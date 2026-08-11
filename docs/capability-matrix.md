# YouTube capability matrix

Capabilities are selected when `configure_oauth()` is called. Redot Tuber derives the minimum Google scope set: read-only capabilities use `youtube.readonly`; any write/moderation capability uses `youtube.force-ssl`, which subsumes the read-only access needed by this addon.

API-key mode exposes only `channel.read`, `discovery.read`, and `chat.read`. All other methods require a connected OAuth account. Availability can still depend on the connected channel, broadcast state, moderator privileges, monetization eligibility, and Google policy.

Quota values below are local protective accounting. Official Data API read costs and the current separate Search Queries bucket are represented directly. Live/write rows marked as estimates are deliberately conservative and must be compared with the integrating developer's Google Cloud Console before release.

| Capability | API methods | OAuth scope | Local units | Confirmation / availability |
|---|---|---|---:|---|
| `channel.read` | `channels.list` | `youtube.readonly` | 1 | API key or OAuth |
| `discovery.read` | `videos.list` | `youtube.readonly` | 1 | API key or OAuth |
| `discovery.read` | `search.list` | `youtube.readonly` | 1 search query | Manual/cached search; never tight-polled |
| `chat.read` | `liveChatMessages.list`, `streamList` | `youtube.readonly` | 1 estimate/request | Active live chat required |
| `chat.write` | `liveChatMessages.insert` | `youtube.force-ssl` | 50 estimate | Connected account; send text/create poll |
| `poll.manage` | `liveChatMessages.transition` | `youtube.force-ssl` | 50 estimate | Explicit confirmation; close only |
| `moderation.delete_message` | `liveChatMessages.delete` | `youtube.force-ssl` | 50 estimate | Explicit confirmation and sufficient privilege |
| `moderation.ban` | `liveChatBans.insert` | `youtube.force-ssl` | 50 estimate | Explicit confirmation; temporary or permanent |
| `moderation.unban` | `liveChatBans.delete` | `youtube.force-ssl` | 50 estimate | Explicit confirmation |
| `moderation.read` | `liveChatModerators.list` | `youtube.force-ssl` | 1 estimate | Connected account and sufficient privilege |
| `moderation.manage` | moderator insert/delete | `youtube.force-ssl` | 50 estimate | Explicit confirmation and sufficient privilege |
| `broadcast.read` | `liveBroadcasts.list` | `youtube.readonly` | 1 estimate | OAuth; channel must support live streaming |
| `broadcast.manage` | broadcast insert/update/delete | `youtube.force-ssl` | 50 estimate | Delete requires confirmation; channel eligibility applies |
| `broadcast.bind` | `liveBroadcasts.bind` | `youtube.force-ssl` | 50 estimate | Explicit confirmation |
| `broadcast.transition` | `liveBroadcasts.transition` | `youtube.force-ssl` | 50 estimate | Explicit confirmation and valid lifecycle transition |
| `broadcast.cuepoint` | `liveBroadcasts.cuepoint` | `youtube.force-ssl` | 50 estimate | Explicit confirmation; active/eligible broadcast |
| `stream.read` | `liveStreams.list` | `youtube.readonly` | 1 estimate | OAuth; channel must support live streaming |
| `stream.manage` | stream insert/update/delete | `youtube.force-ssl` | 50 estimate | Delete requires confirmation; stream ingestion name is secret |
| `monetization.read` | `superChatEvents.list` | `youtube.readonly` | 1 estimate | Eligible purchases from the previous 30 days |

## Error contract

Capability decisions fail locally with typed categories such as `capability_denied`, `authorization`, `confirmation_required`, `invalid_request`, or `quota_budget`. A local rejection consumes no request and exposes no token. Server-side account/policy denials remain typed API errors because the addon cannot infer channel privileges or eligibility in advance.

## Recommended capability sets

Use only what the game needs:

```gdscript
# Read and react to a known live chat.
PackedStringArray(["channel.read", "discovery.read", "chat.read"])

# Add messages and native chat polls.
PackedStringArray(["channel.read", "chat.read", "chat.write", "poll.manage"])

# Creator control surface (request only after explaining the consequences).
PackedStringArray([
	"channel.read", "chat.read", "chat.write", "poll.manage",
	"moderation.read", "moderation.delete_message", "moderation.ban",
	"moderation.unban", "moderation.manage",
	"broadcast.read", "broadcast.manage", "broadcast.bind",
	"broadcast.transition", "broadcast.cuepoint",
	"stream.read", "stream.manage", "monetization.read"
])
```

Changing the requested capability set may require the user to authorize again and may change the integrating developer's Google verification/privacy obligations.
