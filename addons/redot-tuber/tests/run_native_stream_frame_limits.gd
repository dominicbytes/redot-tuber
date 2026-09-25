extends SceneTree
## Invalid and oversized helper frames must fail closed without exposing input.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var checks: Array[bool] = []
	var source: YouTubeLiveChatStreamSource = YouTubeLiveChatStreamSource.new()
	root.add_child(source)
	var errors: Array[YouTubeApiError] = []
	source.error_occurred.connect(func(error: YouTubeApiError) -> void: errors.append(error))
	for frame: String in ["not-json", "{\"protocol\":\"wrong\",\"kind\":\"page\"}", "{\"protocol\":\"RTSL/1\",\"kind\":\"mystery\"}"]:
		source._active = true
		source._accept_frame(frame.to_utf8_buffer())
		checks.append(not source.is_active() and errors.back().category == "stream_framing")
	source._active = true
	source.max_partial_frame_bytes = 65536
	var oversized: PackedByteArray = PackedByteArray()
	oversized.resize(65537)
	source._accept_frame(oversized)
	checks.append(not source.is_active() and errors.back().category == "stream_framing")
	checks.append(errors.size() == 4)
	var api: YouTubeApiClient = YouTubeApiClient.new()
	api.configure("fixture-key")
	source.configure(api, YouTubeLiveChatService.new(api))
	source._active = true
	source._attempt = 2
	source._accept_frame("{\"protocol\":\"RTSL/1\",\"kind\":\"page\",\"page\":{\"items\":[],\"nextPageToken\":\"cursor\"}}".to_utf8_buffer())
	checks.append(source._attempt == 0 and source.next_page_token() == "cursor")
	source.stop("fixture complete")
	source.queue_free()
	await process_frame
	var failures: int = checks.count(false)
	print("NATIVE STREAM FRAME LIMITS %s: %d checks, %d failed" % ["PASS" if failures == 0 else "FAIL", checks.size(), failures])
	quit(0 if failures == 0 else 1)
