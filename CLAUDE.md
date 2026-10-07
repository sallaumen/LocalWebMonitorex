# LocalWebMonitorex conventions

@AGENTS.md

These rules carry the applicable general quality standards from Forrozin. Its domain, database, Fly.io and deployment rules do not apply to this local utility.

## Code and behavior

- Code identifiers and test names are in English; user-visible text is in Portuguese.
- Write a failing behavior test before each feature or bug fix. Test the public result, not an implementation detail.
- Keep functions usually within 10 lines and extract a named step before a function becomes difficult to scan. Keep calculations pure and I/O at the edge.
- Prefer multiple clauses for distinct states, `case` for one decision and `with` for a short chain of fallible operations.
- Start pipelines with a value and put each `|>` on its own line. Avoid `hd/1`, skipped tests and expected warning logs in green tests.
- Put specs on public domain functions. Use specific error atoms and avoid silent failure.

## Boundaries

- `PortProbe` is the swappable discovery boundary. `Scanner` owns bounded concurrency; `Monitor` owns scheduling and broadcasts; `Previews` owns screenshot work. LiveViews call those public APIs.
- Never scan outside the configured range, except a browser screenshot's local asset requests. The dashboard port excludes itself from discovery.
- Keep the Phoenix endpoint bound to `127.0.0.1`; preview navigation may use only local HTTP(S) addresses.
- The preference file contains only the dashboard port. Validate before writing and apply it on the next start.

## Validation

Run focused ExUnit files first, then `mix test`, `mix format --check-formatted` and `mix compile --warnings-as-errors`. For UI changes, inspect accessibility, console errors and screenshots at desktop and 375 px in WebKit. Verify there is no horizontal overflow.
