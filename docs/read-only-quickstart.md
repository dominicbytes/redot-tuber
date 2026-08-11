# Read-only quickstart

Redot Tuber's read-only path lets a game consume a known live video's public chat using a developer-owned YouTube Data API key. It does not sign a channel owner in and cannot perform writes; those features use the OAuth path built in MS-003.

```gdscript
var youtube := YouTubeLiveClient.new()
add_child(youtube)

youtube.event_received.connect(func(event: YouTubeLiveEvent) -> void:
	print(event.kind, ": ", event.display_message)
)

var configuration_error := youtube.configure_public(api_key_from_runtime, "main-channel")
if configuration_error == null:
	await youtube.start_events(live_video_id_from_runtime)
```

Do not place API keys in source, scenes, resources, export presets, or `project.godot`. Inject them through your own runtime configuration boundary and apply appropriate Google Cloud API-key restrictions.

`YouTubeLiveClient` resolves the video's `activeLiveChatId`, prefers incremental `streamList`, and automatically falls back to `liveChatMessages.list` when configured to do so. The polling path obeys `pollingIntervalMillis`; both paths resume with page tokens, deduplicate replayed message IDs, emit mutable updates separately, and stop when chat ends. Set `prefer_streaming = false` or call `start_polling()` if your game deliberately wants polling only.

Public mode grants only `channel.read`, `discovery.read`, and `chat.read`. Account identity, chat writes, moderation, broadcasts, streams, and monetization history use the OAuth flow and capability matrix. Live-method quota values remain conservative local estimates until confirmed in the integrating developer's Cloud Console.
