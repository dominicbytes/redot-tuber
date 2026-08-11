class_name YouTubeLoopbackCallbackServer
extends Node

const MAX_REQUEST_BYTES: int = 16 * 1024
const CALLBACK_PATH: String = "/oauth2/callback"

signal result_received(result: YouTubeOAuthCallbackResult)

var _server: TCPServer = null
var _peer: StreamPeerTCP = null
var _request_bytes: PackedByteArray = PackedByteArray()
var _expected_state: String = ""
var _deadline_msec: int = 0
var _result: YouTubeOAuthCallbackResult = null


func start(expected_state: String, timeout_msec: int = 180000) -> YouTubeApiError:
	stop()
	if expected_state.is_empty():
		return YouTubeApiError.invalid("OAuth callback state is required")
	if timeout_msec < 1000 or timeout_msec > 900000:
		return YouTubeApiError.invalid("OAuth callback timeout is outside the allowed range")
	_server = TCPServer.new()
	var listen_error: Error = _server.listen(0, "127.0.0.1")
	if listen_error != OK:
		_server = null
		return YouTubeApiError.from_transport(listen_error, "Unable to bind the OAuth loopback callback")
	_expected_state = expected_state
	_deadline_msec = Time.get_ticks_msec() + timeout_msec
	_result = null
	_request_bytes.clear()
	set_process(true)
	return null


func stop() -> void:
	set_process(false)
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	if _server != null:
		_server.stop()
	_server = null
	_request_bytes.clear()


func port() -> int:
	return _server.get_local_port() if _server != null else 0


func redirect_uri() -> String:
	return "http://127.0.0.1:%d%s" % [port(), CALLBACK_PATH] if port() > 0 else ""


func wait_for_result() -> YouTubeOAuthCallbackResult:
	if _result == null:
		await result_received
	return _result


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if _server == null or _result != null:
		return
	if Time.get_ticks_msec() >= _deadline_msec:
		_complete_error("timeout", "YouTube authorization timed out")
		return
	if _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var available: int = _peer.get_available_bytes()
	if available <= 0:
		return
	_request_bytes.append_array(_peer.get_data(available)[1])
	if _request_bytes.size() > MAX_REQUEST_BYTES:
		_send_page(413, "Authorization callback was too large.")
		_complete_error("invalid_callback", "OAuth callback exceeded the request limit")
		return
	var request_text: String = _request_bytes.get_string_from_utf8()
	if not request_text.contains("\r\n\r\n"):
		return
	_handle_request(request_text)


func _handle_request(request_text: String) -> void:
	var request_line: String = request_text.split("\r\n", false)[0]
	var pieces: PackedStringArray = request_line.split(" ", false)
	if pieces.size() < 3 or pieces[0] != "GET":
		_send_page(405, "Only the authorization callback is accepted.")
		_complete_error("invalid_callback", "OAuth callback used an unsupported request method")
		return
	var target: String = pieces[1]
	var target_parts: PackedStringArray = target.split("?", true, 1)
	if target_parts[0] != CALLBACK_PATH:
		_send_page(404, "This callback path is not available.")
		_complete_error("invalid_callback", "OAuth callback path did not match")
		return
	var query: Dictionary = _parse_query(target_parts[1] if target_parts.size() > 1 else "")
	var returned_state: String = String(query.get("state", ""))
	if not _constant_time_equals(_expected_state, returned_state):
		_send_page(400, "Authorization could not be verified. Return to the game and try again.")
		_complete_error("state_mismatch", "OAuth callback state did not match")
		return
	var oauth_error: String = String(query.get("error", ""))
	if not oauth_error.is_empty():
		_send_page(400, "Authorization was not granted. You may close this window.")
		_complete_error("authorization_denied", "YouTube authorization was denied")
		return
	var code: String = String(query.get("code", ""))
	if code.is_empty() or code.length() > 4096:
		_send_page(400, "Authorization returned an invalid code.")
		_complete_error("invalid_callback", "OAuth callback did not contain a valid authorization code")
		return
	_send_page(200, "Authorization complete. You may close this window and return to the game.")
	var result: YouTubeOAuthCallbackResult = YouTubeOAuthCallbackResult.new()
	result.code = code
	_complete(result)


func _parse_query(source: String) -> Dictionary:
	var result: Dictionary = {}
	for pair: String in source.split("&", false):
		var parts: PackedStringArray = pair.split("=", true, 1)
		var key: String = parts[0].uri_decode()
		var value: String = parts[1].replace("+", " ").uri_decode() if parts.size() > 1 else ""
		if not key.is_empty() and not result.has(key):
			result[key] = value
	return result


func _constant_time_equals(expected: String, actual: String) -> bool:
	var expected_bytes: PackedByteArray = expected.to_utf8_buffer()
	var actual_bytes: PackedByteArray = actual.to_utf8_buffer()
	var difference: int = expected_bytes.size() ^ actual_bytes.size()
	var maximum: int = maxi(expected_bytes.size(), actual_bytes.size())
	for index: int in maximum:
		var left: int = expected_bytes[index] if index < expected_bytes.size() else 0
		var right: int = actual_bytes[index] if index < actual_bytes.size() else 0
		difference |= left ^ right
	return difference == 0


func _send_page(status: int, message: String) -> void:
	if _peer == null or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var reason: String = "OK" if status == 200 else "Bad Request"
	var body: PackedByteArray = (
		"<!doctype html><meta charset=\"utf-8\"><title>Redot Tuber</title>" +
		"<p>" + message.xml_escape() + "</p>"
	).to_utf8_buffer()
	var headers: String = (
		"HTTP/1.1 %d %s\r\n" % [status, reason] +
		"Content-Type: text/html; charset=utf-8\r\n" +
		"Content-Length: %d\r\n" % body.size() +
		"Cache-Control: no-store\r\n" +
		"Pragma: no-cache\r\n" +
		"Connection: close\r\n\r\n"
	)
	_peer.put_data(headers.to_utf8_buffer())
	_peer.put_data(body)
	_peer.disconnect_from_host()


func _complete_error(category: String, message: String) -> void:
	var result: YouTubeOAuthCallbackResult = YouTubeOAuthCallbackResult.new()
	result.error = YouTubeApiError.custom(category, message)
	_complete(result)


func _complete(result: YouTubeOAuthCallbackResult) -> void:
	if _result != null:
		return
	_result = result
	_expected_state = ""
	stop()
	result_received.emit(result)
