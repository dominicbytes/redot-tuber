# redot-tuber implementation plan

**Status:** MS-001 through MS-005 implementation complete; MS-006 local release preparation complete; live Linux/Google/export/publication certification gates open\
**Updated:** 2026-08-11\
**Target engine:** Redot `26.2.stable.official.4f5b14aba`\
**Runtime language:** typed GDScript

The user has confirmed the destination and shared understanding. The full-featured product scope, developer-owned OAuth application model, platform release sequence, persistent credential architecture, initial x86-64 helper boundary, account-session model, component-level Twitcher reuse strategy, MIT repository license, and public distribution model are fixed. Implementation started on 2026-08-10. MS-001 through MS-005 now have runnable Redot evidence. Live Google consent/account-side behavior, a real Linux desktop keyring, cross-platform exports, and public distribution remain evidence-gated in MS-006.

## 1. Destination

`redot-tuber` is a standalone Redot addon that game developers install in a project. A game exported with the addon can present a runtime authorization flow that lets each consenting user connect their own YouTube account and channel, after which the game can receive YouTube Live events and perform the YouTube actions that user authorized.

A finished first release is full-featured across the official YouTube Live surface relevant to interactive games: channel and live-stream discovery, broadcast/stream lifecycle management, low-latency live-chat reception with a compliant fallback, typed chat and monetization events, chat and poll creation, moderation, media helpers, quota diagnostics, consent, revocation, and data deletion. Unsupported or unavailable routes remain explicit capability gaps; the addon never scrapes YouTube.

## 2. Audience and constraints

### Audiences

- **Integrating developer:** installs and configures the addon, selects requested capabilities, and builds YouTube interaction into a game.
- **Game user / channel owner:** authorizes the exported game at runtime, selects or discovers their channel/live broadcast, and can disconnect or revoke access.
- **Game systems:** consume typed signals/resources and call permission-checked actions without handling raw HTTP or OAuth tokens.

### Fixed constraints

- Standalone install at `res://addons/redot-tuber/`; no dependency on `redot-twitcher` or another streaming addon.
- Implementation is reuse-first at the source level: `dominicbytes/twitcher` commit `5c80a758b1800ac74bdfa36cf2f0274013ba58dc` is the pinned donor baseline for audited generic Redot foundations. Approved code is ported into the `redot-tuber` namespace with characterization tests and provenance; the finished addon has no runtime dependency on Twitcher and is never produced by mechanically renaming the whole Twitch addon.
- The standalone repository and addon are licensed under the MIT License. The Kani/Twitcher MIT notice and applicable Redot-fork attribution remain intact for copied or substantially adapted source.
- GitHub Releases is the canonical immutable distribution source for stable builds. Each stable release is also listed separately in the Redot Asset Library and points to the matching tested release commit/archive.
- The same separate-repository, separate-release, and separate-Asset-Library-listing pattern is the default for `redot-kicker`, `redot-rumbler`, and `redot-joysticker`; each addon retains its own version, license record, metadata, icon, compatibility evidence, and support boundary.
- Redot `26.2.stable.official.4f5b14aba`; installed Redot APIs and successful runtime checks override newer Godot documentation.
- The addon API, editor integration, authorization state machine, and YouTube services use typed GDScript. The only approved native components are standalone Windows/Linux credential-helper executables; no C#, .NET, or GDExtension library is introduced.
- Official Google/YouTube APIs only; no popup-chat parsing, DOM scraping, or private frontend requests.
- Full functionality is capability- and scope-gated. Authorization never implies that every route is available to every account.
- Each integrating game developer or publisher registers, owns, and configures the Google OAuth application used by their shipped game. The addon supplies the runtime flow but never funnels unrelated games through a maintainer-owned production client.
- The first certified desktop release targets Windows and Linux with feature parity. macOS certification follows only after both initial targets are solid and does not block that release.
- Initial Windows and Linux credential-helper certification is x86-64 only. ARM64 follows after the first-release credential flow, packaging, and OS-vault behavior are solid.
- Web and mobile exports are separate platform ports after Windows and Linux are solid; their OAuth redirects, browser handoff, secure storage, and lifecycle work do not block the first certified release.
- A successful user login must persist between game sessions on supported desktop targets unless the user disconnects/revokes access or the operating-system secret service is unavailable.
- Persistence uses a versioned non-secret `user://` session descriptor plus a refresh token stored through Windows Credential Manager or Linux Secret Service. Helpers communicate through a versioned pipe protocol; no plaintext token fallback exists.
- Each `YouTubeLiveClient` owns exactly one active YouTube account/channel and one stable non-secret session slot. A game may connect concurrent accounts by creating independent clients with distinct slots; a client does not manage an internal account collection or share a global auth singleton.
- Every copied or substantially adapted Twitcher file is recorded in a reuse manifest with its donor path, pinned commit, license/notice obligations, disposition, and modification summary. The Kani MIT notice and applicable Redot-fork attribution are preserved.
- Secrets, tokens, API keys, and user data never enter source files, scenes, resources, `ProjectSettings`, examples, reports, or ordinary logs.

### Not yet specified

None. Remaining unknowns are evidence gates recorded in Risks with milestone deadlines; none prevents MS-001 from starting.

## 3. Design pillars

1. **Runtime user ownership:** the channel owner connects and revokes their account inside the exported game; editor authorization is never the only path.
2. **Official and capability-honest:** expose the complete documented YouTube Live surface while preserving native YouTube concepts and reporting unavailable permissions/routes explicitly.
3. **Safe by default:** least-privilege scopes, explicit consent for writes/destructive actions, secret-safe diagnostics, revocation, and clear-data controls are core behavior.
4. **Game-friendly typed API:** game code receives stable typed resources/signals and typed errors rather than raw dictionaries, HTTP codes, or OAuth details.
5. **Observable reliability:** transport, quota, auth, reconnect, and degraded states are visible and deterministically testable.

## 4. Interaction rules

### Connection lifecycle

1. The integrating game supplies its OAuth/API application configuration and a stable non-secret session slot through the approved runtime configuration boundary.
2. The game requests a named capability set; `redot-tuber` derives the minimum scopes needed and shows the channel owner what will be requested.
3. The user authorizes in the system browser. The addon validates OAuth state and PKCE, completes the callback, retrieves channel identity, and reports the connected capability set.
4. The game selects or discovers the relevant live broadcast and begins event delivery.
5. Token refresh, transport reconnect, quota pressure, end-of-chat, authorization loss, and API denial cause explicit state transitions rather than silent failure.
6. Disconnect revokes when requested, stops only that client's transports/actions, clears its memory, and deletes the persisted local data associated with its session slot according to the selected storage policy.

### Event and action rules

- `streamList` is preferred only after it passes the Redot framing/cancellation/resume gate; `liveChatMessages.list` is the supported fallback and obeys `pollingIntervalMillis`.
- Initial history, reconnect replay, duplicate IDs, combo-update events, deleted messages, and unknown future event types have explicit deterministic behavior.
- YouTube-native events remain distinct: text, Super Chat, Super Sticker, membership/milestone, membership gifting/receipt, gift, poll, deletion, ban, and system/lifecycle events.
- Every write checks current authorization, scopes, channel/broadcast state, quota state, and required confirmation before sending.
- Destructive operations return typed success/failure and must be verifiable against the account-side state.
- Search/discovery is manually refreshed or cached; it is never tight-polled.

### Failure and recovery

- No credentials: remain disconnected and emit a configuration/authentication requirement.
- User denies consent: return to disconnected without retry loops or partial credentials.
- Callback state mismatch: reject the exchange and clear the pending verifier/code.
- Refresh failure or revocation: stop privileged actions and require reauthorization.
- Quota/rate exhaustion: pause affected work until the server/policy permits retry; never substitute scraping.
- Stream/chat ended: emit a terminal state and stop consuming messages.
- Unknown event or optional field: emit a safe generic event or omit the optional value; do not tear down the session.

## 5. Presentation

### Editor-facing

- A small setup/status dock or project tool explains required Google Cloud configuration, selected feature modules/scopes, callback requirements, test mode, and current documentation links.
- The plugin must not silently add an autoload or save credentials into the project.
- Enabling and disabling the plugin must be reversible; everything registered in `_enter_tree()` is removed in `_exit_tree()`.

### Runtime-facing

- Provide headless APIs plus optional reusable Controls for connect, consent status, account/channel identity, capability status, disconnect/revoke, and clear-data actions.
- Optional UI is theme-neutral and replaceable; games are not forced to use a branded layout.
- Authorization, denial, quota, reconnect, and destructive-action states have text labels and cannot rely on color alone.
- Browser launch failure exposes a copyable authorization URL and a typed error; it does not expose verifier, state, token, or secret values.

### Audio, animation, and assets

No game art/audio pipeline is required. Any icons or YouTube branding used by the addon must follow current branding terms and have recorded provenance. Network-delivered profile/sticker media is user/API data, not a redistributable addon asset.

## 6. Technical design

### Planned package boundary

```text
addons/redot-tuber/
  plugin.cfg
  plugin.gd
  editor/
  runtime/
  auth/
  transport/
  services/
  models/
  media/
  diagnostics/
  ui/
  tests/
  bin/
    windows/
    linux/
native/credential-helper/
examples/redot-tuber-demo/
docs/lineage/twitcher-reuse.md
THIRD_PARTY_NOTICES.md
```

These folders are planning boundaries, not permission to generate scaffolding before the plan is approved.

### Runtime responsibilities

- `YouTubeLiveClient`: public facade and connection/capability state machine for exactly one active account/channel and one persistent session slot; games create distinct clients for concurrent accounts.
- OAuth session: PKCE/state, browser launch, loopback callback where supported, code exchange, refresh, revocation, and scope calculation.
- Credential provider: a non-secret session descriptor plus standalone helper binaries for Windows Credential Manager and Linux Secret Service; an unavailable/locked store is typed and never falls back to plaintext.
- YouTube API client: authenticated/unauthenticated requests, typed errors, rate/backoff metadata, cancellation, and redaction.
- Live-chat transports: incremental `streamList` implementation and policy-compliant `list` fallback behind one event-source contract.
- Services: channels/videos/discovery, live chat, polls, bans/moderators, broadcasts, streams, and broadcast-stream binding/transition operations.
- Models: immutable or narrowly mutable typed Resources/RefCounted values for identities, broadcasts, streams, messages, monetization, membership, polls, moderation, capabilities, quota, and errors.
- Media cache: bounded content-type/size/concurrency/retention behavior plus clear-data support.
- Diagnostics: request category, quota units/buckets, retry state, transport mode, event lag, and redacted error summaries.

### Signal/event boundary

The final API names will be frozen before implementation. At minimum, game code needs typed state, authorization, broadcast/stream, message, monetization, membership, poll, moderation, quota, and error signals. A generic `unknown_event` path is mandatory for forward compatibility. Raw response bodies are test/debug data only and are never emitted through the normal public API.

### Redot constraints already verified

- `HTTPRequest` and `HTTPClient` for REST and streaming experiments.
- `TCPServer` for desktop loopback callback handling.
- `OS.shell_open` for system-browser authorization.
- `HashingContext`, `Crypto`, and Base64 helpers for PKCE/state and local encryption experiments.
- No verified cross-platform OS keychain in the installed Redot API.
- `OS.execute_with_pipe` exists in the installed API and can support a bounded helper process without placing tokens in command-line arguments.
- No Godot 4.6/4.7-only editor API may be planned without first verifying it in the installed Redot build.

### Native credential persistence feasibility

- **Accepted boundary:** keep the public addon and authorization state machine in typed GDScript, but ship one small credential-helper executable per operating system. Communicate through a versioned stdin/stdout protocol; never pass tokens through arguments, environment variables, files, or logs. This avoids coupling the addon to the Redot GDExtension ABI.
- **Windows:** use generic credentials through `CredWriteW`, `CredReadW`, and `CredDeleteW`, scoped by publisher/game/account identifiers. This side is comparatively direct, but must validate credential-blob limits, replacement, deletion, multiple accounts, and Windows error mapping.
- **Linux:** use the freedesktop Secret Service contract, preferably through `libsecret` or a carefully bounded D-Bus client. This side must handle no service, locked collections, user prompts, cancellation, missing library/runtime dependencies, desktop-environment differences, and sandboxed packages.
- **Failure contract:** an unavailable or locked OS store is a typed capability state, never permission to fall back to plaintext. Disconnect/revoke must delete the matching stored refresh token, and diagnostics must remain secret-free.
- **Why a browser cookie is not the token store:** the OAuth flow uses the external system browser, whose Google cookies remain isolated inside that browser. Redot has no installed cookie-jar API, and the native game cannot safely read or reuse the browser's cookies. Google's installed-app flow instead returns refresh/access tokens and requires them to be stored securely between invocations.
- **Cookie-like hybrid:** store a versioned non-secret session descriptor under `user://` containing only the credential-record key, schema version, connection state, granted capability summary, and minimal account/channel identifiers approved by the data-lifecycle policy. Store the refresh token—and any DPoP private key if adopted—only in the OS secret store. Keep access tokens in memory and replace them through refresh-token rotation.
- **Rejected substitute:** an encrypted `user://` token file with its decryption key embedded in the game or stored beside it is not materially safer than plaintext. A user passphrase could protect such a file, but it would add password/recovery UX and would no longer be browser-like seamless login.
- **Planning estimate:** approximately two to four engineering weeks for production-quality Windows/Linux x86-64 helper binaries, IPC, packaging, failure handling, tests, and documentation. Supporting ARM64, Flatpak/Snap-specific behavior, signing, or a GDExtension implementation broadens this to roughly four to six or more weeks.

### Redot-Twitcher auth comparison

The local `redot-twitcher` source provides a useful functional reference but not the security boundary for `redot-tuber`:

- `TwitchAuth.authorize()` delegates to a reusable OAuth layer supporting authorization-code, client-credentials, device-code, and implicit flows. Its game setup defaults to device-code authorization and also offers implicit authorization.
- `OAuth.login()` loads cached tokens, accepts a still-valid token when the scopes match, attempts refresh after expiry, and only then starts a full authorization flow. Browser flows launch the system browser, listen on a loopback HTTP server, and validate `state`; the device flow displays a user code and polls the token endpoint.
- Access and refresh tokens are persisted in `user://auth.conf`. They are AES-ECB-encrypted, but the generated decryption key is itself stored in `user://encryption_key.cfg` in the same user profile. This deters casual file inspection but is not an operating-system credential-vault boundary because a copy of both files is sufficient to recover the tokens.
- The token handler schedules refresh before expiry, and the Twitch-specific handler periodically validates or revokes the token. No PKCE verifier/challenge implementation was found in the inspected OAuth code.
- Separate token Resources can select separate cache sections, but `TwitchService` exposes a global `instance` and one active settings/token set per service, so concurrent multi-account use is not a first-class facade contract.

`redot-tuber` may adapt Twitcher's authorization-state orchestration, cancellation, refresh, validation, revocation, and Resource separation ideas. It must not copy the key-beside-cache token storage, implicit-flow default, distributed client-secret assumptions, lack of PKCE, or singleton account model. Its installed-app flow remains external-browser authorization with state and PKCE, memory-only access tokens, one OS-vault refresh token per client session slot, and no global auth singleton.

### Pinned Twitcher reuse map

The reuse baseline is the clean local checkout of `dominicbytes/twitcher` at commit `5c80a758b1800ac74bdfa36cf2f0274013ba58dc`. It is MIT-licensed and derived from Kani's original Twitcher. The standalone `redot-tuber` repository and addon are also MIT-licensed. Directly copied or substantially adapted files must be traceable in `docs/lineage/twitcher-reuse.md`; `THIRD_PARTY_NOTICES.md` must reproduce the applicable MIT text and identify both the original project and the Redot continuation.

**Port first, then rename into the Redot-Tuber namespace:**

- reversible `EditorPlugin` registration/removal and setup-window organization;
- small editor/resource patterns, typed cancellation token, OAuth scope collection, query parsing, and typed data-serialization patterns;
- the minimal loopback HTTP-server skeleton and the Redot compatibility-probe structure.

Even these candidates require characterization tests before behavior changes. Reuse is based on individual files and functions, not folder-level copying.

**Adapt behind replacement tests:**

- OAuth orchestration and token-handler lifecycle: retain state transitions, timeout/cancellation, refresh scheduling, validation, and revocation concepts; replace endpoints and flows with Google authorization code plus PKCE, bind only to loopback, enforce one session slot per client, and replace persistence completely.
- HTTP request/response wrapper: retain typed request/response objects and signals, but implement real bounded concurrency, deterministic cancellation, retry/backoff, quota metadata, timeout behavior, and secret redaction. The donor implementation's claim of sequential buffering and its retry path are not accepted without tests.
- API generator: reuse its parser/model/template architecture, adapting it to Google's YouTube discovery schema and checked-in generation fixtures. Generated Twitch models and endpoint wrappers are never carried over.
- Media loader: reuse image-fetch/decode/transform ideas only after adding content-type, byte-size, concurrency, retention, eviction, corruption, and clear-data bounds. Twitch emotes, Cheermotes, badges, fallback art, ImageMagick integration, and the bundled GIF importer are not inherited by default.
- Chat-command framework: reuse argument, alias, cooldown, help, and callback organization while replacing Twitch tags/permission flags and EventSub coupling with YouTube-native authors, roles, and events.
- Editor setup and inspectors: reuse workflow layout and reversible registration, but remove editor token persistence and rewrite all Twitch-specific copy, Resources, credentials, and capability selection.

**Reject from the donor baseline:**

- Twitch Helix, EventSub, IRC, WebSocket, rewards, and generated Twitch schemas or semantics;
- global `instance` service ownership, implicit authorization, shipped-client-secret assumptions, wildcard callback binding, `user://auth.conf`, `user://encryption_key.cfg`, and the AES key provider;
- unbounded caches, donor assets/branding, and third-party GIF code unless a later YouTube requirement independently justifies and licenses them.

This reuse strategy is intended to shorten foundation work while leaving every YouTube contract, security property, and public API independently specified and verified.

## 7. Preflight research brief

The completed preflight investigated:

- official YouTube Live chat, monetization, moderation, broadcast, stream, OAuth, quota, policy, and data-lifecycle capabilities;
- `streamList` versus polling feasibility in native Redot;
- existing Redot/Godot addons and their licenses/protocol choices;
- reusable ideas from `redot-twitcher` without creating a dependency;
- security boundaries for distributed desktop credentials and user data.

Evidence had to come from current official documentation or a clearly licensed local source, work with typed GDScript on the installed Redot build, avoid scraping/private endpoints, and answer each architecture decision or leave it explicitly blocked. The detailed results are in [`preflight-report.md`](preflight-report.md).

## 8. Preflight findings

- **Adopt:** official YouTube Live/Data APIs, installed-app OAuth with PKCE, `streamList` subject to a Redot spike, `list` as a compliant fallback, native event types, BYO application configuration as the preflight default, quota diagnostics, revocation, and data deletion.
- **Adapt:** the pinned `dominicbytes/twitcher` commit component by component for editor/package ergonomics, loopback/OAuth lifecycle scaffolding, request/model-generation patterns, bounded media and command foundations, and compatibility probes; keep a reuse manifest, characterization tests, and no shared runtime.
- **Reject:** DOM/popup scraping, private frontend calls, unlicensed candidate code, universal Twitch-style reward types, embedded secrets, project-resource token storage, and Twitcher's local-key-beside-token-cache security boundary.
- **Distribution decision:** GitHub Releases is the canonical source for immutable tags, archives, checksums, issues, and lineage; each stable release is also listed in the Redot Asset Library for in-editor discovery. The same per-plugin pattern is the portfolio default for the other three streaming-platform addons.
- **Blocked evidence:** real Google consent/account-side behavior, live quota measurements, Linux desktop Secret Service behavior, export certification, and final Google verification/privacy obligations for the accepted GitHub/Asset-Library distribution model. Incremental `streamList` framing/reconnect/cancel behavior is accepted by deterministic Redot loopback evidence but still requires the live matrix.

Relevant source records are `SRC-001` through `SRC-027` in `source-of-truth.xlsx`.

## 9. Milestones

### MS-001 - Deterministic transport and policy harness

**Status:** Complete — 135 contract/unit checks and 15 real incremental-HTTP checks pass on the pinned Redot build.

**Runnable result:** an offline Redot harness feeds lawful recorded/synthetic live-chat responses through both transport paths and displays normalized events, continuation state, quota accounting, and failures.

**Exit checks:** partial/multiple frames, cancellation, resume token, duplicate/history behavior, end-of-chat, `pollingIntervalMillis`, unknown types, bounded buffers, and policy/data-lifecycle checklist pass. The `streamList` path is either accepted or explicitly rejected in favor of polling.

### MS-002 - Installable addon and read-only vertical slice

**Status:** Complete — installable shell, reversible editor workflow, deterministic discovery tooling, hardened REST transport, video resolution, polling event delivery, and the read-only sample pass offline/loopback validation. Live YouTube certification remains part of the later credentialed QA matrix and is not inferred from fixtures.

**Runnable result:** a clean Redot sample installs/enables the addon using the approved, renamed Twitcher foundations, configures public/API access at runtime, resolves a known video's active chat, and displays typed events through the selected transport.

**Exit checks:** the pinned-source reuse manifest and component characterization tests pass; clean enable/disable, no orphan editor registrations, no autoload surprise, no rejected Twitch modules or paths, secret-safe logs/project files, typed connection/error states, bounded run, and warnings/errors review pass.

### MS-003 - Runtime end-user OAuth and channel connection

**Status:** Implementation complete; release certification pending. PKCE/state/IPv4-loopback, token exchange/refresh/rotation/revoke, per-client slot isolation, non-secret descriptors, optional runtime UI, and helper failure contracts pass deterministic Redot tests. The Windows x86-64 helper passes real Credential Manager store/read/replace/delete. The Linux x86-64 helper builds with strict warnings and its protocol returns typed unavailable without a desktop Secret Service; actual Linux keyring behavior and live Google consent/account behavior remain external MS-006 gates and are not claimed as passed.

**Runnable result:** a user launches an exported test game, authorizes their own YouTube account through one `YouTubeLiveClient`, sees the connected channel and granted capabilities, restarts the game without having to authorize again, survives refresh, then disconnects/revokes and clears that client's local data. A second client can independently connect another account through a distinct session slot.

**Exit checks:** the adapted OAuth lifecycle is source-traceable while the donor's implicit flow, wildcard binding, singleton ownership, local cache, and AES key provider are absent. The developer-owned OAuth configuration contract is documented and enforced; PKCE/state/loopback-only callbacks, denial, timeout, refresh rotation, OS-backed store/read/delete, stable slot reuse, duplicate-slot rejection, unavailable/locked-store behavior, revocation, minimum scopes, and no-secret diagnostics pass on Windows and Linux x86-64. Two simultaneous clients prove that tokens, signals, quota state, disconnect, revocation, and data deletion remain isolated.

### MS-004 - Complete discovery, event, and media surface

**Status:** Implementation complete; live certification pending. The shared MS-004/MS-005 service suite passes 131 checks, the bounded media harness passes 21, and the incremental stream harness passes 16 on the pinned Redot build.

**Runnable result:** the sample discovers/selects relevant channels, broadcasts, streams, and chats and presents every supported typed live event/media variant through a capability-aware API.

**Exit checks:** message/monetization/membership/gift/poll/moderation/system fixtures, duplicate/combo updates, unknown events, cache limits, clear-data behavior, and quota-aware discovery pass.

### MS-005 - Complete authorized actions and broadcast management

**Status:** Implementation complete; account-side certification pending. The service/capability suite passes 131 checks and the real loopback authorized-operation harness passes 22 checks, including bearer headers, bodies/queries, token-freshness preflight, confirmation gates, and pre-network quota rejection.

**Runnable result:** an authorized channel owner can exercise documented chat, poll, moderation, moderator, broadcast, stream, binding, metadata, and transition operations from a test UI and observe the resulting account/API state.

**Exit checks:** scope matrix, confirmations, invalid-state guards, typed errors, rate/quota handling, account-side verification, cleanup, and denial/revocation behavior pass for every shipped action.

### MS-006 - Editor/runtime UX, certification, and release

**Status:** In progress. The YouTube-specific setup tool, optional connection control, full integration lab, API/capability/lifecycle documentation, licensing, and local source packaging are implemented. A stable release remains blocked on the live credential/account matrix, Linux desktop keyring, Windows/Linux exports, and publication checks.

**Runnable result:** a new developer follows the documentation, configures a sample game, has a test user connect a channel, optionally runs the documented two-client/multi-channel example, exercises the supported feature matrix in a controlled live broadcast, packages Windows and Linux x86-64 exports, creates the canonical GitHub release, and installs the same stable release through its Redot Asset Library entry.

**Exit checks:** fresh-project install, full event/action matrix, end/reconnect/token-expiry, quota pressure, accessibility, privacy/consent/revocation/data deletion, MIT license and pinned-source reuse-manifest/notice audit, rejected-donor-module scan, clean plugin disable, bounded Redot runs, immutable GitHub tag/archive/checksum audit, Redot Asset Library metadata/install checks, and release artifact checks pass.

## 10. Task breakdown

The task list is approved and executable in dependency order. Implementation still requires an explicit start instruction.

| ID | Milestone | Outcome | Dependencies | Expected files/systems | Acceptance and verification |
| --- | --- | --- | --- | --- | --- |
| TUBE-001 | MS-001 | Freeze official endpoint/event/scope/quota contracts and lawful redacted fixtures | Preflight | `tests/fixtures/`, contract notes | Every supported type/action maps to an official source and disposition |
| TUBE-002 | MS-001 | Build deterministic fake HTTP/stream harness | TUBE-001 | test server/harness scripts and scene | Chunk boundaries, disconnects, errors, timing, and captures are reproducible |
| TUBE-003 | MS-001 | Prove/reject bounded `streamList` parsing in Redot | TUBE-002 | `transport/` prototype, tests | Resume/cancel/partial frames pass without unbounded buffering |
| TUBE-004 | MS-001 | Prove compliant `list` scheduler | TUBE-002 | polling transport, tests | Never polls before returned interval; continuation/end/error states pass |
| TUBE-005 | MS-001 | Freeze quota and policy/data-lifecycle checklist | TUBE-001 | diagnostics/policy test data | Each request category and stored datum has cost/lifecycle handling |
| TUBE-006 | MS-002 | Port and rename the approved Twitcher `EditorPlugin`, setup-shell, small utility, and compatibility-probe foundations | MS-001; DEC-017; SRC-026 | addon root, `plugin.gd`, `editor/`, `tests/`, reuse manifest | Donor characterization tests pass; every adapted file has provenance; enable/disable twice leaves no orphan types/docks/settings; no Twitch path, branding, credential, or service dependency remains |
| TUBE-007 | MS-002 | Adapt and harden the donor HTTP request/response and typed model/generator foundations | TUBE-006; DEC-017 | `transport/`, `models/`, generator fixtures, diagnostics | Real bounded concurrency, cancellation, retry/backoff, timeout, quota metadata, typed errors, Google-discovery generation, and secret-redaction fixtures pass; donor retry/queue behavior is not assumed |
| TUBE-008 | MS-002 | Resolve known video to active live chat | TUBE-007 | video/live-chat services | Valid, missing, disabled, ended, and denied cases are typed |
| TUBE-009 | MS-002 | Deliver read-only typed vertical slice | TUBE-003 or TUBE-004; TUBE-008 | public client facade, sample scene | Sample displays ordered events and connection/quota state in bounded run |
| TUBE-010 | MS-003 | Document and enforce the developer-owned OAuth application configuration contract | DEC-010; SRC-007/008 | plan/API configuration contract | Consent, verification, quota, redirect, privacy, and support remain explicitly assigned to each game developer/publisher |
| TUBE-011 | MS-003 | Adapt Twitcher's OAuth state/timeout/loopback scaffolding to Google authorization code plus PKCE | TUBE-010; TUBE-007; DEC-017; SRC-025; SRC-026 | `auth/`, loopback transport, reuse manifest | Success, denial, state mismatch, timeout, port conflict, browser failure, cancellation, and loopback-only binding pass on Windows/Linux; implicit flow, wildcard binding, and protected-secret assumptions are absent |
| TUBE-012 | MS-003 | Adapt refresh/validation/revocation lifecycle into per-client capability ownership | TUBE-011; DEC-016; DEC-017 | `auth/`, models | Rotation/expiry/revoke/denial and two-client isolation tests pass without token or signal cross-talk; no global auth/service instance or donor persistence remains |
| TUBE-013 | MS-003 | Implement hybrid session descriptor and standalone OS-vault helpers | DEC-013; DEC-014; DEC-015; DEC-016; DEC-017; SRC-018–SRC-026 | `auth/` storage provider, `bin/`, `native/credential-helper/` | Store/read/replace/delete, restart, stable slot reuse, duplicate-slot rejection, unavailable/locked store, corruption, protocol mismatch, revocation, per-client deletion, and secret-leak cases pass on Windows/Linux x86-64; donor token cache and AES provider are absent |
| TUBE-014 | MS-003 | Provide optional per-client runtime connection UI | TUBE-011–013 | `ui/` | Keyboard/gamepad navigation, account/channel identity, text status, cancel, disconnect, and clear-data isolation pass |
| TUBE-015 | MS-004 | Implement channel/broadcast/stream/chat discovery and selection | MS-003 | `services/` | Manual refresh/cache and quota tests pass; no tight search polling |
| TUBE-016 | MS-004 | Implement the complete typed live-event model using the adapted generator/data-pattern foundation | TUBE-001; TUBE-007; TUBE-009 | `models/`, parser/generator fixtures, signals | Official YouTube variants, optional fields, combo updates, unknown types, regeneration determinism, and no-Twitch-schema checks pass fixtures |
| TUBE-017 | MS-004 | Adapt the donor media-fetch/decode flow into a bounded YouTube media cache with clearing | TUBE-016; DEC-017 | `media/`, reuse manifest | Type/size/concurrency/retention/eviction/corruption/delete tests pass; no Twitch emote/badge/Cheermote, ImageMagick, GIF-importer, or donor-asset dependency ships |
| TUBE-018 | MS-005 | Implement chat send and poll operations | MS-003; MS-004 | live-chat service | Scope, validation, success, denial, quota, and observed result pass |
| TUBE-019 | MS-005 | Implement delete, ban/timeout, unban, and moderator operations | TUBE-018 | moderation services | Confirmation, privilege, invalid target, cleanup, account-side checks pass |
| TUBE-020 | MS-005 | Implement broadcast and stream CRUD/binding/transition surface | TUBE-015 | broadcast/stream services | Valid state machine, destructive confirmation, invalid transition, cleanup pass |
| TUBE-021 | MS-005 | Freeze and test public capability matrix | TUBE-018–020 | facade/models/docs | Every public action declares scopes, availability, quota category, and typed errors |
| TUBE-022 | MS-006 | Complete the YouTube-specific editor setup/status tooling using the approved donor workflow shell | MS-003–MS-005; DEC-017 | `editor/`, reuse manifest | Fresh developer configuration succeeds without project credentials; setup/inspectors contain only YouTube capabilities and unregister cleanly |
| TUBE-023 | MS-006 | Complete examples, API documentation, lineage manifest, MIT license, and notices | TUBE-021; TUBE-022 | demo project, README/API docs, `LICENSE`, addon-local license/readme copies, `docs/lineage/twitcher-reuse.md`, `THIRD_PARTY_NOTICES.md` | New developer reproduces the full flow; the standalone project is clearly MIT-licensed; each adapted file traces to the pinned donor commit and required original/fork attribution is present without implying endorsement |
| TUBE-024 | MS-006 | Run live credential and account-side certification matrix | TUBE-023 | QA evidence | Full supported event/action/reconnect/quota/revoke/cleanup matrix, including two concurrent clients with no cross-talk, passes on Windows and Linux x86-64 |
| TUBE-025 | MS-006 | Package and verify release | TUBE-024 | addon archive, canonical GitHub release, and Redot Asset Library listing | MIT license/notices/lineage manifest, signed or checksum-verifiable immutable tag/archive, clean install/disable from both GitHub and Asset Library, matching version/commit/repository/icon metadata, x86-64 Windows/Linux exports, supported-architecture manifest, rejected-donor-module scan, and no-secret checks pass |

TUBE-001 through TUBE-021 are implementation-complete with deterministic evidence. TUBE-022 and TUBE-023 are locally implemented and remain subject to fresh-user/live review. TUBE-024 and the public-release portions of TUBE-025 require the external MS-006 environments and are not claimed complete.

## 11. QA strategy

- Pure fixture tests for parsers, event normalization, scope mapping, quota classification, redaction, and state machines.
- Deterministic fake HTTP/stream service for chunking, latency, disconnect, replay, error, and retry scenarios.
- For every adapted Twitcher component, run minimal characterization tests against the pinned donor behavior and then the renamed Redot-Tuber version; record every intentional difference in the reuse manifest before extending it.
- Automated lineage and exclusion checks verify adapted files point to the pinned donor commit and that runtime code contains no `res://addons/twitcher`, Twitch service/model dependencies, global donor instances, donor token-cache/key paths, implicit flow, wildcard callback binding, or inherited Twitch media/GIF subsystems.
- `redot_code_intel(action="validate")` or the available Redot validation equivalent before runtime checks.
- Bounded Redot runs with `--quit-after` of at least 2 and a wall-clock timeout; never use unattended `-d`.
- Clean enable/disable/re-enable cycles for the EditorPlugin.
- Clean-project install and exported runtime OAuth tests on Windows and Linux x86-64, with equal public API and feature coverage.
- Live Google test project/channel matrix for authorization, refresh, revocation, discovery, every event/action category, quota pressure, end-of-chat, reconnect, and account-side cleanup.
- Cross-process-restart tests proving persisted login, refresh rotation, disconnect deletion, revoked-token cleanup, and no-plaintext fallback on Windows and Linux.
- Two-client tests using distinct stable session slots, proving there is no token, identity, signal, transport, quota, refresh, revoke, or clear-data cross-talk; reusing a live slot is rejected deterministically.
- Automated secret scanning of project files, fixtures, logs, screenshots, reports, and release archives.
- Accessibility checks for optional runtime/editor UI: keyboard operation, visible focus, text state, no color-only status, readable scaling, and cancel/recovery routes.
- Performance checks: bounded receive queues/buffers/cache, no per-frame polling, stable idle CPU, and no node/resource leaks after repeated connect/disconnect.

## 12. Risks and open questions

| Risk | State | Impact | Mitigation / deadline |
| --- | --- | --- | --- |
| RSK-001 `streamList` framing/cancel/reconnect in Redot | RESOLVED for implementation; live certification pending | May remove low-latency transport | Incremental loopback harness passes framing, resume, reconnect, cancellation, idle, and bounded-buffer gates; polling fallback remains valid |
| RSK-002 Google verification/privacy/data-deletion duties | BLOCKED for release | Can block distribution | Document developer/publisher duties, minimize scopes, and complete review before MS-006 |
| RSK-003 quota budget and current costs | PARTIALLY RESOLVED; live measurements pending | Can interrupt games | Official read/Search Queries accounting and conservative Live/write budgets are enforced before network; compare against a live Cloud Console during MS-006 |
| RSK-004 creator-action scope | RESOLVED by full-featured direction | Previously limited v1 | Plan all documented live actions; capability-gate unavailable account features |
| RSK-005 media retention | RESOLVED for implementation | Privacy/disk risk | Persistence defaults off; HTTPS/type/item/aggregate/concurrency/TTL/LRU bounds and clear-data/corruption recovery pass the MS-004 media harness |
| RSK-006 desktop OS matrix | RESOLVED by Windows/Linux-first certification | Changes OAuth/export testing | Certify feature parity on Windows and Linux; begin macOS only after both are solid |
| RSK-007 OAuth application ownership | RESOLVED by developer-owned applications | Determines consent screen, verification, quota, redirects, privacy, and support ownership | Each integrating developer/publisher owns the application used by their game; enforce in TUBE-010/MS-003 |
| RSK-008 account multiplicity | RESOLVED by one-account-per-client model | Affects token/session model, public facade, persistence, UI, and testing | Each client owns one account/channel and stable session slot; concurrent accounts use independent clients with explicit isolation tests in MS-003 |
| RSK-009 web/mobile support | RESOLVED as later platform ports | Requires different redirect/storage lifecycle | Design and certify web/mobile separately after Windows/Linux stability |
| RSK-010 credential persistence | RESOLVED by hybrid helper architecture | Persistence is required, but unsafe storage leaks refresh tokens and native helpers expand build/release scope | Use non-secret session metadata plus standalone OS-vault helpers; no plaintext or GDExtension path |
| RSK-011 native CPU matrix | RESOLVED by x86-64-first certification | Each architecture multiplies helper builds, packaging, signing, and Windows/Linux certification | Certify x86-64 helpers in the initial release; add ARM64 after the first-release credential flow and packaging are solid |
| RSK-012 repository license | RESOLVED by MIT | Controls reuse rights, contributor expectations, notice obligations, and compatibility with adapted MIT material | License the standalone repository and addon under MIT; preserve the Kani/Twitcher notice and applicable Redot-fork attribution in copied or substantially adapted source |
| RSK-013 public distribution destination | RESOLVED by GitHub Releases plus Redot Asset Library | Changes release automation, discovery, support, and registry metadata | GitHub Releases is canonical; list each stable release separately in the Redot Asset Library and keep version, commit/archive, repository, icon, and license metadata aligned |
| RSK-014 donor-code assumptions and defects | OPEN / controlled by gates | Blind reuse could import Twitch semantics, insecure auth/storage, unstable retry/cancellation, attribution gaps, or maintenance debt | Pin commit `5c80a758b1800ac74bdfa36cf2f0274013ba58dc`; characterize before porting; maintain per-file provenance; reject named donor modules/patterns; independently validate each adapted component before MS-002 or MS-003 accepts it |

## 13. Release plan

### Planned artifacts

- Standalone addon source rooted at `addons/redot-tuber/`.
- Installable source archive with `plugin.cfg`, runtime/editor code, tests/fixtures permitted for redistribution, documentation, an MIT `LICENSE`, addon-local license/readme copies, and third-party notices.
- Separate example Redot project or clearly isolated example content.
- Versioned API/capability matrix, OAuth setup guide, privacy/data-lifecycle integration guide, and migration notes.
- `docs/lineage/twitcher-reuse.md` mapping every copied or substantially adapted donor file to the pinned Twitcher commit, plus `THIRD_PARTY_NOTICES.md` with the original MIT license and applicable fork attribution.
- Versioned Windows/Linux x86-64 credential-helper binaries with protocol manifest, source, licenses/notices, checksums, and supported-architecture table; ARM64 is explicitly marked post-release.
- Canonical GitHub release with immutable tag/archive, checksums, release notes, tested-Redot compatibility declaration, and links to source/lineage documentation.
- Redot Asset Library Addon entry pointing to the same tested stable release, with matching version, commit/archive, repository, icon, license, and support metadata.

### Version and compatibility

- Semantic versioning begins at `0.x` during fixture/live validation and reaches `1.0.0` only after MS-006.
- The first release certifies the exact tested Redot build(s) on Windows and Linux; “Godot compatible” is not implied.
- The first release ships and certifies x86-64 helper binaries only. ARM64 helpers are a post-release compatibility milestone after Windows/Linux behavior is solid.
- macOS support is a post-stability compatibility milestone after the Windows and Linux release criteria remain solid.
- Web and mobile are separate compatibility tracks with their own OAuth, storage, lifecycle, and export gates after the initial desktop targets are stable.
- Breaking signal/model/configuration changes require migration notes and a major version once 1.0 is released.

### Distribution gates

- All milestone and selected Gauntlet gates pass with retained evidence.
- Google verification/privacy obligations for the selected OAuth model are complete.
- No credentials or user data are present in source/release artifacts.
- The standalone repository/addon MIT license, Twitcher lineage, per-file reuse manifest, YouTube non-endorsement, documentation-source terms, and inherited MIT notices are correct; every release file derived from Twitcher traces to the pinned donor commit.
- Automated exclusion checks confirm the release contains no Twitch runtime dependency, Twitch protocol/generated model, donor token cache/key provider, global donor service, wildcard callback binding, or unapproved donor asset/GIF subsystem.
- Clean install, full disable/re-enable, exported runtime login, live event/action matrix, revocation, clear-data, and removal tests pass.
- Every shipped helper binary passes protocol-version, store/read/replace/delete, unavailable-store, secret-leak, checksum, and clean-removal gates on its declared OS/architecture.
- The GitHub release tag/archive is immutable and checksum-verifiable; the Redot Asset Library entry resolves to that exact tested release and installs under `res://addons/redot-tuber/` without extra repository files.
- Release metadata is synchronized across `plugin.cfg`, GitHub, the compatibility declaration, and the Redot Asset Library before submission or update.

## 14. Out of scope

- Scraping YouTube pages, popup chat, or private frontend endpoints.
- C#, .NET, or GDExtension libraries; credential persistence uses the approved standalone helper-process boundary.
- A dependency on `redot-twitcher` or a shared multi-platform streaming runtime.
- Mechanically renaming or bulk-copying the complete Twitcher addon; reuse remains component-level, source-traceable, and test-gated.
- Generic Twitch-compatible “reward” models that erase YouTube semantics.
- Shipping third-party code/assets without a verified license and attribution path.
- Silent background authorization, hidden scope escalation, or storing credentials in project content.
- Web or mobile export certification in the first Windows/Linux release.
- ARM64 credential-helper certification in the initial release.

## Decisions so far

- Standalone Redot addon with typed GDScript and platform-prefixed public APIs.
- Full official YouTube Live functionality is the product goal, not a deliberately narrow MVP.
- Game users connect their own YouTube account/channel at runtime through an authorization flow supplied by the addon.
- Each integrating game developer or publisher owns and supplies the Google OAuth application configuration used by their shipped game; `redot-tuber` owns the secure flow, not the shared production identity.
- Windows and Linux receive first-release certification and feature parity; macOS follows after both are solid.
- Web and mobile are later platform ports and do not block first-release certification.
- Login persistence across game sessions is required on supported desktop targets; session-only authorization is not the standard experience.
- Persistent login uses a cookie-like non-secret session descriptor plus standalone Windows Credential Manager and Linux Secret Service helpers; tokens never fall back to plaintext or GDExtension storage.
- Initial Windows/Linux credential-helper certification is x86-64 only; ARM64 follows after the first release is solid.
- Each `YouTubeLiveClient` owns one active account/channel and one stable non-secret session slot; games use multiple isolated clients for concurrent accounts rather than an account collection or global auth singleton.
- Implementation starts from audited generic foundations in `dominicbytes/twitcher` commit `5c80a758b1800ac74bdfa36cf2f0274013ba58dc` where that saves time. Each adapted component is renamed, characterized, independently hardened, and provenance-tracked; Twitch protocols, storage, singletons, and branding are not inherited.
- The standalone repository and addon use the MIT License; Kani/Twitcher notices and applicable Redot-fork attribution are preserved for adapted source.
- Stable releases use GitHub Releases as the canonical source and are listed separately in the Redot Asset Library using the exact tested release commit/archive.
- `redot-kicker`, `redot-rumbler`, and `redot-joysticker` will use the same per-plugin GitHub-plus-Asset-Library release pattern, without a combined suite package or shared runtime.
- The same addon supports API-key/public reads and authorized user operations where useful.
- Official APIs only; no scraping/private protocols.
- `streamList` is preferred if the installed Redot build passes the transport gate; policy-compliant polling is the fallback.
- YouTube-native event/action types, capability flags, least-privilege scopes, BYO configuration baseline, memory-safe handling, revocation, and data deletion.

## Planning confirmation

The planning interview is complete. No unresolved product or release decision blocks MS-001. `RSK-001`, `RSK-002`, `RSK-003`, `RSK-005`, and `RSK-014` remain deliberate evidence gates with named deadlines and fallbacks; they are implementation/release risks rather than missing user decisions.
