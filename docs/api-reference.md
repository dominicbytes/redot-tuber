# Redot Tuber API reference

This reference describes the public typed-GDScript surface in the `0.5.0-dev` development build. `YouTubeLiveClient` is the entry point; lower-level services are obtained from that client so they share its account, capability gate, transport, token refresh, and quota ledger.

## Client setup

Create one client per connected account/session slot:

```gdscript
var youtube := YouTubeLiveClient.new()
youtube.session_slot = "primary-channel"
add_child(youtube)
```

For public reads:

```gdscript
var error := youtube.configure_public(runtime_api_key, "public-session")
if error == null:
	var resolution := await youtube.start_events(runtime_live_video_id)
```

`start_events()` prefers incremental `streamList` and falls back to compliant polling when `fallback_to_polling` is enabled. Set `prefer_streaming = false` or call `start_polling()` to force polling.

For an account connection:

```gdscript
var oauth := YouTubeOAuthConfig.new()
oauth.client_id = runtime_desktop_client_id
oauth.publisher_id = "example-studio"
oauth.application_id = "com.example.game"

var error := youtube.configure_oauth(
	oauth,
	PackedStringArray(["channel.read", "chat.read", "chat.write"]),
	"primary-channel"
)
if error == null:
	var result := await youtube.restore_account()
	if not result.is_success():
		result = await youtube.connect_account()
```

The OAuth client is developer-owned. Do not configure a client secret. See [OAuth setup](oauth-setup.md) and the [capability matrix](capability-matrix.md).

## Client lifecycle methods

| Method | Result | Purpose |
|---|---|---|
| `configure_public(api_key, slot, base_url)` | `YouTubeApiError` or `null` | Configure API-key public reads. |
| `configure_oauth(config, capabilities, slot, ...)` | `YouTubeApiError` or `null` | Configure a per-client OAuth account and minimum requested scopes. |
| `connect_account()` | `YouTubeAuthResult` | Run browser authorization and persist the refresh token in the OS vault. |
| `restore_account()` | `YouTubeAuthResult` | Restore a persisted session and refresh the access token. |
| `refresh_account()` | `YouTubeAuthResult` | Explicitly refresh; authorized service calls also run freshness preflight automatically. |
| `disconnect_account(revoke)` | `YouTubeApiError` or `null` | Stop activity, optionally revoke remotely, and delete this slot's local auth data. |
| `clear_local_data(revoke)` | `YouTubeApiError` or `null` | Disconnect and also clear discovery/media caches. |
| `resolve_video(video_id)` | `YouTubeLiveChatResolution` | Resolve a known video to its active live chat. |
| `start_events(video_id)` | `YouTubeLiveChatResolution` | Resolve and start preferred streaming with optional polling fallback. |
| `start_polling(video_id)` | `YouTubeLiveChatResolution` | Resolve and force API-directed polling. |
| `poll_once()` | `YouTubeLiveChatPage` | Fetch one page for an already selected chat. |
| `stop_chat(reason)` | `void` | Cancel stream/poll work and clear the active chat selection. |
| `capability_matrix()` | `Array[YouTubeCapabilityInfo]` | Inspect every supported API method and its policy metadata. |
| `quota_snapshot()` | `Dictionary` | Read local Data API and Search Queries budget usage. |

`begin_account_authorization()` and `complete_account_authorization()` are available for games that provide their own browser/authorization UI. `cancel_account_authorization()` safely abandons a pending attempt.

## Signals

Connection signals are `connection_state_changed`, `authorization_url_ready`, `account_connected`, `account_disconnected`, and `capabilities_changed`.

Event delivery always emits `event_received` for a new event and `event_updated` for a known ID whose mutable details changed. Typed routes are:

- `message_received`
- `monetization_received`
- `membership_received`
- `poll_received`
- `moderation_received`
- `gift_received(event, updated)`
- `system_event_received`
- `unknown_event_received`

Transport and diagnostics signals are `live_chat_resolved`, `event_source_changed`, `quota_changed`, `quota_bucket_changed`, and `error_occurred`. Diagnostics and URLs are redacted before ordinary logging; the explicit `authorization_url_ready` signal exists only so the game can offer browser-launch recovery.

## Services

Retrieve services from the configured client. Do not create a second API client for authorized calls; doing so would bypass the client's shared freshness and quota state.

| Getter | Main operations |
|---|---|
| `channel_service()` | OAuth-only `get_mine`; public/OAuth `list_by_ids`, `get_by_handle` |
| `discovery_service()` | manual/cached `search_live_videos`, `clear_cache` |
| `live_chat_service()` | `list_messages`, `send_text`, `create_poll`, `close_poll` |
| `moderation_service()` | `delete_message`, `ban_user`, `unban_user`, moderator list/add/remove |
| `broadcast_service()` | broadcast list/create/update/delete, stream binding, transition, cuepoint |
| `stream_service()` | stream list/create/update/delete |
| `monetization_service()` | recent `list_super_chat_events` |
| `media_cache()` | bounded `fetch_texture`, cache counters, `clear_data` |

Every operation returns a typed page/result/error. Destructive calls take a `confirmed` argument and are rejected locally unless it is `true`. The gate also rejects missing capabilities, unauthenticated OAuth-only methods, invalid transitions, invalid input, and exhausted configured quota budgets before a network request is sent.

## Result and event models

- `YouTubeApiPage` carries typed `items`, page tokens/counts, cache state, and `error`.
- `YouTubeOperationResult` carries `method_id`, `status_code`, `value`, and `error`.
- `YouTubeApiError` exposes a stable category, safe message, HTTP/API reason data, and retry metadata without secrets.
- `YouTubeLiveEvent` contains common IDs/timestamps plus typed author, text, monetization, membership, poll, moderation, and gift details. `raw_payload` and `raw_details` preserve forward-compatible fixture/API data but must not be written to ordinary logs.
- `YouTubeLiveBroadcast` and `YouTubeLiveStream` serialize only approved mutable sections. Call `YouTubeLiveStream.clear_sensitive()` when an ingestion name is no longer needed.

Unknown future event types remain usable through `unknown_event_received`; they do not terminate event delivery.

## Media behavior

`YouTubeMediaCache.fetch_texture()` accepts HTTPS (and test-only loopback HTTP), PNG/JPEG/WebP/GIF content types, and bounded response bodies. PNG/JPEG/WebP decode to `Texture2D`. GIF is returned as bounded bytes because the installed Redot path does not provide animated-GIF decoding.

Disk persistence is opt-in. If enabled, it is restricted to `user://redot-tuber/`, names entries by a URL hash, stores no signed URL in metadata, and enforces item, byte, TTL, and LRU limits. `clear_local_data()` clears it.

## Threading and cancellation

Public methods are intended for the main scene thread and use Redot async/await. Long-running HTTP, stream, OAuth, and polling work is bounded and cancellable. Freeing the client stops its work and releases its session slot.
