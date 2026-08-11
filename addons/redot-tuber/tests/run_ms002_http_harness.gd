extends SceneTree

const TransportClass = preload("res://addons/redot-tuber/transport/youtube_http_transport.gd")
const CancellationClass = preload("res://addons/redot-tuber/transport/cancellation_token.gd")
const MAX_FRAMES: int = 300

var _checks: int = 0
var _failures: PackedStringArray = []
var _server: TCPServer = null
var _peers: Array[Dictionary] = []
var _path_counts: Dictionary = {}
var _release_delayed: bool = false


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	_server = TCPServer.new()
	var listen_error: Error = _server.listen(0, "127.0.0.1")
	_check(listen_error == OK, "loopback harness binds 127.0.0.1")
	if listen_error != OK:
		_finish()
		return

	var transport: YouTubeHttpTransport = TransportClass.new()
	transport.max_concurrent_requests = 2
	transport.max_retries = 1
	transport.retry_base_delay_msec = 1
	transport.timeout_seconds = 1.0
	transport.response_body_limit_bytes = 1024
	root.add_child(transport)

	await _test_success_and_redaction(transport)
	await _test_retry(transport)
	await _test_concurrency(transport)
	await _test_cancellation(transport)
	await _test_body_and_scheme_limits(transport)

	transport.free()
	_close_server()
	_finish()


func _test_success_and_redaction(transport: YouTubeHttpTransport) -> void:
	print("MS-002 HTTP phase: success/redaction")
	var started_urls: PackedStringArray = PackedStringArray()
	var capture: Callable = func(_ticket_id: int, redacted_url: String, _attempt: int) -> void: started_urls.append(redacted_url)
	transport.request_started.connect(capture)
	var secret: String = "fixture-api-secret"
	var ticket: YouTubeHttpTicket = transport.request(_url("/ok?key=" + secret.uri_encode()))
	await _drive_until_completed([ticket])
	transport.request_started.disconnect(capture)
	_check(ticket.response != null and ticket.response.is_success(), "loopback JSON request succeeds")
	_check(ticket.response.parsed_json is Dictionary and ticket.response.parsed_json.get("ok", false), "successful response parses JSON")
	_check(started_urls.size() == 1, "success starts exactly one request")
	if started_urls.size() == 1:
		_check(not started_urls[0].contains(secret), "request_started URL redacts API key")
		_check(started_urls[0].contains("[REDACTED]"), "redacted URL exposes an explicit marker")


func _test_retry(transport: YouTubeHttpTransport) -> void:
	print("MS-002 HTTP phase: retry")
	var retries: Array[int] = []
	var capture: Callable = func(_ticket_id: int, attempt: int, _delay: int) -> void: retries.append(attempt)
	transport.request_retried.connect(capture)
	var ticket: YouTubeHttpTicket = transport.request(_url("/retry"))
	await _drive_until_completed([ticket])
	transport.request_retried.disconnect(capture)
	_check(ticket.response != null and ticket.response.is_success(), "transient 503 retries to success")
	_check(ticket.response.attempt_count == 2, "retry response reports two attempts")
	_check(int(_path_counts.get("/retry", 0)) == 2, "fake server observes exactly one retry")
	_check(retries == [2], "retry signal reports the next attempt")


func _test_concurrency(transport: YouTubeHttpTransport) -> void:
	print("MS-002 HTTP phase: concurrency")
	_release_delayed = false
	var started: Array[int] = []
	var capture: Callable = func(ticket_id: int, _url_value: String, _attempt: int) -> void: started.append(ticket_id)
	transport.request_started.connect(capture)
	var tickets: Array[YouTubeHttpTicket] = [
		transport.request(_url("/delayed/one")),
		transport.request(_url("/delayed/two")),
		transport.request(_url("/delayed/three")),
	]
	for _frame: int in 20:
		_service_server()
		await process_frame
	_check(transport.active_count() == 2, "transport enforces configured concurrency")
	_check(transport.queued_count() == 1, "excess request remains queued")
	_check(started.size() == 2, "queued request is not started early")
	_release_delayed = true
	await _drive_until_completed(tickets)
	transport.request_started.disconnect(capture)
	_check(tickets.all(func(ticket: YouTubeHttpTicket) -> bool: return ticket.response != null and ticket.response.is_success()), "all bounded-concurrency requests finish")
	_check(started.size() == 3, "queued request starts after a slot opens")


func _test_cancellation(transport: YouTubeHttpTransport) -> void:
	print("MS-002 HTTP phase: cancellation")
	var cancellation: YouTubeCancellationToken = CancellationClass.new()
	var ticket: YouTubeHttpTicket = transport.request(_url("/slow"), PackedStringArray(), HTTPClient.METHOD_GET, PackedByteArray(), cancellation)
	for _frame: int in 10:
		_service_server()
		await process_frame
	cancellation.cancel("fixture stop")
	await _drive_until_completed([ticket])
	_check(ticket.is_cancelled, "active request ticket records cancellation")
	_check(ticket.cancellation_reason == "fixture stop", "cancellation preserves safe reason")
	_check(ticket.response != null and ticket.response.error != null and ticket.response.error.category == "cancelled", "cancellation returns typed error")
	_check(transport.active_count() == 0, "cancelled request releases concurrency slot")


func _test_body_and_scheme_limits(transport: YouTubeHttpTransport) -> void:
	print("MS-002 HTTP phase: limits")
	var oversized: YouTubeHttpTicket = transport.request(_url("/oversized"))
	await _drive_until_completed([oversized])
	_check(oversized.response != null and not oversized.response.is_success(), "oversized response is rejected")
	_check(oversized.response.request_result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, "oversized response reports body limit result")
	var insecure: YouTubeHttpTicket = transport.request("http://example.com/unsafe")
	_check(insecure.is_completed and insecure.response.error.category == "transport", "non-loopback HTTP is rejected before network access")
	var large_body: PackedByteArray = PackedByteArray()
	large_body.resize(transport.request_body_limit_bytes + 1)
	var body_ticket: YouTubeHttpTicket = transport.request(_url("/ok"), PackedStringArray(), HTTPClient.METHOD_POST, large_body)
	_check(body_ticket.is_completed and body_ticket.response.error != null, "oversized request body is rejected before network access")


func _drive_until_completed(tickets: Array, max_frames: int = MAX_FRAMES) -> void:
	for _frame: int in max_frames:
		_service_server()
		var done: bool = true
		for ticket: Variant in tickets:
			if not ticket.is_completed:
				done = false
				break
		if done:
			return
		await process_frame
	_failures.append("timed out waiting for HTTP tickets")


func _service_server() -> void:
	while _server != null and _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		_peers.append({"peer": peer, "request": "", "responded": false, "path": ""})
	for item: Dictionary in _peers:
		if bool(item.responded):
			continue
		var peer: StreamPeerTCP = item.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			item.responded = true
			continue
		var available: int = peer.get_available_bytes()
		if available > 0:
			item.request = String(item.request) + peer.get_utf8_string(available)
		if not String(item.request).contains("\r\n\r\n"):
			continue
		if String(item.path).is_empty():
			var first_line: String = String(item.request).split("\r\n", false)[0]
			var parts: PackedStringArray = first_line.split(" ", false)
			item.path = parts[1].split("?", false)[0] if parts.size() >= 2 else "/invalid"
			_path_counts[item.path] = int(_path_counts.get(item.path, 0)) + 1
		var path: String = item.path
		if path == "/slow" or (path.begins_with("/delayed/") and not _release_delayed):
			continue
		if path == "/retry" and int(_path_counts[path]) == 1:
			_send_json(peer, 503, {"error": {"message": "fixture transient"}})
		elif path == "/oversized":
			var oversized_body: PackedByteArray = PackedByteArray()
			oversized_body.resize(2048)
			oversized_body.fill(65)
			_send_bytes(peer, 200, "application/octet-stream", oversized_body)
		else:
			_send_json(peer, 200, {"ok": true, "path": path})
		item.responded = true


func _send_json(peer: StreamPeerTCP, status: int, payload: Dictionary) -> void:
	_send_bytes(peer, status, "application/json", JSON.stringify(payload).to_utf8_buffer())


func _send_bytes(peer: StreamPeerTCP, status: int, content_type: String, body: PackedByteArray) -> void:
	var reason: String = "OK" if status == 200 else "Service Unavailable"
	var header: String = (
		"HTTP/1.1 %d %s\r\n" % [status, reason] +
		"Content-Type: %s\r\n" % content_type +
		"Content-Length: %d\r\n" % body.size() +
		"Connection: close\r\n\r\n"
	)
	peer.put_data(header.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()


func _url(path: String) -> String:
	return "http://127.0.0.1:%d%s" % [_server.get_local_port(), path]


func _close_server() -> void:
	for item: Dictionary in _peers:
		var peer: StreamPeerTCP = item.peer
		if peer != null:
			peer.disconnect_from_host()
	_peers.clear()
	if _server != null:
		_server.stop()
	_server = null


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-002 HTTP HARNESS PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-002 HTTP HARNESS FAIL: %s" % failure)
	print("MS-002 HTTP HARNESS FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
