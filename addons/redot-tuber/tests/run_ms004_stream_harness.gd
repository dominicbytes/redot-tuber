extends SceneTree
## A missing native stream helper must fail explicitly and optionally poll.


class VideoFixture extends YouTubeVideoService:
	func _init() -> void:
		super(null)

	func resolve_live_chat(video_id: String, _cancellation: YouTubeCancellationToken = null) -> YouTubeLiveChatResolution:
		var result: YouTubeLiveChatResolution = YouTubeLiveChatResolution.new()
		result.status = YouTubeLiveChatResolution.STATUS_ACTIVE
		result.video_id = video_id
		result.live_chat_id = "fixture-chat"
		return result


class ChatFixture extends YouTubeLiveChatService:
	var tree: SceneTree
	var calls: int = 0

	func _init(scene_tree: SceneTree) -> void:
		super(null)
		tree = scene_tree

	func list_messages(_chat_id: String, _page: String = "", _count: int = 200, _cancellation: YouTubeCancellationToken = null) -> YouTubeLiveChatPage:
		calls += 1
		await tree.process_frame
		var result: YouTubeLiveChatPage = YouTubeLiveChatPage.new()
		result.polling_interval_msec = 20
		return result


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source: YouTubeLiveChatStreamSource = YouTubeLiveChatStreamSource.new()
	var api: YouTubeApiClient = YouTubeApiClient.new()
	api.configure("fixture-key")
	source.configure(api, YouTubeLiveChatService.new(api))
	source.helper_path_override = "res://addons/redot-tuber/tests/fixtures/missing-stream-helper.exe"
	var error: YouTubeApiError = source.start("fixture-chat")
	var checks: Array[bool] = [
		error != null,
		error != null and error.category == "stream_transport_unavailable",
		not source.is_active(),
		source.next_page_token().is_empty(),
	]
	source.stop()
	checks.append(not source.is_active())
	source.free()
	for fallback: bool in [true, false]:
		var client: YouTubeLiveClient = YouTubeLiveClient.new()
		root.add_child(client)
		checks.append(not client.prefer_streaming)
		checks.append(client.configure_public("fixture-key") == null)
		client._videos = VideoFixture.new()
		var chat: ChatFixture = ChatFixture.new(self)
		client._chat = chat
		var unavailable_source: YouTubeLiveChatStreamSource = YouTubeLiveChatStreamSource.new()
		unavailable_source.helper_path_override = "res://addons/redot-tuber/tests/fixtures/missing-stream-helper.exe"
		client.add_child(unavailable_source)
		unavailable_source.configure(client._api, chat, client._capability_gate)
		unavailable_source.page_received.connect(client._on_stream_page)
		unavailable_source.error_occurred.connect(client._on_stream_error)
		unavailable_source.stopped.connect(client._on_stream_stopped)
		client._stream_source = unavailable_source
		client.prefer_streaming = true
		client.fallback_to_polling = fallback
		var errors: Array[YouTubeApiError] = []
		client.error_occurred.connect(func(value: YouTubeApiError) -> void: errors.append(value))
		var resolution: YouTubeLiveChatResolution = await client.start_events("fixture-video")
		checks.append(errors.size() == 1 and errors[0].category == "stream_transport_unavailable")
		checks.append(client.event_source_mode == ("polling" if fallback else "stopped"))
		checks.append(resolution.is_active() == fallback)
		checks.append(chat.calls == (1 if fallback else 0))
		client.stop_chat()
		await create_timer(0.05).timeout
		client.queue_free()
		await process_frame
	var failures: int = checks.count(false)
	print("STREAM MISSING HELPER REGRESSION: %d checks, %d failed" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)
