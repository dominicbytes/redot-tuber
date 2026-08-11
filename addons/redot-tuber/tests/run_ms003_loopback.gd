extends SceneTree

const ServerClass = preload("res://addons/redot-tuber/auth/youtube_loopback_callback_server.gd")
const MAX_FRAMES: int = 300

var _checks: int = 0
var _failures: PackedStringArray = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	await _test_success()
	await _test_state_mismatch()
	await _test_denial()
	_finish()


func _test_success() -> void:
	var server: Node = ServerClass.new()
	root.add_child(server)
	var start_error: Variant = server.start("expected-state", 2000)
	_check(start_error == null, "callback server starts")
	_check(server.redirect_uri().begins_with("http://127.0.0.1:"), "callback binds an IPv4 loopback URI")
	_check(server.redirect_uri().ends_with("/oauth2/callback"), "callback uses fixed local path")
	var exchange: Dictionary = await _send_callback(server, "/oauth2/callback?code=fixture-code&state=expected-state")
	_check(int(exchange.get("status", 0)) == 200, "valid callback receives success page")
	var result: Variant = await server.wait_for_result()
	_check(result.error == null and result.code == "fixture-code", "valid state releases authorization code")
	server.free()


func _test_state_mismatch() -> void:
	var server: Node = ServerClass.new()
	root.add_child(server)
	_check(server.start("expected-state", 2000) == null, "mismatch server starts")
	var exchange: Dictionary = await _send_callback(server, "/oauth2/callback?code=must-not-escape&state=wrong-state")
	_check(int(exchange.get("status", 0)) == 400, "state mismatch receives error page")
	var result: Variant = await server.wait_for_result()
	_check(result.error != null and result.error.category == "state_mismatch", "state mismatch is typed")
	_check(result.code.is_empty(), "state mismatch never releases authorization code")
	server.free()


func _test_denial() -> void:
	var server: Node = ServerClass.new()
	root.add_child(server)
	_check(server.start("expected-state", 2000) == null, "denial server starts")
	var exchange: Dictionary = await _send_callback(server, "/oauth2/callback?error=access_denied&state=expected-state")
	_check(int(exchange.get("status", 0)) == 400, "OAuth denial receives a safe terminal page")
	var result: Variant = await server.wait_for_result()
	_check(result.error != null and result.error.category == "authorization_denied", "OAuth denial is typed")
	server.free()


func _send_callback(server: Node, path: String) -> Dictionary:
	var client: HTTPClient = HTTPClient.new()
	var connect_error: Error = client.connect_to_host("127.0.0.1", server.port())
	if connect_error != OK:
		return {"error": error_string(connect_error)}
	var requested: bool = false
	var status: int = 0
	var body: PackedByteArray = PackedByteArray()
	for _frame: int in MAX_FRAMES:
		var poll_error: Error = client.poll()
		if poll_error != OK:
			break
		if client.get_status() == HTTPClient.STATUS_CONNECTED and not requested:
			var request_error: Error = client.request(HTTPClient.METHOD_GET, path, PackedStringArray(["Host: 127.0.0.1"]))
			if request_error != OK:
				break
			requested = true
		if client.has_response():
			status = client.get_response_code()
		if client.get_status() == HTTPClient.STATUS_BODY:
			body.append_array(client.read_response_body_chunk())
		if requested and status != 0 and client.get_status() in [HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTED]:
			break
		await process_frame
	client.close()
	return {"status": status, "body": body.get_string_from_utf8()}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-003 LOOPBACK PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-003 LOOPBACK FAIL: %s" % failure)
	print("MS-003 LOOPBACK FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
