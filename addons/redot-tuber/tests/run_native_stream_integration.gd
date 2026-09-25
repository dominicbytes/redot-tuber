extends SceneTree
## Requires RTSL_FIXTURE_ENDPOINT from the local Go gRPC fixture process.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var endpoint: String = OS.get_environment("RTSL_FIXTURE_ENDPOINT")
	if endpoint.is_empty():
		printerr("NATIVE STREAM INTEGRATION FAIL: fixture endpoint missing")
		quit(1)
		return
	var api: YouTubeApiClient = YouTubeApiClient.new()
	var checks: Array[bool] = [api.configure("", "fixture-oauth-token") == null]
	var gate: YouTubeCapabilityGate = YouTubeCapabilityGate.new()
	gate.configure(PackedStringArray(["chat.read"]), true)
	var source: YouTubeLiveChatStreamSource = YouTubeLiveChatStreamSource.new()
	root.add_child(source)
	source.configure(api, YouTubeLiveChatService.new(api, gate), gate)
	source.test_loopback_endpoint = endpoint
	source.read_chunk_bytes = 4096
	source.max_reconnect_attempts = 0
	var pages: Array[YouTubeLiveChatPage] = []
	var errors: Array[YouTubeApiError] = []
	source.page_received.connect(func(page: YouTubeLiveChatPage) -> void: pages.append(page))
	source.error_occurred.connect(func(error: YouTubeApiError) -> void: errors.append(error))
	checks.append(source.start("chat") == null)
	var deadline: int = Time.get_ticks_msec() + 5000
	while pages.size() < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	checks.append(pages.size() == 2)
	if pages.size() == 2:
		checks.append(pages[0].next_page_token == "cursor-1" and pages[1].next_page_token == "cursor-2")
		checks.append(pages[0].events.size() == 1 and pages[0].events[0].kind == "text_message")
		checks.append(pages[0].events[0].display_message.ends_with("hé😀"))
		checks.append(pages[1].events.size() == 1 and pages[1].events[0].kind == "super_chat")
		checks.append(pages[1].events[0].monetization_details.amount_micros_exact == "18446744073709551615")
		checks.append(source.next_page_token() == "cursor-2")
	var helper_pid: int = source._pid
	checks.append(helper_pid > 0 and OS.is_process_running(helper_pid))
	source.stop("fixture complete")
	checks.append(not source.is_active())
	checks.append(not OS.is_process_running(helper_pid))
	checks.append(errors.is_empty())
	source.queue_free()
	await process_frame
	var failures: int = checks.count(false)
	print("NATIVE STREAM INTEGRATION %s: %d checks, %d failed" % ["PASS" if failures == 0 else "FAIL", checks.size(), failures])
	quit(0 if failures == 0 else 1)
