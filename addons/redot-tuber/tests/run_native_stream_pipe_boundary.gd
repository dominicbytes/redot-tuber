extends SceneTree
## Exercises the actual OS pipe with a 1 MiB JSON line plus LF, then a second frame.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var binary: String = OS.get_environment("RTSL_FRAME_FIXTURE_BINARY")
	if binary.is_empty():
		printerr("NATIVE STREAM PIPE BOUNDARY FAIL: fixture binary missing")
		quit(1)
		return
	var source: YouTubeLiveChatStreamSource = YouTubeLiveChatStreamSource.new()
	root.add_child(source)
	var api: YouTubeApiClient = YouTubeApiClient.new()
	api.configure("fixture-key")
	source.configure(api, YouTubeLiveChatService.new(api))
	source.max_partial_frame_bytes = 1024 * 1024
	source.read_chunk_bytes = 65536
	source.max_reconnect_attempts = 0
	var pages: Array[YouTubeLiveChatPage] = []
	var errors: Array[YouTubeApiError] = []
	source.page_received.connect(func(page: YouTubeLiveChatPage) -> void: pages.append(page))
	source.error_occurred.connect(func(error: YouTubeApiError) -> void: errors.append(error))
	var process: Dictionary = OS.execute_with_pipe(binary, PackedStringArray(["-test.run=TestFrameEmitterProcess"]), false)
	source._stdio = process.get("stdio", null)
	source._stderr = process.get("stderr", null)
	source._pid = int(process.get("pid", -1))
	source._active = true
	source.set_process(true)
	var checks: Array[bool] = [source._pid > 0 and source._stdio != null]
	var deadline: int = Time.get_ticks_msec() + 5000
	while pages.size() < 2 and errors.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	checks.append(pages.size() == 2)
	checks.append(errors.is_empty())
	if pages.size() == 2:
		checks.append(pages[1].next_page_token == "second")
	var pid: int = source._pid
	source.stop("boundary test complete")
	checks.append(not OS.is_process_running(pid))
	source.queue_free()
	await process_frame
	var failures: int = checks.count(false)
	print("NATIVE STREAM PIPE BOUNDARY %s: %d checks, %d failed" % ["PASS" if failures == 0 else "FAIL", checks.size(), failures])
	quit(0 if failures == 0 else 1)
