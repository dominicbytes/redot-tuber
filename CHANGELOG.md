# Changelog

## 0.5.0-dev — 2026-08-11

- Added developer-owned installed-app OAuth with PKCE/state/IPv4-loopback handling, automatic access-token freshness checks, revocation, and per-client persistent sessions.
- Added Windows Credential Manager and Linux Secret Service x86-64 credential helpers with a versioned stdin/stdout protocol and no plaintext fallback.
- Added channel/live-video discovery, preferred incremental chat streaming, polling fallback, typed YouTube-native events, and recent Super Chat/Super Sticker history.
- Added chat/poll writes, moderation and moderator management, broadcast/stream CRUD, stream binding, lifecycle transitions, and cuepoints behind capability and confirmation gates.
- Added separate Data API/Search Queries budgets, conservative Live API accounting, and pre-network budget rejection.
- Added a bounded optional media cache, comprehensive integration lab, API/capability/lifecycle documentation, and deterministic feature/HTTP/stream/media harnesses.
- Kept stable release certification blocked on real Google account-side testing and Linux desktop Secret Service validation.

## 0.1.0-dev — 2026-08-10

- Added the installable Redot Tuber editor plugin and credential-free setup guidance.
- Added bounded REST transport with retry, cancellation, timeout, body limits, quota accounting, and secret-safe diagnostics.
- Added typed YouTube API errors and video-to-active-live-chat resolution.
- Added compliant `liveChatMessages.list` polling and typed event delivery.
- Added deterministic Google Discovery contract tooling and lawful offline fixtures.
- Added a runtime-built read-only sample scene.
- Added MIT licensing, Kani/Twitcher attribution, and a pinned donor reuse/rejection manifest.
