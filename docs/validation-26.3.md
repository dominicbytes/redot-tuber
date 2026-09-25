# Redot 26.3 validation

2026-09-24 development-source checkpoint, not a stable release. Target: official Windows x64 Redot `26.3.rc.1.official.704b10a8e`. Historical 26.2 records are not current certification.

## Implemented and verified locally

- Replaced the incorrectly modeled HTTP streaming route with Google's real server-streaming gRPC RPC through a bundled Go 1.27.1 helper. Windows/Linux x64 binaries require no player-installed Go runtime; source, pinned dependencies, licenses and checksums are included.
- Ordinary interval-respecting polling remains the default. Streaming is opt-in with `prefer_streaming = true`. Credentials enter the helper over private stdin, production TLS destination is fixed, messages/errors are bounded, and owned processes are stopped on cancellation.
- Fixed stale polling generations and preserved cursor/authorization/quota checks across stream reconnects. Credential and stream helpers resolve outside exported PCKs through registered sidecars.
- Independent source aggregate: **15/15 clean processes**, **597 assertions plus 93-script project check**, on exact Redot 26.3. This excludes live-vault and fixture-dependent tests.
- Separate real gRPC/helper integration: **13/13** checks, including multiple responses, UTF-8, exact uint64 values, cursor and process cancellation. Separate real OS-pipe boundary test: **5/5** checks, including a 1 MiB JSON line plus newline and subsequent response.
- Native Go tests, `go vet` and module verification passed. Independent review found and repaired a watchdog context race, a legal-frame boundary rejection, and protobuf duration narrowing. Tests also cover idle cancellation, retry reset after a valid page, status-code spelling, enums, gift/poll mapping, and sanitized errors.

The GitHub native-helper workflow runs Windows/Linux tests, Linux's race detector, and reproducible-build comparisons against the bundled binaries. Its result is separate from these local checks; inspect the workflow for the tested commit. Linux CI does not certify Redot game exports or desktop Secret Service.

Published source `87fbab9117d7627b97214a5f61c63919f7ce4d22` passed [both native CI jobs](https://github.com/dominicbytes/redot-tuber/actions/runs/36080641898): Windows/Linux gRPC/process tests, Linux race detection, and byte-for-byte rebuilt helper comparisons. This closes the native-helper Linux execution/reproducibility gate, not the Redot export or live-service gates below.

## Transport policy

A 90-second no-response watchdog and three reconnect attempts bound a stalled transport. A valid response resets the retry counter. If all attempts remain silent/fail, configured polling fallback takes over; with fallback disabled, an explicit transport error stops reception. Silence is not proof of chat end, and no undocumented server heartbeat is assumed. Authorization, permission, quota and rate-limit failures do not silently fall back. A single helper process also has a 24-hour lifetime cap.

## Reproduce

Resolve `REDOT_BIN` to the exact build and run `& $env:REDOT_BIN --version` first. An existing successfully imported project cache was used for source checks. A separately reproduced Windows headless-editor crash also affects an empty project; a fresh `--headless --editor` import is not a reliable workaround or a passed prerequisite.

Once the project is imported, run each `addons/redot-tuber/tests/run_*.gd` with `--headless --path <repo-root> --script res://addons/redot-tuber/tests/<name>.gd --quit-after 10000`, an isolated application-data profile, and a 60-second wall timeout. Require native exit 0, explicit completion, and no errors/warnings. Real credential-vault tests require separate consent and prerequisites; do not substitute mocks. The two native-stream fixture tests require the setup in the [helper README](../native/stream-helper/README.md), not just an ordinary script invocation.

## Dependency advisory

The 2026-09-24 `govulncheck` source scan reported no reachable vulnerability and one imported-but-unreachable gRPC advisory, [GO-2026-6443](https://pkg.go.dev/vuln/GO-2026-6443), in pinned gRPC 1.84.0. It concerns xDS-configured servers processing missing authority headers; the shipped helper is a client and does not host that server path. This is a scoped reachability assessment, not a claim that the dependency has no advisories. Re-scan when changing dependencies or adding server functionality.

## Remaining release gates

- Live Google OAuth/consent, real channels/events and service limits.
- Clean Windows/Linux exported games with matching 26.3 templates, actual sidecar copy/callback execution and Linux executable permissions.
- Linux desktop Secret Service and persistent-login/restart/clear-data behavior.
- Resolution or verified workaround for the separate Windows 26.3 headless-editor crash.

No release tag, live-account mutation or complete cross-platform compatibility certification is implied by source publication. macOS and ARM64 remain later targets.
