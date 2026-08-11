# Development release readiness

Version `0.5.0-dev` is a local feature-complete development snapshot for Redot `26.2.stable.official.4f5b14aba`. It is not a stable/public release and does not claim live Google or cross-platform certification.

## Deterministic evidence

| Area | Runner | Result |
|---|---|---:|
| Contract, framing, scheduling, event normalization, quota policy | `run_ms001.gd` | 135 checks |
| Incremental HTTP/framing fixture | `run_ms001_http_harness.gd` | 15 checks |
| Addon, models, transport, discovery, redaction | `run_ms002.gd` | 74 checks |
| Retry, concurrency, cancellation, request/response bounds | `run_ms002_http_harness.gd` | 23 checks |
| OAuth, scopes, descriptors, slot isolation, helper protocol | `run_ms003.gd` | 73 checks |
| IPv4 loopback callback | `run_ms003_loopback.gd` | 12 checks |
| OAuth token exchange/refresh/revoke fixture | `run_ms003_oauth_harness.gd` | 22 checks |
| Windows Credential Manager helper | `run_ms003_credential_helper.gd` | 11 checks |
| Discovery, typed events, capabilities, every service action, lifecycle guards | `run_ms004.gd` | 131 checks |
| Bounded memory/disk media cache | `run_ms004_media_harness.gd` | 21 checks |
| Incremental stream source, resume/reconnect/cancel/fallback inputs | `run_ms004_stream_harness.gd` | 16 checks |
| Real loopback REST writes, auth preflight, serialization, quota rejection | `run_ms005_http_harness.gd` | 22 checks |

The combined deterministic suite contains 555 passing assertions. `run_project_check.gd` loads every addon/example GDScript. The integration-lab main scene also completes a bounded headless smoke run without warnings or errors.

## Implemented release content

- Standalone MIT addon under `addons/redot-tuber/`, with no Twitcher runtime dependency.
- Public reads and per-client OAuth authorization/persistence.
- Windows/Linux x86-64 helper binaries, versioned protocol, source, hashes, and architecture status.
- Complete documented discovery, event, chat/poll, moderation, broadcast, stream, monetization, quota, media, and clear-data surface.
- Reversible editor setup tool, optional runtime connection control, and full integration lab.
- API, capability, OAuth, data-lifecycle, lineage, license, and notice documentation.

## External gates before a stable release

1. Run real Google Desktop OAuth consent, restore, refresh rotation, denial, expiry, and revocation using a developer-owned test project.
2. Exercise every supported read/write against controlled live broadcasts and verify observed channel-side outcomes and actual Cloud Console quota usage.
3. Run the Linux x86-64 helper against a real unlocked/locked/unavailable Secret Service desktop matrix; repeat persistent-login/restart/clear-data tests.
4. Build and exercise Windows and Linux x86-64 game exports, including system-browser handoff, loopback firewall behavior, credential-helper placement/permissions, and clean removal.
5. Complete publisher privacy policy, OAuth verification/limited-use review, user support, incident response, branding, and data-deletion obligations.
6. Perform fresh-project install/disable/re-enable and clean archive checks on both operating systems.
7. Only after those gates pass, create an immutable GitHub release/tag/checksum and a matching Redot Asset Library entry. macOS and ARM64 remain later compatibility milestones.

Failures in an external gate must keep the version in `0.x-dev`; deterministic fixtures are not substitutes for account-side evidence.
