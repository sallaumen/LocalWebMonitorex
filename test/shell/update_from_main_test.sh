#!/usr/bin/env bash
# Exercises bin/update-from-main against a local "GitHub" repository, a fake
# build script, a fake server and a fake launchctl. Run: test/shell/update_from_main_test.sh
set -euo pipefail

updater="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)/bin/update-from-main"
root="$(mktemp -d "${TMPDIR:-/tmp}/lwm-updater-test.XXXXXX")"
failures=0
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

cleanup() {
  stop_fake_service
  rm -rf "$root"
}
trap cleanup EXIT

stop_fake_service() {
  if [[ -f "$root/service.pid" ]]; then
    kill "$(cat "$root/service.pid")" 2>/dev/null || true
    rm -f "$root/service.pid"
  fi
}

write_fakes() {
  mkdir -p "$root/fakes"
  cat >"$root/fakes/server.py" <<'PY'
import http.server, os, sys
if os.path.exists("SMOKE_FAILS"):
    sys.exit(1)
revision = open("REVISION").read().strip()
body = f'<meta phx-r name="localwebmonitorex-revision" content="{revision}">LocalWebMonitorex'.encode()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
http.server.HTTPServer(("127.0.0.1", int(os.environ["PORT"])), Handler).serve_forever()
PY
  # Restarts the "service" from the installation link, like launchd would.
  cat >"$root/fakes/launchctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$root/launchctl.calls"
[[ -f "$root/service.pid" ]] && kill "\$(cat "$root/service.pid")" 2>/dev/null
cd "$root/install"
[[ -f RESTART_FAILS ]] && exit 0
PORT="\$(cat "$root/port")" python3 "$root/fakes/server.py" >/dev/null 2>&1 &
echo \$! >"$root/service.pid"
EOF
  chmod +x "$root/fakes/launchctl"
}

commit_to_main() {
  local marker=$1
  [[ -z $marker ]] || touch "$root/origin/$marker"
  git -C "$root/origin" add -A
  # Runs in a command substitution, so the counter lives in a file.
  echo x >>"$root/commit-count"
  git -C "$root/origin" commit --quiet --allow-empty \
    -m "change $(wc -l <"$root/commit-count" | tr -d ' ') ${marker:-plain}"
  git -C "$root/origin" rev-parse HEAD
}

setup_case() {
  stop_fake_service
  rm -rf "$root/origin" "$root/versions" "$root/state" "$root/install" "$root/launchctl.calls"
  mkdir -p "$root/origin/bin" "$root/versions"
  cp "$updater" "$root/origin/bin/update-from-main"
  cat >"$root/origin/bin/build-installation" <<'SH'
#!/usr/bin/env bash
cd "$(dirname "$0")/.."
[[ ! -f BUILD_FAILS ]] && touch built
SH
  chmod +x "$root/origin/bin/build-installation"
  git -C "$root/origin" init --quiet -b main
  first=$(commit_to_main "")
  install_version "$first"
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])' >"$root/port"
}

install_version() {
  mkdir -p "$root/versions/$1"
  git -C "$root/origin" archive "$1" | tar -x -C "$root/versions/$1"
  echo "$1" >"$root/versions/$1/REVISION"
  ln -sfn "$root/versions/$1" "$root/install"
}

run_updater() {
  LOCALWEBMONITOREX_INSTALL_DIR="$root/install" \
    LOCALWEBMONITOREX_VERSIONS_DIR="$root/versions" \
    LOCALWEBMONITOREX_UPDATE_DIR="$root/state" \
    LOCALWEBMONITOREX_UPDATE_REMOTE="$root/origin" \
    LOCALWEBMONITOREX_CONFIG="$root/port" \
    LOCALWEBMONITOREX_LAUNCHCTL="$root/fakes/launchctl" \
    LOCALWEBMONITOREX_SERVER_COMMAND="python3 $root/fakes/server.py" \
    LOCALWEBMONITOREX_SMOKE_SECONDS=10 \
    LOCALWEBMONITOREX_HEALTH_SECONDS=4 \
    bash "$updater" >"$root/updater.log" 2>&1 || true
}

field() { sed -n "s/^$1=//p" "$root/state/status"; }

expect() {
  local description=$1 actual=$2 expected=$3
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL [$current_case] $description: expected '$expected', got '$actual'" >&2
    sed 's/^/    log: /' "$root/updater.log" >&2
    failures=$((failures + 1))
  fi
}

restarts() { grep -c kickstart "$root/launchctl.calls" 2>/dev/null || echo 0; }

write_fakes

current_case="up to date"
setup_case
run_updater
expect "phase" "$(field phase)" up_to_date
expect "behind" "$(field behind)" 0
expect "installed" "$(field installed_sha)" "$first"
expect "restarts" "$(restarts)" 0

current_case="behind main"
setup_case
commit_to_main "" >/dev/null
third=$(commit_to_main "")
run_updater
expect "phase" "$(field phase)" up_to_date
expect "installed" "$(field installed_sha)" "$third"
expect "link" "$(readlink "$root/install")" "$root/versions/$third"
expect "revision" "$(cat "$root/install/REVISION")" "$third"
expect "built" "$([[ -f $root/install/built ]] && echo yes)" yes
expect "restarts" "$(restarts)" 1
expect "previous kept" "$([[ -d $root/versions/$first ]] && echo yes)" yes
expect "runner refreshed" "$([[ -x $root/state/update-from-main ]] && echo yes)" yes
expect "lock released" "$([[ -e $root/state/lock ]] && echo held)" ""

current_case="prunes older versions"
fourth=$(commit_to_main "")
run_updater
expect "installed" "$(field installed_sha)" "$fourth"
expect "previous kept" "$([[ -d $root/versions/$third ]] && echo yes)" yes
expect "oldest removed" "$([[ -d $root/versions/$first ]] && echo kept)" ""

current_case="build fails"
setup_case
broken=$(commit_to_main BUILD_FAILS)
run_updater
expect "phase" "$(field phase)" failed
expect "reason" "$(field reason)" build_failed
expect "behind" "$(field behind)" 1
expect "available" "$(field available_sha)" "$broken"
expect "link" "$(readlink "$root/install")" "$root/versions/$first"
expect "candidate removed" "$([[ -d $root/versions/$broken ]] && echo kept)" ""
expect "restarts" "$(restarts)" 0

current_case="smoke test fails"
setup_case
commit_to_main SMOKE_FAILS >/dev/null
run_updater
expect "phase" "$(field phase)" failed
expect "reason" "$(field reason)" smoke_failed
expect "link" "$(readlink "$root/install")" "$root/versions/$first"
expect "restarts" "$(restarts)" 0

current_case="restart fails"
setup_case
commit_to_main RESTART_FAILS >/dev/null
run_updater
expect "phase" "$(field phase)" failed
expect "reason" "$(field reason)" restart_failed
expect "link restored" "$(readlink "$root/install")" "$root/versions/$first"
expect "restarts" "$(restarts)" 2

current_case="installed commit is not on main"
setup_case
git -C "$root/origin" checkout --quiet -b side
side=$(commit_to_main "")
git -C "$root/origin" checkout --quiet main
commit_to_main "" >/dev/null
install_version "$side"
run_updater
expect "phase" "$(field phase)" diverged
expect "link" "$(readlink "$root/install")" "$root/versions/$side"
expect "restarts" "$(restarts)" 0

current_case="remote unavailable"
setup_case
mv "$root/origin" "$root/origin-away"
run_updater
mv "$root/origin-away" "$root/origin"
expect "phase" "$(field phase)" failed
expect "reason" "$(field reason)" fetch_failed
expect "installed" "$(field installed_sha)" "$first"

current_case="unknown installed commit"
setup_case
rm "$root/install/REVISION"
run_updater
expect "phase" "$(field phase)" failed
expect "reason" "$(field reason)" installed_revision_missing

if ((failures > 0)); then
  echo "$failures update-from-main expectation(s) failed" >&2
  exit 1
fi
echo "update-from-main: all cases passed"
