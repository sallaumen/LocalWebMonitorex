# Project guidance

Read `CLAUDE.md` before changing the application. This is a local Phoenix LiveView app; never turn it into a remotely exposed service by changing the loopback bind address without an explicit product decision.

## Quality

- Keep code, modules, atoms, events, tests and comments in English. Keep interface copy in Portuguese.
- Use TDD for behavior changes. Name tests by behavior, assert observable outcomes, and avoid skipped tests.
- Keep functions focused and short. Separate pure calculations from I/O. Prefer pattern-matched clauses and explicit return contracts.
- Give public domain functions specs. Inject port probing through the `PortProbe` behavior.
- Use `Req` for HTTP requests. Bound concurrency and timeouts, and do not follow a discovered service's redirect to a remote host.
- Keep screenshots sequential and local. Do not commit captures of applications running on a contributor's computer.
- Validate incrementally: focused tests, affected tests, then the full suite for shared infrastructure. Run `mix format --check-formatted` and `mix compile --warnings-as-errors` before a pull request.

## Delivery

Review the diff and local UI before merging. Use the configured Playwright MCP with WebKit for desktop and 375 px mobile checks. Close the browser session when finished. Keep repository changes in small pull requests when a remote is available.
