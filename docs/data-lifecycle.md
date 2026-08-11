# Data lifecycle and clear-data contract

| Datum | Default location | Retention | Removal |
|---|---|---|---|
| OAuth access token | Memory inside one client auth manager | Until expiry, refresh, auth loss, disconnect, or process exit | Replaced/cleared in memory |
| OAuth refresh token | Windows Credential Manager or Linux Secret Service only | Until revoke, disconnect, or clear-data | RTCH/1 `delete` for the qualified slot |
| PKCE verifier, OAuth state, authorization code | Memory during one authorization attempt | Until exchange, denial, timeout, mismatch, cancel, or replacement | Cleared immediately by the OAuth session |
| Session descriptor | `user://redot-tuber/sessions/<slot>.json` | Until disconnect or clear-data | Descriptor-store deletion |
| Minimal channel identity/capability summary | Inside the non-secret descriptor | Same as descriptor | Same as descriptor |
| API key | Integrating game's runtime configuration and client memory | Defined by integrating game; never persisted by Redot Tuber | Integrating game clears its source; client freed/reconfigured |
| Live chat events | Memory-only by default | Current client/process | Stop chat, disconnect, clear-data, or process exit |
| Stream ingestion name/key | Memory inside a returned `YouTubeLiveStream` only | While that model is referenced | `clear_sensitive()`, disconnect/clear-data, model release, or process exit |
| Remote media | Bounded memory cache; optional disk cache under `user://redot-tuber/media-cache` | Default 24-hour TTL, 128 items, 32 MiB total, 2 MiB/item; configurable within hard code bounds | `clear_local_data()`, `media_cache().clear_data()`, expiry, LRU eviction, or corruption recovery |
| Diagnostics | Redacted in-memory signals/log summaries | Current process unless the game explicitly records them | Process exit or game-owned clear action |

Redot Tuber never treats browser cookies as its login store. Google browser cookies remain inside the user's browser; the game receives OAuth tokens through the installed-app flow and persists only the refresh token in the operating-system vault.

Media persistence is disabled by default. When enabled, filenames are SHA-256 hashes of source URLs and metadata contains only content type, byte size, and retention timestamps; signed/source URLs are not written to cache metadata. Only PNG, JPEG, WebP, and GIF responses are accepted, and all downloads obey content-type, item-size, aggregate-size, concurrency, and TTL bounds. GIF responses remain bounded bytes because the installed Redot decoder path does not provide animated-GIF playback.

YouTube stream ingestion names are credentials. They are redacted from diagnostics, never included in create/update request bodies, never cached, and must not be copied into scenes, resources, screenshots, crash reports, telemetry, or logs by the integrating game.

Games integrating the addon remain responsible for disclosing their own data use, downstream storage, telemetry, exports, moderation logs, and server-side processing. Redot Tuber's local clear-data action cannot delete data that an integrating game copied elsewhere.
