# LocalWebMonitorex conventions

@AGENTS.md

These rules carry the applicable general quality standards from Forrozin. Its domain, database, Fly.io and deployment rules do not apply to this local utility.

## Code and behavior

- Code identifiers, test names and user-visible text are in English.
- Write a failing behavior test before each feature or bug fix. Test the public result, not an implementation detail.
- Keep functions usually within 10 lines and extract a named step before a function becomes difficult to scan. Keep calculations pure and I/O at the edge.
- Prefer multiple clauses for distinct states, `case` for one decision and `with` for a short chain of fallible operations.
- Start pipelines with a value and put each `|>` on its own line. Avoid `hd/1`, skipped tests and expected warning logs in green tests.
- Put specs on public domain functions. Use specific error atoms and avoid silent failure.

## Boundaries

- `PortProbe` and `ProcessInspector` are swappable discovery boundaries. `ProcessInspector.System` selects the macOS, Linux, or Windows adapter. `Scanner` owns bounded concurrency; `Monitor` owns scheduling and broadcasts; `Previews` owns screenshot work; `Sweeper` owns the wide sweep. LiveViews call those public APIs.
- `Monitor` and `Scanner` never probe outside the configured range, and previews never request anything but local addresses. The dashboard port excludes itself from discovery.
- `Sweeper` is the one approved exception, a product decision by the owner: a slow background sweep of `127.0.0.1` ports 1–65535 that skips the watched range and the dashboard port. It stays loopback-only, probes in small paced batches with fixed low concurrency and short timeouts, waits a long interval between passes, takes no screenshots, and stops at once when its switch is turned off. Do not raise its rate, widen it beyond loopback, or add work per finding without a new product decision.
- Keep the Phoenix endpoint bound to `127.0.0.1`; preview navigation may use only local HTTP(S) addresses.
- The port, watched-range and sweep preferences live in separate local files. Validate before writing. The port and range apply on the next start; the sweep switch applies immediately.

## Validation

Run focused ExUnit files first, then `mix test`, `mix format --check-formatted` and `mix compile --warnings-as-errors`. For UI changes, inspect accessibility, console errors and screenshots at desktop and 375 px in WebKit. Verify there is no horizontal overflow.
