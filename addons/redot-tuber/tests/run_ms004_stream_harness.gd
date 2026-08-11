extends SceneTree

const ContractPath: String = "res://addons/redot-tuber/contracts/youtube_api_contract.json"
const WIRE_CHUNKS: Array[int] = [1, 3, 11, 2, 17, 5]

var _checks: int = 0
var _failures: PackedStringArray = []


class StreamServer extends Node:
	var server: TCPServer = TCPServer.new()
	var legs: Array = []
	var peers: Array[Dictionary] = []
	var requests: PackedStringArray = PackedStringArray()
	var connection_count: int = 0

	func start(response_legs: Array) -> Error:
		legs = response_legs
		var error: Error = server.listen(0, "127.0.0.1")
		set_process(error == OK)
		return error

	func port() -> int:
		return server.get_local_port()

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			var leg_index: int = connection_count
			connection_count += 1
			peers.append({
				"peer": server.take_connection(),
				"leg": leg_index,
				"request": "",
				"headers_sent": false,
				"payload": PackedByteArray(),
				"offset": 0,
				"chunk_index": 0,
				"finished": false,
			})
		for item: Dictionary in peers:
			if bool(item.finished):
				continue
			var peer: StreamPeerTCP = item.peer
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				item.finished = true
				continue
			var available: int = peer.get_available_bytes()
			if available > 0:
				item.request = String(item.request) + peer.get_utf8_string(available)
			if not String(item.request).contains("\r\n\r\n"):
				continue
			var leg_index: int = int(item.leg)
			if leg_index >= legs.size():
				_send_error(peer)
				item.finished = true
				continue
			var leg: Dictionary = legs[leg_index]
			if not bool(item.headers_sent):
				requests.append(String(item.request))
				item.payload = _encode(leg.get("responses", []))
				peer.put_data((
					"HTTP/1.1 200 OK\r\n" +
					"Content-Type: application/json; charset=utf-8\r\n" +
					"Transfer-Encoding: chunked\r\n" +
					"Connection: close\r\n\r\n"
				).to_utf8_buffer())
				item.headers_sent = true
				continue
			var payload: PackedByteArray = item.payload
			var offset: int = int(item.offset)
			if offset < payload.size():
				var chunk_size: int = WIRE_CHUNKS[int(item.chunk_index) % WIRE_CHUNKS.size()]
				item.chunk_index = int(item.chunk_index) + 1
				var next_offset: int = mini(payload.size(), offset + chunk_size)
				_send_chunk(peer, payload.slice(offset, next_offset))
				item.offset = next_offset
			elif not bool(leg.get("hold_open", false)):
				peer.put_data("0\r\n\r\n".to_utf8_buffer())
				peer.disconnect_from_host()
				item.finished = true

	func stop() -> void:
		set_process(false)
		for item: Dictionary in peers:
			var peer: StreamPeerTCP = item.peer
			if peer != null:
				peer.disconnect_from_host()
		peers.clear()
		server.stop()

	func _encode(responses: Array) -> PackedByteArray:
		var encoded: PackedStringArray = PackedStringArray()
		for response: Variant in responses:
			encoded.append(JSON.stringify(response))
		return ("\n".join(encoded) + "\n").to_utf8_buffer()

	func _send_chunk(peer: StreamPeerTCP, bytes: PackedByteArray) -> void:
		peer.put_data(("%x\r\n" % bytes.size()).to_utf8_buffer())
		peer.put_data(bytes)
		peer.put_data("\r\n".to_utf8_buffer())

	func _send_error(peer: StreamPeerTCP) -> void:
		var body: PackedByteArray = JSON.stringify({"error": {"message": "unexpected connection"}}).to_utf8_buffer()
		peer.put_data((
			"HTTP/1.1 500 Internal Server Error\r\n" +
			"Content-Type: application/json\r\n" +
			"Content-Length: %d\r\n" % body.size() +
			"Connection: close\r\n\r\n"
		).to_utf8_buffer())
		peer.put_data(body)
		peer.disconnect_from_host()


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	await _test_reconnect_and_resume()
	await _test_cancellation()
	_finish()


func _test_reconnect_and_resume() -> void:
	var first_page: Dictionary = {
		"nextPageToken": "resume-token-1",
		"items": [{"id": "message-1", "snippet": {"type": "textMessageEvent", "liveChatId": "chat-1", "displayMessage": "First", "textMessageDetails": {"messageText": "First"}}}],
	}
	var terminal_page: Dictionary = {
		"nextPageToken": "resume-token-2",
		"offlineAt": "2026-08-10T12:05:00Z",
		"items": [{"id": "gift-1", "snippet": {"type": "giftEvent", "liveChatId": "chat-1", "giftEventDetails": {"giftMetadata": {"giftName": "Star", "comboCount": 2}}}}],
	}
	var server: StreamServer = StreamServer.new()
	root.add_child(server)
	_check(server.start([
		{"responses": [first_page], "hold_open": false},
		{"responses": [terminal_page], "hold_open": false},
	]) == OK, "stream harness binds IPv4 loopback")
	var context: Dictionary = _stream_context(server.port())
	var source: YouTubeLiveChatStreamSource = context.source
	source.reconnect_base_delay_msec = 1
	source.reconnect_max_delay_msec = 2
	source.max_reconnect_attempts = 2
	var pages: Array[YouTubeLiveChatPage] = []
	var stop_state: Dictionary = {"reason": ""}
	source.page_received.connect(func(page: YouTubeLiveChatPage) -> void: pages.append(page))
	source.stopped.connect(func(reason: String) -> void: stop_state.reason = reason)
	var start_error: YouTubeApiError = source.start("chat-1")
	_check(start_error == null, "stream source starts")
	for _frame: int in 900:
		if not source.is_active():
			break
		await process_frame
	_check(pages.size() == 2, "stream source delivers both connection legs")
	if pages.size() == 2:
		_check(pages[0].events.size() == 1 and pages[0].events[0].text_details.message_text == "First", "stream source normalizes typed text event")
		_check(pages[1].events.size() == 1 and pages[1].events[0].gift_details.combo_count == 2, "resumed stream normalizes typed gift update")
		_check(pages[1].is_terminal(), "stream source preserves terminal offline state")
	_check(String(stop_state.reason) == "chat ended" and not source.is_active(), "terminal stream stops cleanly")
	_check(source.next_page_token() == "resume-token-2", "stream source retains the latest continuation token")
	_check(server.requests.size() == 2, "stream source reconnects exactly once")
	if server.requests.size() == 2:
		_check(not server.requests[0].contains("pageToken="), "initial stream request has no continuation token")
		_check(server.requests[1].contains("pageToken=resume-token-1"), "reconnect sends the last complete continuation token")
	var ledger: YouTubeQuotaLedger = context.ledger
	_check(ledger.request_count("liveChatMessages.streamList") == 2, "each stream connection is quota-accounted")
	_cleanup_context(context, server)
	await process_frame
	await process_frame


func _test_cancellation() -> void:
	var page_payload: Dictionary = {
		"nextPageToken": "cancel-token",
		"items": [{"id": "message-cancel", "snippet": {"type": "textMessageEvent", "liveChatId": "chat-cancel", "textMessageDetails": {"messageText": "Before cancel"}}}],
	}
	var server: StreamServer = StreamServer.new()
	root.add_child(server)
	_check(server.start([{"responses": [page_payload], "hold_open": true}]) == OK, "cancellation harness binds IPv4 loopback")
	var context: Dictionary = _stream_context(server.port())
	var source: YouTubeLiveChatStreamSource = context.source
	var token: YouTubeCancellationToken = YouTubeCancellationToken.new()
	var pages: Array[YouTubeLiveChatPage] = []
	var stop_state: Dictionary = {"reason": ""}
	source.page_received.connect(func(page: YouTubeLiveChatPage) -> void: pages.append(page))
	source.stopped.connect(func(reason: String) -> void: stop_state.reason = reason)
	_check(source.start("chat-cancel", "", token) == null, "cancellable stream starts")
	for _frame: int in 600:
		if not pages.is_empty():
			break
		await process_frame
	_check(pages.size() == 1, "cancellable stream delivers the complete frame before cancellation")
	token.cancel("fixture cancellation")
	for _frame: int in 30:
		if not source.is_active():
			break
		await process_frame
	_check(not source.is_active() and String(stop_state.reason) == "fixture cancellation", "cancellation closes the active HTTPClient with its safe reason")
	_cleanup_context(context, server)
	await process_frame
	await process_frame


func _stream_context(port: int) -> Dictionary:
	var contract: Dictionary = _load_json(ContractPath)
	var ledger: YouTubeQuotaLedger = YouTubeQuotaLedger.new(contract.get("endpoints", []), 100)
	var api: YouTubeApiClient = YouTubeApiClient.new(null, ledger)
	api.configure("fixture-key", "", "http://127.0.0.1:%d" % port)
	var gate: YouTubeCapabilityGate = YouTubeCapabilityGate.new()
	gate.configure(PackedStringArray(["chat.read"]), false)
	var chat: YouTubeLiveChatService = YouTubeLiveChatService.new(api, gate)
	var source: YouTubeLiveChatStreamSource = YouTubeLiveChatStreamSource.new()
	source.configure(api, chat, gate)
	root.add_child(source)
	return {"ledger": ledger, "api": api, "gate": gate, "chat": chat, "source": source}


func _cleanup_context(context: Dictionary, server: StreamServer) -> void:
	var source: YouTubeLiveChatStreamSource = context.source
	if source.is_active():
		source.stop("test cleanup")
	source.queue_free()
	server.stop()
	server.queue_free()


func _load_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("fixture opens: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_failures.append("fixture parses: %s" % path)
		return {}
	return parsed


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-004 STREAM HARNESS PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-004 STREAM HARNESS FAIL: %s" % failure)
	print("MS-004 STREAM HARNESS FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
