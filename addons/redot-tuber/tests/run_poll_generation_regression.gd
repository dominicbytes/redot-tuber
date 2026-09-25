extends SceneTree

var _checks: int = 0
var _failures: PackedStringArray = []


class DelayedChat extends YouTubeLiveChatService:
	var tree: SceneTree
	var calls: Dictionary = {}
	var fail_old: bool = false
	var inflight: int = 0
	var peak: int = 0

	func _init(scene_tree: SceneTree) -> void:
		super(null)
		tree = scene_tree

	func list_messages(chat_id: String, _page_token: String = "", _max_results: int = 200, _cancellation: YouTubeCancellationToken = null) -> YouTubeLiveChatPage:
		calls[chat_id] = int(calls.get(chat_id, 0)) + 1
		inflight += 1
		peak = maxi(peak, inflight)
		await tree.create_timer(0.12 if chat_id == "old" else 0.02).timeout
		inflight -= 1
		var page: YouTubeLiveChatPage = YouTubeLiveChatPage.new()
		page.next_page_token = chat_id + "-cursor"
		page.polling_interval_msec = 300
		if chat_id == "old" and fail_old:
			page.error = YouTubeApiError.custom("old_error", "Delayed old response")
		return page


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _sleeping_loop_does_not_join_new_session()
	await _old_response_cannot_change_new_session(false)
	await _old_response_cannot_change_new_session(true)
	for failure: String in _failures:
		push_error(failure)
	print("POLL GENERATION REGRESSION: %d checks, %d failed" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _client() -> YouTubeLiveClient:
	var client: YouTubeLiveClient = YouTubeLiveClient.new()
	root.add_child(client)
	client._ensure_runtime()
	client._chat = DelayedChat.new(self)
	return client


func _start(client: YouTubeLiveClient, chat_id: String) -> void:
	client.active_live_chat_id = chat_id
	client._cancellation = YouTubeCancellationToken.new()
	client._begin_polling()


func _sleeping_loop_does_not_join_new_session() -> void:
	var client: YouTubeLiveClient = _client()
	var chat: DelayedChat = client._chat as DelayedChat
	client._poll_scheduler.accept_response({"pollingIntervalMillis": 80}, Time.get_ticks_msec())
	_start(client, "old")
	await process_frame
	client.stop_chat("switch")
	_start(client, "new")
	client._begin_polling()
	await create_timer(0.2).timeout
	_check(int(chat.calls.get("old", 0)) == 0, "stopped sleeping loop never sends its request")
	_check(int(chat.calls.get("new", 0)) == 1, "new session has one polling loop and respects its interval")
	_check(chat.peak == 1, "no duplicate concurrent polls")
	client.stop_chat()
	await create_timer(0.35).timeout
	_check(int(chat.calls.get("new", 0)) == 1, "stopped session never polls again after its timer")
	client.queue_free()
	await process_frame


func _old_response_cannot_change_new_session(fail_old: bool) -> void:
	var client: YouTubeLiveClient = _client()
	var chat: DelayedChat = client._chat as DelayedChat
	chat.fail_old = fail_old
	var errors: Array[YouTubeApiError] = []
	client.error_occurred.connect(func(error: YouTubeApiError) -> void: errors.append(error))
	_start(client, "old")
	await process_frame
	client.stop_chat("switch")
	_start(client, "new")
	await create_timer(0.2).timeout
	_check(client._is_polling, "old completed request cannot stop new polling")
	_check(client._poll_scheduler.next_page_token() == "new-cursor", "old page cannot replace current cursor")
	_check(errors.is_empty(), "old request errors are not emitted into the new session")
	_check(client.active_live_chat_id == "new", "new chat identity is preserved")
	client.stop_chat()
	await create_timer(0.35).timeout
	client.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
