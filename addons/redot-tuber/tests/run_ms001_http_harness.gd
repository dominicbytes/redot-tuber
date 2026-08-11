extends SceneTree

const FramerClass = preload("res://addons/redot-tuber/transport/json_stream_framer.gd")
const CancellationClass = preload("res://addons/redot-tuber/transport/cancellation_token.gd")
const STREAM_FIXTURE: String = "res://addons/redot-tuber/tests/fixtures/live_chat_stream.json"
const MAX_LOOP_FRAMES: int = 900
const BODY_READ_CHUNK_BYTES: int = 256
const WIRE_CHUNK_PATTERN: Array[int] = [1, 7, 3, 19, 2, 11]

var _checks: int = 0
var _failures: PackedStringArray = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var fixture: Dictionary = _load_json_object(STREAM_FIXTURE)
	var responses: Array = fixture.get("responses", [])
	_check(responses.size() == 3, "stream fixture contains reconnect sequence")
	if responses.size() != 3:
		_finish()
		return

	var first_leg: Dictionary = await _run_http_exchange(responses.slice(0, 2), "", false)
	_check(String(first_leg.get("error", "")).is_empty(), "first HTTP stream leg completes")
	_check(int(first_leg.get("response_code", 0)) == 200, "first HTTP stream leg returns 200")
	_check((first_leg.get("frames", []) as Array).size() == 2, "HTTPClient incrementally receives first two frames")
	_check(String(first_leg.get("request", "")).begins_with("GET /stream HTTP/1.1"), "fake server captures initial request")
	_check(int(first_leg.get("max_buffered", 0)) <= 1024 * 1024, "first leg buffer remains bounded")

	var first_frames: Array = first_leg.get("frames", [])
	var resume_token: String = ""
	if first_frames.size() == 2:
		resume_token = String(first_frames[1].get("nextPageToken", ""))
	_check(resume_token == "fixture-token-2", "last complete response supplies reconnect token")

	var resumed_leg: Dictionary = await _run_http_exchange([responses[2]], resume_token, false)
	_check(String(resumed_leg.get("error", "")).is_empty(), "resumed HTTP stream leg completes")
	_check((resumed_leg.get("frames", []) as Array).size() == 1, "resume receives remaining response")
	_check(String(resumed_leg.get("request", "")).contains("pageToken=fixture-token-2"), "resume token is sent in reconnect request")
	var resumed_frames: Array = resumed_leg.get("frames", [])
	if resumed_frames.size() == 1:
		_check(String(resumed_frames[0].get("offlineAt", "")) != "", "resumed response preserves offline terminal state")

	var cancelled_leg: Dictionary = await _run_http_exchange(responses, "", true)
	_check(String(cancelled_leg.get("error", "")).is_empty(), "cancelled HTTP stream exits cleanly")
	_check(bool(cancelled_leg.get("cancelled", false)), "cancellation closes the HTTP client")
	_check((cancelled_leg.get("frames", []) as Array).size() == 1, "cancellation stops delivery after first complete response")
	_check(int(cancelled_leg.get("max_buffered", 0)) <= 1024 * 1024, "cancelled leg buffer remains bounded")

	_finish()


func _run_http_exchange(responses: Array, resume_token: String, cancel_after_first: bool) -> Dictionary:
	var result: Dictionary = {
		"error": "",
		"frames": [],
		"request": "",
		"response_code": 0,
		"cancelled": false,
		"max_buffered": 0,
	}
	var server: TCPServer = TCPServer.new()
	var listen_error: Error = server.listen(0, "127.0.0.1")
	if listen_error != OK:
		result.error = "listen failed: %s" % error_string(listen_error)
		return result

	var client: HTTPClient = HTTPClient.new()
	client.set_read_chunk_size(BODY_READ_CHUNK_BYTES)
	var connect_error: Error = client.connect_to_host("127.0.0.1", server.get_local_port())
	if connect_error != OK:
		server.stop()
		result.error = "connect failed: %s" % error_string(connect_error)
		return result

	var request_path: String = "/stream"
	if not resume_token.is_empty():
		request_path += "?pageToken=%s" % resume_token.uri_encode()
	var request_sent: bool = false
	var server_peer: StreamPeerTCP = null
	var response_headers_sent: bool = false
	var response_end_sent: bool = false
	var wire_payload: PackedByteArray = _encode_responses(responses)
	var wire_offset: int = 0
	var chunk_pattern_index: int = 0
	var framer: Variant = FramerClass.new(1024 * 1024)
	var token: Variant = CancellationClass.new()
	var received_frames: Array[Dictionary] = []

	for _loop_index: int in MAX_LOOP_FRAMES:
		var poll_error: Error = client.poll()
		if poll_error != OK and not token.is_cancelled():
			result.error = "HTTPClient poll failed: %s" % error_string(poll_error)
			break

		if server_peer == null and server.is_connection_available():
			server_peer = server.take_connection()

		if client.get_status() == HTTPClient.STATUS_CONNECTED and not request_sent:
			var request_error: Error = client.request(HTTPClient.METHOD_GET, request_path, PackedStringArray(["Accept: application/json"]))
			if request_error != OK:
				result.error = "request failed: %s" % error_string(request_error)
				break
			request_sent = true

		if server_peer != null:
			server_peer.poll()
			var available_request_bytes: int = server_peer.get_available_bytes()
			if available_request_bytes > 0:
				result.request += server_peer.get_utf8_string(available_request_bytes)
			if not response_headers_sent and String(result.request).contains("\r\n\r\n"):
				var header_error: Error = server_peer.put_data((
					"HTTP/1.1 200 OK\r\n" +
					"Content-Type: application/json; charset=utf-8\r\n" +
					"Transfer-Encoding: chunked\r\n" +
					"Connection: close\r\n\r\n"
				).to_utf8_buffer())
				if header_error != OK:
					result.error = "response header send failed: %s" % error_string(header_error)
					break
				response_headers_sent = true
			elif response_headers_sent and wire_offset < wire_payload.size():
				var planned_chunk_size: int = WIRE_CHUNK_PATTERN[chunk_pattern_index % WIRE_CHUNK_PATTERN.size()]
				chunk_pattern_index += 1
				var next_offset: int = mini(wire_payload.size(), wire_offset + planned_chunk_size)
				var body_chunk: PackedByteArray = wire_payload.slice(wire_offset, next_offset)
				var send_error: Error = _send_chunked_body_piece(server_peer, body_chunk)
				if send_error != OK:
					result.error = "response body send failed: %s" % error_string(send_error)
					break
				wire_offset = next_offset
			elif response_headers_sent and wire_offset == wire_payload.size() and not response_end_sent:
				var end_error: Error = server_peer.put_data("0\r\n\r\n".to_utf8_buffer())
				if end_error != OK:
					result.error = "response terminator send failed: %s" % error_string(end_error)
					break
				response_end_sent = true

		if client.has_response():
			result.response_code = client.get_response_code()

		if client.get_status() == HTTPClient.STATUS_BODY:
			var received_chunk: PackedByteArray = client.read_response_body_chunk()
			if not received_chunk.is_empty():
				received_frames.append_array(framer.push_chunk(received_chunk))
				result.max_buffered = maxi(int(result.max_buffered), framer.buffered_byte_count())
				if not framer.last_error().is_empty():
					result.error = framer.last_error()
					break
				if cancel_after_first and received_frames.size() >= 1:
					token.cancel("fixture cancellation")
					client.close()
					result.cancelled = true
					break

		if response_end_sent and received_frames.size() == responses.size() and client.get_status() != HTTPClient.STATUS_BODY:
			break
		await process_frame

	if String(result.error).is_empty() and not bool(result.cancelled) and received_frames.size() != responses.size():
		result.error = "exchange ended with %d of %d responses" % [received_frames.size(), responses.size()]
	result.frames = received_frames
	client.close()
	if server_peer != null:
		server_peer.disconnect_from_host()
	server.stop()
	return result


func _encode_responses(responses: Array) -> PackedByteArray:
	var encoded: PackedStringArray = []
	for response: Variant in responses:
		encoded.append(JSON.stringify(response))
	return ("\n".join(encoded) + "\n").to_utf8_buffer()


func _send_chunked_body_piece(peer: StreamPeerTCP, body: PackedByteArray) -> Error:
	var header_error: Error = peer.put_data(("%x\r\n" % body.size()).to_utf8_buffer())
	if header_error != OK:
		return header_error
	var body_error: Error = peer.put_data(body)
	if body_error != OK:
		return body_error
	return peer.put_data("\r\n".to_utf8_buffer())


func _load_json_object(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("fixture opens: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_failures.append("fixture is a JSON object: %s" % path)
		return {}
	return parsed


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-001 HTTP HARNESS PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-001 HTTP HARNESS FAIL: %s" % failure)
	print("MS-001 HTTP HARNESS FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
