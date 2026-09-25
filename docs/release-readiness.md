# Development release readiness

Version `0.5.0-dev` is a development snapshot now targeting Redot `26.3-rc.1`. It is not release-certified: the former streaming implementation used the ordinary list endpoint, while the new opt-in native gRPC `streamList` helper has local fixture and exact-Redot runtime evidence, plus passing Windows/Linux native CI and reproducible binaries. Interval-respecting polling remains the safe default. The independently reproduced 26.3 headless-editor crash, live Google verification, and clean Windows/Linux exported-game checks remain release gates. See [current validation](validation-26.3.md).

## Deterministic evidence

The table below is historical 26.2 implementation evidence, not current release qualification. Its old 16-check streaming fixture modeled the wrong HTTP transport and is not counted as proof of native streaming. Current 26.3 native gRPC, helper process, polling-generation, and exported-helper-path evidence is recorded separately in [validation](validation-26.3.md); path tests alone do not establish exported-game compatibility.

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

The historical suite reported 555 assertions. Current suite counts must be read from the fresh run logs after remediation. `run_project_check.gd` loads every addon/example GDScript; neither it nor a fixture proves real streaming or editor/export compatibility.

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
