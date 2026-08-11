extends SceneTree

const AuthManagerClass = preload("res://addons/redot-tuber/auth/youtube_auth_manager.gd")
const ConfigClass = preload("res://addons/redot-tuber/auth/youtube_oauth_config.gd")
const TransportClass = preload("res://addons/redot-tuber/transport/youtube_http_transport.gd")
const CredentialResultClass = preload("res://addons/redot-tuber/models/youtube_credential_result.gd")
const DescriptorStoreClass = preload("res://addons/redot-tuber/auth/youtube_session_descriptor_store.gd")
const TEST_DESCRIPTOR_DIR: String = "res://.test-output/oauth-harness-sessions"
const MAX_FRAMES: int = 600

var _checks: int = 0
var _failures: PackedStringArray = []
var _server: TCPServer = null
var _peers: Array[Dictionary] = []
var _requests: Array[Dictionary] = []


class FakeCredentialProvider extends RefCounted:
	var values: Dictionary = {}

	func store(target: String, secret: String, _cancellation: Variant = null) -> Variant:
		values[target] = secret
		return _result("ok")

	func read(target: String, _cancellation: Variant = null) -> Variant:
		if not values.has(target):
			return _result("not_found")
		var result: Variant = _result("ok")
		result.secret = String(values[target])
		return result

	func delete(target: String, _cancellation: Variant = null) -> Variant:
		if not values.has(target):
			return _result("not_found")
		values.erase(target)
		return _result("ok")

	func _result(status: String) -> Variant:
		var result: Variant = CredentialResultClass.new()
		result.status = status
		return result


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	_server = TCPServer.new()
	var listen_error: Error = _server.listen(0, "127.0.0.1")
	_check(listen_error == OK, "OAuth harness binds loopback server")
	if listen_error != OK:
		_finish()
		return
	var provider: FakeCredentialProvider = FakeCredentialProvider.new()
	var store: Variant = DescriptorStoreClass.new(TEST_DESCRIPTOR_DIR)
	store.delete_descriptor("primary")
	var config: Variant = _make_config()

	var first: Node = _make_manager(config, provider, store, "primary")
	var request: Variant = first.begin_authorization(false, "http://127.0.0.1:49152/oauth2/callback")
	_check(request.error == null, "manager prepares authorization")
	first.complete_authorization("fixture-code")
	await _drive_until(func() -> bool: return first.state in ["connected", "configured"])
	_check(first.state == "connected", "authorization code exchange connects channel")
	_check(first.channel != null and first.channel.id == "fixture-channel", "connected account resolves its YouTube channel")
	_check(first.access_token() == "access-one", "access token remains available only in manager memory")
	var target: String = config.credential_target("primary")
	_check(provider.values.has(target), "refresh token is persisted through credential provider")
	var descriptor_path: String = store.path_for_slot("primary")
	var descriptor_text: String = FileAccess.get_file_as_string(descriptor_path)
	_check(descriptor_text.contains("fixture-channel"), "non-secret descriptor records channel identity")
	_check(not descriptor_text.contains(String(provider.values[target])) and not descriptor_text.contains("access-one"), "descriptor excludes access and refresh tokens")
	var exchange_request: Dictionary = _find_request("/token", "grant_type=authorization_code")
	_check(not exchange_request.is_empty(), "authorization-code token request reaches endpoint")
	_check(String(exchange_request.get("body", "")).contains("code_verifier="), "token exchange sends PKCE verifier")
	_check(not String(exchange_request.get("body", "")).contains("client_secret"), "token exchange has no client secret")
	first.free()
	await process_frame

	var restored: Node = _make_manager(config, provider, store, "primary")
	restored.restore()
	await _drive_until(func() -> bool: return restored.state in ["connected", "configured"])
	_check(restored.state == "connected", "persisted session restores after manager recreation")
	_check(restored.access_token() == "access-two", "restore refreshes to a new memory-only access token")
	_check(String(provider.values.get(target, "")) == "refresh-two", "refresh-token rotation replaces vault value")
	var refresh_request: Dictionary = _find_request("/token", "grant_type=refresh_token")
	_check(not refresh_request.is_empty(), "restore uses refresh-token grant")
	var channel_request: Dictionary = _find_request("/youtube/v3/channels", "")
	_check(String(channel_request.get("headers", "")).contains("Authorization: Bearer"), "authorized channel request uses bearer header")

	restored.revoke_and_disconnect()
	await _drive_until(func() -> bool: return restored.state == "disconnected")
	_check(restored.state == "disconnected", "revoke transitions client to disconnected")
	_check(not provider.values.has(target), "disconnect deletes vault credential")
	_check(not FileAccess.file_exists(descriptor_path), "disconnect deletes non-secret descriptor")
	_check(not _find_request("/revoke", "token=").is_empty(), "disconnect calls OAuth revocation endpoint")
	restored.free()
	_close_server()
	_finish()


func _make_config() -> Variant:
	var config: Variant = ConfigClass.new()
	var base: String = "http://127.0.0.1:%d" % _server.get_local_port()
	config.client_id = "fixture.apps.googleusercontent.com"
	config.application_id = "com.example.oauth-harness"
	config.publisher_id = "fixture-publisher"
	config.authorization_endpoint = base + "/authorize"
	config.token_endpoint = base + "/token"
	config.revocation_endpoint = base + "/revoke"
	config.youtube_api_base_url = base + "/youtube/v3"
	return config


func _make_manager(config: Variant, provider: FakeCredentialProvider, store: Variant, slot: String) -> Node:
	var manager: Node = AuthManagerClass.new()
	root.add_child(manager)
	var transport: Node = TransportClass.new()
	transport.max_retries = 0
	transport.timeout_seconds = 2.0
	manager.add_child(transport)
	var error: Variant = manager.configure(config, PackedStringArray(["channel.read", "chat.read"]), slot, transport, provider, store)
	_check(error == null, "auth manager configures isolated slot %s" % slot)
	return manager


func _drive_until(predicate: Callable) -> void:
	for _frame: int in MAX_FRAMES:
		_service_server()
		if predicate.call():
			return
		await process_frame
	_failures.append("timed out waiting for OAuth operation")


func _service_server() -> void:
	while _server != null and _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		_peers.append({"peer": peer, "wire": PackedByteArray(), "responded": false})
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
			var wire_bytes: PackedByteArray = item.wire
			wire_bytes.append_array(peer.get_data(available)[1])
			item.wire = wire_bytes
		var wire_text: String = (item.wire as PackedByteArray).get_string_from_utf8()
		var header_end: int = wire_text.find("\r\n\r\n")
		if header_end < 0:
			continue
		var content_length: int = _content_length(wire_text.substr(0, header_end))
		if wire_text.length() < header_end + 4 + content_length:
			continue
		var request: Dictionary = _parse_request(wire_text, header_end, content_length)
		_requests.append(request)
		_respond(peer, request)
		item.responded = true


func _parse_request(wire: String, header_end: int, content_length: int) -> Dictionary:
	var header_text: String = wire.substr(0, header_end)
	var first_line: String = header_text.split("\r\n", false)[0]
	var parts: PackedStringArray = first_line.split(" ", false)
	var target: String = parts[1] if parts.size() >= 2 else "/invalid"
	return {
		"path": target.split("?", true)[0],
		"headers": header_text,
		"body": wire.substr(header_end + 4, content_length),
	}


func _content_length(headers: String) -> int:
	for line: String in headers.split("\r\n", false):
		if line.to_lower().begins_with("content-length:"):
			return int(line.get_slice(":", 1).strip_edges())
	return 0


func _respond(peer: StreamPeerTCP, request: Dictionary) -> void:
	var path: String = request.path
	var body: String = String(request.body)
	if path == "/token" and body.contains("grant_type=authorization_code"):
		_send_json(peer, 200, {"access_token": "access-one", "refresh_token": "refresh-one", "expires_in": 3600, "token_type": "Bearer", "scope": "https://www.googleapis.com/auth/youtube.readonly"})
	elif path == "/token" and body.contains("grant_type=refresh_token"):
		_send_json(peer, 200, {"access_token": "access-two", "refresh_token": "refresh-two", "expires_in": 3600, "token_type": "Bearer", "scope": "https://www.googleapis.com/auth/youtube.readonly"})
	elif path == "/youtube/v3/channels":
		_send_json(peer, 200, {"items": [{"id": "fixture-channel", "snippet": {"title": "Fixture Creator", "customUrl": "@fixture", "thumbnails": {"default": {"url": "https://example.invalid/avatar.png"}}}}]})
	elif path == "/revoke":
		_send_json(peer, 200, {})
	else:
		_send_json(peer, 400, {"error": "invalid_request", "error_description": "fixture rejection"})


func _send_json(peer: StreamPeerTCP, status: int, payload: Dictionary) -> void:
	var body: PackedByteArray = JSON.stringify(payload).to_utf8_buffer()
	var reason: String = "OK" if status == 200 else "Bad Request"
	var headers: String = (
		"HTTP/1.1 %d %s\r\n" % [status, reason] +
		"Content-Type: application/json\r\n" +
		"Content-Length: %d\r\n" % body.size() +
		"Connection: close\r\n\r\n"
	)
	peer.put_data(headers.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()


func _find_request(path: String, body_fragment: String) -> Dictionary:
	for request: Dictionary in _requests:
		if String(request.get("path", "")) == path and (body_fragment.is_empty() or String(request.get("body", "")).contains(body_fragment)):
			return request
	return {}


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
		print("MS-003 OAUTH HARNESS PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-003 OAUTH HARNESS FAIL: %s" % failure)
	print("MS-003 OAUTH HARNESS FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
