# redot-tuber preflight report

**Research date:** 2026-08-10\
**Target:** standalone GDScript addon for Redot `26.2.stable.official.4f5b14aba`\
**Verdict:** **GO**, with policy/quota gates\
**Implementation status:** not started

## Research scope and assumptions

This preflight asks whether an independently installable Redot addon can expose YouTube Live capabilities comparable in product scope to `redot-twitcher`: live events, outbound chat, moderation, monetization interactions, media metadata, authentication, typed signals, editor setup, and reliable lifecycle handling.

Only the official YouTube Data API and Live Streaming API are acceptable protocol sources. Web-page scraping, popup-chat DOM parsing, or replaying private frontend requests is out of scope. Desktop is the first target. The initial product should support developers bringing their own Google Cloud project/client rather than making every addon user depend on one centrally verified client.

## Executive decision

Proceed. YouTube's official API supports a broad and useful plugin: public live-chat reads, low-latency server streaming, chat writes, message deletion, bans, moderators, Super Chats, Super Stickers, memberships, membership gifts, polls, and broadcast/stream lifecycle operations.

Complexity is higher than Rumble or Joystick.TV because the addon must combine two authorization modes, honor quota and server-directed polling intervals, implement user-data controls, and treat sensitive OAuth scope verification as a release concern. The recommended v1 has two explicit modes:

1. **Viewer/read-only mode:** API key plus video ID; resolve `activeLiveChatId`, then consume chat using `liveChatMessages.streamList` when proven, with `list` as a compliant fallback.
2. **Creator mode:** installed-app OAuth with PKCE and loopback callback; opt-in scopes enable chat writes, deletion/moderation, and broadcast management.

Do not present monetization messages as generic “channel points.” Preserve YouTube-native concepts in names and payloads.

## Capability target

| Twitcher-like area | Official YouTube support | Proposed v1 | Constraint |
| --- | --- | --- | --- |
| Public live-chat read | API key can access public stream/video data and chat messages | Include by video ID | Avoid repeated search calls for discovery |
| Low-latency events | `liveChatMessages.streamList` server-streaming | Preferred after transport spike | Redot framing/cancellation/reconnect must be proven |
| Polling fallback | `liveChatMessages.list` with `pollingIntervalMillis` | Include | Calling earlier risks rate limiting |
| Outbound chat | `liveChatMessages.insert` | Creator mode | OAuth and explicit user action/consent |
| Moderation | delete messages, live-chat bans, moderators | Optional creator module | Sensitive permissions and destructive actions |
| Monetization/events | Super Chat, Super Sticker, membership/milestone, gifts, polls | Typed native events | Not equivalent to Twitch rewards |
| Broadcast lifecycle | Broadcasts/streams APIs | Optional creator module | Quota and scope dependent |
| Media | author profile image and sticker metadata where present | URL model plus bounded cache | Respect YouTube data refresh/deletion rules |

## Recommended references by milestone/system

### M0 — transport, quota, and policy contract

- **SRC-003:** [YouTube Live Streaming API overview](https://developers.google.com/youtube/v3/live/getting-started). Use to delimit broadcast/stream and live-chat concepts.
- **SRC-004:** [`liveChatMessages` resource](https://developers.google.com/youtube/v3/live/docs/liveChatMessages). Use as the message/event type contract.
- **SRC-005:** [`liveChatMessages.streamList`](https://developers.google.com/youtube/v3/live/docs/liveChatMessages/streamList). Use for the low-latency transport spike, continuation/reconnect behavior, and response contract.
- **SRC-006:** [`liveChatMessages.list`](https://developers.google.com/youtube/v3/live/docs/liveChatMessages/list). Use for a compliant polling fallback and `pollingIntervalMillis` scheduling.
- **SRC-008:** [YouTube API Services developer policies](https://developers.google.com/youtube/terms/developer-policies). Turn consent, display, refresh, deletion, privacy, and anti-scraping duties into testable product requirements.
- **SRC-009:** [Quota costs](https://developers.google.com/youtube/v3/determine_quota_cost). Use for a bounded request budget and diagnostics.
- **SRC-001:** installed Redot API data at `D:\Claude Vault\redot\plugins\api\redot-26.2\4f5b14aba-single-windows-x86_64\extension_api.json`. It verifies HTTP, loopback TCP, crypto/SHA-256, Base64, and browser-launch primitives.

M0 ends only when an `HTTPClient` prototype can incrementally consume, cancel, and reconnect a recorded/synthetic `streamList` response without buffering an unbounded body. If that fails, `list` remains the v1 transport; the project remains feasible with higher latency.

### M1 — authentication and configuration

- **SRC-007:** [OAuth 2.0 for installed applications](https://developers.google.com/identity/protocols/oauth2/native-app). Use for PKCE S256, state, loopback redirect, token refresh, and installed-client behavior.
- **SRC-002:** [dominicbytes/twitcher](https://github.com/dominicbytes/twitcher), local path `D:\Claude Vault\redot\twitcher-redot`, commit `5c80a758b1800ac74bdfa36cf2f0274013ba58dc`. Use as MIT packaging/editor UX inspiration only; keep the runtime independent.

The editor should make API-key-only and OAuth modes visibly distinct and show estimated/observed quota use without storing secrets in project resources.

### M2–M3 — chat, moderation, broadcasts, and media

- **SRC-004/SRC-005/SRC-006:** define typed message variants, page/stream continuation, deletions, bans, monetization events, polls, and author details.
- **SRC-003:** defines broadcasts/streams lifecycle and how an active chat relates to a live broadcast.
- Additional official resource pages linked from these indexes should be pinned in the implementation plan before each optional module is coded; no route should be inferred from a community client.

### M4–M5 — examples and compliance certification

- **SRC-008/SRC-009:** drive the privacy notice, account/data deletion control, consent prompts, quota test, and prohibited-scraping checks.
- A real Google Cloud project, test channel, live broadcast, and verification status are **not available evidence in this preflight**; live certification remains a release gate.

## Redot adaptation notes

### Addon boundary

Use `res://addons/redot-tuber/` with platform-prefixed classes such as `YouTubeLiveClient`, `YouTubeLiveChatMessage`, and `YouTubeSuperChatEvent`. The product name can remain `redot-tuber`, but public code names should say `YouTube` clearly. The addon should enable/disable cleanly and undo all `EditorPlugin` registration in `_exit_tree()`.

Keep modules narrow:

- video/broadcast discovery and active-chat resolution;
- chat transport (`streamList`, with `list` fallback);
- installed-app OAuth and token refresh;
- typed live-chat events and signals;
- opt-in writer/moderator/broadcast actions;
- bounded remote-media cache and deletion hooks;
- quota/rate diagnostics.

Do not add a catch-all global singleton or require a shared runtime from the other streaming addons.

### Authentication and data modes

Read-only mode should accept a developer-provided API key at run time and a known video ID. Calling search repeatedly to find “the current live stream” is costly and avoidable. Resolve `liveStreamingDetails.activeLiveChatId` through a targeted video request, then start chat consumption.

Creator mode should register as an installed/desktop application, generate state and PKCE locally, open the browser, and bind a loopback callback using `TCPServer`. Request the minimum scopes needed for the enabled module. Destructive operations—message deletion, bans, broadcast transitions—must require explicit game/developer action and provide typed confirmation/errors.

No API key, client configuration, access token, refresh token, or user data belongs in source, `ProjectSettings`, `.tres`, `.tscn`, examples, logs, or reports. The installed Redot build has cryptographic primitives but no verified OS keychain. Start with memory-only credentials and make persistence a separate reviewed decision.

### Streaming and polling

Implement `streamList` only after verifying Redot's actual incremental-response behavior. The transport must handle partial JSON framing, multiple messages per chunk, heartbeat/idle timeouts if present, cancellation, continuation tokens, reconnect backoff, duplicates, and end-of-chat states. Cap all receive buffers.

The `list` fallback must schedule the next call no earlier than the returned `pollingIntervalMillis`, carry the next-page token, and stop when the chat ends. It should expose latency and quota diagnostics so users understand the tradeoff. Never substitute DOM scraping when quota is exhausted.

### Models, media, and policy

Use a base event envelope plus typed variants for text, Super Chat, Super Sticker, memberships/milestones, membership gifts, polls, deletions/bans, and system notices. Unknown message types must produce a safe generic event instead of failing the connection.

Cache author images or sticker assets only when needed, with size/content-type bounds and documented eviction. Provide a control to delete stored user-linked data and clear tokens. Refresh or delete API-derived data as required by current policy. Display YouTube attribution/branding only according to current brand requirements; those requirements need a fresh check at implementation/release time.

## Existing plugin and repository search

Queries covered GitHub repository search for `Redot YouTube API`, `Redot YouTube live chat`, `Godot YouTube API`, `Godot YouTube live chat`, plus Godot Asset Library terms. No relevant Redot addon was found on 2026-08-10. This is a bounded search result, not proof of global absence.

Evaluated Godot candidates:

| Source | Evidence | Disposition |
| --- | --- | --- |
| **SRC-010:** [Tanuki33/Godot-Youtube-LiveChat](https://github.com/Tanuki33/Godot-Youtube-LiveChat) | Godot 4.1-era WIP using YouTube popup chat; no repository license found; last activity observed 2023 | Reject |
| **SRC-011:** [guranon/godot-youtube-chat](https://github.com/guranon/godot-youtube-chat) | MIT, Godot 4.5-era project, but explicitly works “without API” by following frontend behavior | Reject protocol; at most independently recreate ergonomic signal ideas |
| **SRC-012:** [dougneves/yt-live-chat-godot](https://github.com/dougneves/yt-live-chat-godot) | Small Godot 4.2-era official-API polling prototype using `videos.list` then live-chat list; no repository license found | Inspiration/evidence only; no code reuse |
| **SRC-013:** [stat.void/youtube-chat-integration-godot-version](https://gitlab.com/stat.void/youtube-chat-integration-godot-version) | Small 2023 MIT prototype | Low-confidence inspiration only; official docs remain authoritative |

## Rejected candidates and reasons

- Any YouTube popup chat, DOM scraper, private frontend request, or “without API” transport is rejected. YouTube's developer policies explicitly prohibit scraping, and frontend contracts are unstable.
- Unlicensed repositories are not reusable code even if publicly visible.
- A single maintainer-owned production OAuth client is deferred. It creates verification, quota, support, revocation, and privacy obligations that are unnecessary for the first developer addon.
- A fake Twitch-style “reward” abstraction is rejected; Super Chats, memberships, gifts, stickers, and polls should remain YouTube-native types.

## License and attribution obligations

- Google/YouTube documentation is a specification/reference. Link and paraphrase it; do not copy extensive text or branding assets.
- `dominicbytes/twitcher` is MIT and retains attribution to original [kanimaru/twitcher](https://github.com/kanimaru/twitcher). Preserve MIT notices if substantive code is adapted; prefer independent implementation.
- `guranon/godot-youtube-chat` and the GitLab prototype are MIT, but their code is not needed for the protocol. Record provenance if any nontrivial ergonomics or code is later adapted.
- The Tanuki and dougneves repositories have no verified license in this preflight, so no code or assets may be copied.
- The eventual repository needs an explicit license, third-party notices, privacy documentation, and accurate non-endorsement wording before release.

## Adversarial evidence audit — `SELF_REVIEW`

Delegated reviewers were not requested, so these are separate labeled self-review passes, not independent review.

| Finding | Lens | Challenged claim | Evidence / missing proof | Result | Decision impact |
| --- | --- | --- | --- | --- | --- |
| TUBE-001 | Feature/reference fit | Official APIs cover a valuable Twitcher-like YouTube surface | Official Live Streaming and live-chat resources cover events, writes, moderation, and lifecycle | PASS | Supports GO |
| TUBE-002 | Redot compatibility | `streamList` can be consumed robustly by the installed Redot HTTP stack | Required primitives exist, but framing/cancel/reconnect has not been exercised with a live or faithful stream | BLOCKED | M0 spike; polling is viable fallback |
| TUBE-003 | Policy/license | Existing no-API/scraping clients are acceptable accelerators | Official policy prohibits scraping; some candidates are unlicensed | FAIL | Reject their protocol/code |
| TUBE-004 | Compliance | A distributable creator-mode client can ship after code tests alone | No live Google project, OAuth verification result, privacy flow, or quota evidence was provided | BLOCKED | Blocks public release, not research/implementation |
| TUBE-005 | Redot compatibility | Native GDScript can perform OAuth, REST, hashing, and loopback callback | Installed Redot 26.2 API data verifies required primitives | PASS | No native extension required |
| TUBE-006 | Product fit | YouTube interactions can be normalized as Twitch rewards without loss | Official event model uses distinct Super Chat/sticker/membership/gift/poll semantics | FAIL | Preserve native types and capability flags |
| TUBE-007 | Maintenance | Community projects establish current API behavior | Projects are stale/small or bypass the API; official docs are current authority | FAIL | Community sources remain inspiration/evidence only |

No rejected audit finding was overridden. The material blocked findings are retained as release and transport gates rather than being described as solved.

## Open risks and unanswered questions

- **RSK-001 — BLOCKED:** Does current Redot `HTTPClient` handle `streamList` framing, cancellation, and reconnect safely under real traffic?
- **RSK-002 — BLOCKED for public release:** What Google OAuth verification, privacy policy, and data-deletion obligations apply to the final selected scopes and distribution model?
- **RSK-003 — OPEN:** What first-release quota budget and per-feature accounting should the editor show? Verify against a real project because quotas and costs can change.
- **RSK-004 — OPEN:** Which creator actions belong in v1 versus a later management module?
- **RSK-005 — OPEN:** What author/sticker media may be cached, for how long, and how will users clear it?
- **RSK-006 — OPEN:** Which desktop platforms must loopback OAuth support initially?

## Concrete implementation-plan changes

When `docs/gamedev/implementation-plan.md` is created, it should contain these ordered outcomes:

1. **MS-001 — Streaming/policy contract spike:** bounded `streamList` fixture prototype, `list` scheduling test, quota ledger, data lifecycle checklist, and unknown-message fixtures pass.
2. **MS-002 — Addon shell and read-only mode:** API-key configuration, video-to-chat resolution, fixture/polling client, typed base events, clean enable/disable, and secret-safe logs pass.
3. **MS-003 — Creator OAuth:** PKCE/state/loopback/refresh and scope gating pass with fixture token responses and a test Google project.
4. **MS-004 — Full event and media models:** text, monetization, memberships/gifts, polls, moderation/system events, bounded media cache, and deletion controls pass.
5. **MS-005 — Optional writes/moderation/broadcasts:** explicit-consent chat send, delete/ban, and selected broadcast actions pass typed error, quota, and cleanup tests.
6. **MS-006 — Documentation and certification:** clean sample project, fresh-project setup, live stream matrix, reconnect/end-of-chat/token-expiry tests, privacy/policy review, and Redot runtime validation pass.

## Preflight gate result

All research questions are answered, deferred, or explicitly blocked. Every recommendation has a primary source, intended use, compatibility assessment, and license disposition. No candidate code or plugin was executed. Implementation can begin with MS-001, but a public release remains blocked on live transport and Google compliance evidence.
