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

`YouTubeLiveClient` resolves the video's `activeLiveChatId` and uses `liveChatMessages.list` polling by default. It obeys `pollingIntervalMillis`, resumes with page tokens, deduplicates replayed message IDs, emits mutable updates separately, and stops when chat ends. To opt into the Windows/Linux x86-64 native gRPC `streamList` helper, set `youtube.prefer_streaming = true` before `start_events()`. Keep `fallback_to_polling = true` for missing helpers or transient stream failures. The former incremental list-response implementation did not provide real streaming. See [current validation](validation-26.3.md) before shipping.

Public mode grants only `channel.read`, `discovery.read`, and `chat.read`. Account identity, chat writes, moderation, broadcasts, streams, and monetization history use the OAuth flow and capability matrix. Live-method quota values remain conservative local estimates until confirmed in the integrating developer's Cloud Console.
