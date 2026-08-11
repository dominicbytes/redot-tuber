extends SceneTree

const ContractPath: String = "res://addons/redot-tuber/contracts/youtube_api_contract.json"

var _checks: int = 0
var _failures: PackedStringArray = []


class ApiServer extends Node:
	var server: TCPServer = TCPServer.new()
	var peers: Array[Dictionary] = []
	var requests: Array[Dictionary] = []

	func start() -> Error:
		var error: Error = server.listen(0, "127.0.0.1")
		set_process(error == OK)
		return error

	func port() -> int:
		return server.get_local_port()

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			peers.append({"peer": server.take_connection(), "request": PackedByteArray(), "responded": false})
		for item: Dictionary in peers:
			if bool(item.responded):
				continue
			var peer: StreamPeerTCP = item.peer
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
				continue
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				item.responded = true
				continue
			var available: int = peer.get_available_bytes()
			if available > 0:
				var request_bytes: PackedByteArray = item.request
				request_bytes.append_array(peer.get_data(available)[1])
				item.request = request_bytes
			var request_text: String = (item.request as PackedByteArray).get_string_from_utf8()
			var header_end: int = request_text.find("\r\n\r\n")
			if header_end < 0:
				continue
			var content_length: int = _content_length(request_text.substr(0, header_end))
			var body_start: int = header_end + 4
			if (item.request as PackedByteArray).size() < body_start + content_length:
				continue
			var captured: Dictionary = _capture(request_text, body_start, content_length)
			requests.append(captured)
			_respond(peer, captured)
			item.responded = true

	func stop() -> void:
		set_process(false)
		for item: Dictionary in peers:
			var peer: StreamPeerTCP = item.peer
			if peer != null:
				peer.disconnect_from_host()
		peers.clear()
		server.stop()

	func _content_length(headers: String) -> int:
		for line: String in headers.split("\r\n", false):
			if line.to_lower().begins_with("content-length:"):
				return int(line.get_slice(":", 1).strip_edges())
		return 0

	func _capture(request_text: String, body_start: int, content_length: int) -> Dictionary:
		var lines: PackedStringArray = request_text.split("\r\n", false)
		var request_parts: PackedStringArray = lines[0].split(" ", false)
		var target: String = request_parts[1] if request_parts.size() >= 2 else "/invalid"
		var body_text: String = request_text.substr(body_start, content_length)
		var parsed_body: Variant = JSON.parse_string(body_text) if not body_text.is_empty() else {}
		return {
			"method": request_parts[0] if not request_parts.is_empty() else "",
			"target": target,
			"path": target.split("?", false)[0],
			"headers": request_text.substr(0, request_text.find("\r\n\r\n")),
			"body": parsed_body if parsed_body is Dictionary else {},
		}

	func _respond(peer: StreamPeerTCP, request: Dictionary) -> void:
		var method: String = String(request.method)
		var path: String = String(request.path)
		if method == "DELETE":
			_send(peer, 204, null)
			return
		var body: Dictionary = request.body
		match path:
			"/liveChat/messages":
				var message: Dictionary = body.duplicate(true)
				message["id"] = "server-message"
				_send(peer, 200, message)
			"/liveChat/bans":
				var ban: Dictionary = body.duplicate(true)
				ban["id"] = "server-ban"
				_send(peer, 200, ban)
			"/liveBroadcasts/transition":
				_send(peer, 200, {"id": "broadcast-1", "snippet": {"title": "Fixture"}, "status": {"lifeCycleStatus": "live"}})
			"/liveStreams":
				_send(peer, 200, {"id": "stream-1", "snippet": body.get("snippet", {}), "cdn": {"ingestionType": "rtmp", "resolution": "1080p", "frameRate": "60fps", "ingestionInfo": {"streamName": "server-stream-secret"}}})
			_:
				_send(peer, 404, {"error": {"message": "not found", "errors": [{"reason": "notFound"}]}})

	func _send(peer: StreamPeerTCP, status: int, payload: Variant) -> void:
		var body: PackedByteArray = PackedByteArray() if payload == null else JSON.stringify(payload).to_utf8_buffer()
		var reason: String = "OK" if status == 200 else ("No Content" if status == 204 else "Not Found")
		var headers: String = "HTTP/1.1 %d %s\r\nContent-Length: %d\r\nConnection: close\r\n" % [status, reason, body.size()]
		if payload != null:
			headers += "Content-Type: application/json; charset=utf-8\r\n"
		headers += "\r\n"
		peer.put_data(headers.to_utf8_buffer())
		if not body.is_empty():
			peer.put_data(body)
		peer.disconnect_from_host()


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var server: ApiServer = ApiServer.new()
	root.add_child(server)
	_check(server.start() == OK, "authorized API harness binds IPv4 loopback")
	if server.port() <= 0:
		_finish()
		return
	var contract: Dictionary = _load_json(ContractPath)
	var ledger: YouTubeQuotaLedger = YouTubeQuotaLedger.new(contract.get("endpoints", []), 1000)
	var transport: YouTubeHttpTransport = YouTubeHttpTransport.new()
	transport.max_retries = 0
	root.add_child(transport)
	var api: YouTubeApiClient = YouTubeApiClient.new(transport, ledger)
	_check(api.configure("", "fixture-access-value", "http://127.0.0.1:%d" % server.port()) == null, "authorized API client accepts loopback fixture endpoint")
	var preflight_state: Dictionary = {"count": 0}
	api.set_authorization_preflight(func() -> YouTubeApiError: preflight_state.count = int(preflight_state.count) + 1; return null)
	var capabilities: PackedStringArray = YouTubeScopeRegistry.new().all_capabilities()
	var gate: YouTubeCapabilityGate = YouTubeCapabilityGate.new()
	gate.configure(capabilities, true)

	var chat: YouTubeLiveChatService = YouTubeLiveChatService.new(api, gate)
	print("MS-005 HTTP phase: chat insert")
	var sent: YouTubeOperationResult = await chat.send_text("chat-1", "Hello from Redot")
	_check(sent.is_success() and (sent.value as YouTubeLiveEvent).id == "server-message", "real transport sends a chat message")
	var moderation: YouTubeModerationService = YouTubeModerationService.new(api, gate)
	print("MS-005 HTTP phase: message delete")
	var deleted: YouTubeOperationResult = await moderation.delete_message("message-1", true)
	_check(deleted.is_success() and deleted.value == true, "real transport accepts empty moderation delete response")
	print("MS-005 HTTP phase: temporary ban")
	var banned: YouTubeOperationResult = await moderation.ban_user("chat-1", "target-1", "temporary", 300, true)
	_check(banned.is_success() and (banned.value as YouTubeLiveChatBan).id == "server-ban", "real transport sends typed temporary ban")
	var broadcasts: YouTubeBroadcastService = YouTubeBroadcastService.new(api, gate)
	print("MS-005 HTTP phase: broadcast transition")
	var transitioned: YouTubeOperationResult = await broadcasts.transition_broadcast("broadcast-1", "live", "ready", true)
	_check(transitioned.is_success() and (transitioned.value as YouTubeLiveBroadcast).life_cycle_status == "live", "real transport sends guarded broadcast transition")
	var stream: YouTubeLiveStream = YouTubeLiveStream.new()
	stream.title = "Fixture encoder"
	stream.ingestion_type = "rtmp"
	stream.resolution = "1080p"
	stream.frame_rate = "60fps"
	var streams: YouTubeStreamService = YouTubeStreamService.new(api, gate)
	print("MS-005 HTTP phase: stream create")
	var created_stream: YouTubeOperationResult = await streams.create_stream(stream)
	_check(created_stream.is_success() and (created_stream.value as YouTubeLiveStream).stream_name == "server-stream-secret", "real transport returns in-memory stream ingestion data")

	_check(server.requests.size() == 5, "server observes exactly the five authorized operations")
	_check(int(preflight_state.count) == 5, "every authorized REST operation runs token-freshness preflight")
	if server.requests.size() == 5:
		for request: Dictionary in server.requests:
			_check(String(request.headers).contains("Authorization: Bearer fixture-access-value"), "authorized REST request carries the bearer header")
		_check(server.requests[0].method == "POST" and String(server.requests[0].target).contains("part=snippet"), "chat insert uses POST and the official part query")
		_check(server.requests[1].method == "DELETE" and String(server.requests[1].target).contains("id=message-1"), "message delete uses DELETE with its resource ID")
		_check(server.requests[2].body.snippet.type == "temporary" and server.requests[2].body.snippet.banDurationSeconds == 300, "ban JSON body survives real serialization")
		_check(String(server.requests[3].target).contains("broadcastStatus=live"), "transition query survives real URL encoding")
		_check(not (server.requests[4].body.cdn as Dictionary).has("ingestionInfo"), "stream create body contains no echoed ingestion credential")
	_check(ledger.total_units() == 250, "five conservative write operations consume their classified local units")

	var blocked_ledger: YouTubeQuotaLedger = YouTubeQuotaLedger.new(contract.get("endpoints", []), 0)
	var blocked_api: YouTubeApiClient = YouTubeApiClient.new(transport, blocked_ledger)
	blocked_api.configure("fixture-key", "", "http://127.0.0.1:%d" % server.port())
	var before_blocked: int = server.requests.size()
	print("MS-005 HTTP phase: quota preflight")
	var blocked_response: YouTubeHttpResponse = await blocked_api.request_json("videos.list", HTTPClient.METHOD_GET, "/videos", {"part": "id", "id": "video-1"})
	_check(blocked_response.error != null and blocked_response.error.category == "quota_budget", "local quota exhaustion returns a typed error")
	await process_frame
	_check(server.requests.size() == before_blocked, "quota-exhausted request never reaches the network")

	(created_stream.value as YouTubeLiveStream).clear_sensitive()
	transport.queue_free()
	server.stop()
	server.queue_free()
	await process_frame
	await process_frame
	_finish()


func _load_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("fixture opens: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-005 HTTP HARNESS PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-005 HTTP HARNESS FAIL: %s" % failure)
	print("MS-005 HTTP HARNESS FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
