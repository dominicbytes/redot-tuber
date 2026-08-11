class_name YouTubeLiveChatStreamSource
extends Node

const FramerClass = preload("res://addons/redot-tuber/transport/json_stream_framer.gd")

signal page_received(page: YouTubeLiveChatPage)
signal reconnecting(attempt: int, delay_msec: int, page_token: String)
signal error_occurred(error: YouTubeApiError)
signal stopped(reason: String)

@export_range(65536, 8388608, 65536) var max_partial_frame_bytes: int = 1024 * 1024
@export_range(4096, 1048576, 4096) var read_chunk_bytes: int = 65536
@export_range(1000, 300000, 1000) var idle_timeout_msec: int = 90000
@export_range(0, 10, 1) var max_reconnect_attempts: int = 3
@export_range(10, 60000, 10) var reconnect_base_delay_msec: int = 500
@export_range(10, 120000, 10) var reconnect_max_delay_msec: int = 10000

var _api: YouTubeApiClient = null
var _chat: YouTubeLiveChatService = null
var _gate: YouTubeCapabilityGate = null
var _client: HTTPClient = null
var _framer: YouTubeJsonStreamFramer = null
var _cancellation: YouTubeCancellationToken = null
var _live_chat_id: String = ""
var _page_token: String = ""
var _host: String = ""
var _port: int = 0
var _request_path: String = ""
var _secure: bool = false
var _active: bool = false
var _request_sent: bool = false
var _request_starting: bool = false
var _response_seen: bool = false
var _reconnect_attempt: int = 0
var _reconnect_at_msec: int = 0
var _last_receive_msec: int = 0


func configure(api_client: YouTubeApiClient, chat_service: YouTubeLiveChatService, capability_gate: YouTubeCapabilityGate = null) -> void:
	_api = api_client
	_chat = chat_service
	_gate = capability_gate


func start(
	live_chat_id: String,
	page_token: String = "",
	cancellation: YouTubeCancellationToken = null
) -> YouTubeApiError:
	if _active:
		return YouTubeApiError.invalid("The YouTube live chat stream source is already active")
	if _api == null or _chat == null:
		return YouTubeApiError.custom("stream_unconfigured", "Configure the YouTube live chat stream source before starting")
	if live_chat_id.strip_edges().is_empty():
		return YouTubeApiError.invalid("Live chat ID is required")
	if _gate != null:
		var gate_error: YouTubeApiError = _gate.require_method("liveChatMessages.streamList")
		if gate_error != null:
			return gate_error
	_live_chat_id = live_chat_id
	_page_token = page_token
	_cancellation = cancellation if cancellation != null else YouTubeCancellationToken.new()
	if not _cancellation.cancelled.is_connected(_on_cancelled):
		_cancellation.cancelled.connect(_on_cancelled, CONNECT_ONE_SHOT)
	_active = true
	_reconnect_attempt = 0
	_framer = FramerClass.new(max_partial_frame_bytes)
	var url_error: YouTubeApiError = _prepare_url()
	if url_error != null:
		_active = false
		return url_error
	set_process(true)
	_open_connection()
	return null


func stop(reason: String = "stopped") -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	_close_client()
	if _framer != null:
		_framer.reset()
	stopped.emit(reason)


func is_active() -> bool:
	return _active


func next_page_token() -> String:
	return _page_token


func _process(_delta: float) -> void:
	if not _active:
		return
	if _cancellation != null and _cancellation.is_cancelled():
		stop(_cancellation.reason())
		return
	var now: int = Time.get_ticks_msec()
	if _client == null:
		if now >= _reconnect_at_msec:
			_open_connection()
		return
	var poll_error: Error = _client.poll()
	if poll_error != OK:
		_schedule_reconnect("HTTPClient poll failed: %s" % error_string(poll_error))
		return
	var status: int = _client.get_status()
	if status == HTTPClient.STATUS_CONNECTED and not _request_sent and not _request_starting:
		_send_request()
		return
	if _client != null and _client.has_response() and not _response_seen:
		_response_seen = true
		var status_code: int = _client.get_response_code()
		if status_code < 200 or status_code >= 300:
			var api_error: YouTubeApiError = YouTubeApiError.from_http(status_code, {})
			if api_error.is_retryable:
				_schedule_reconnect(api_error.message)
			else:
				error_occurred.emit(api_error)
				stop("stream request rejected")
			return
	if _client != null and _client.get_status() == HTTPClient.STATUS_BODY:
		_read_available_body()
		if not _active:
			return
		now = Time.get_ticks_msec()
		if now - _last_receive_msec > idle_timeout_msec:
			_schedule_reconnect("YouTube stream was idle beyond the configured timeout")
		return
	if _request_sent and status == HTTPClient.STATUS_DISCONNECTED:
		_schedule_reconnect("YouTube stream connection closed")


func _send_request() -> void:
	_request_starting = true
	var authorization_error: YouTubeApiError = await _api.prepare_authorized_request()
	if not _active or _client == null:
		_request_starting = false
		return
	if authorization_error != null:
		_request_starting = false
		error_occurred.emit(authorization_error)
		stop("authorization unavailable")
		return
	var quota_error: YouTubeApiError = _api.begin_external_request("liveChatMessages.streamList")
	if quota_error != null:
		_request_starting = false
		error_occurred.emit(quota_error)
		stop("quota budget unavailable")
		return
	var headers: PackedStringArray = _api.request_headers()
	headers.append("Accept-Encoding: identity")
	headers.append("Cache-Control: no-cache")
	var request_error: Error = _client.request(HTTPClient.METHOD_GET, _request_path, headers)
	_request_starting = false
	if request_error != OK:
		_schedule_reconnect("Unable to start YouTube stream request: %s" % error_string(request_error))
		return
	_request_sent = true
	_last_receive_msec = Time.get_ticks_msec()


func _read_available_body() -> void:
	for _read_index: int in 8:
		var chunk: PackedByteArray = _client.read_response_body_chunk()
		if chunk.is_empty():
			break
		_last_receive_msec = Time.get_ticks_msec()
		var frames: Array[Dictionary] = _framer.push_chunk(chunk)
		if not _framer.last_error().is_empty():
			var framing_error: YouTubeApiError = YouTubeApiError.custom("stream_framing", _framer.last_error())
			error_occurred.emit(framing_error)
			stop("stream framing failed")
			return
		for payload: Dictionary in frames:
			var page: YouTubeLiveChatPage = _chat.parse_page(payload)
			if not page.next_page_token.is_empty():
				_page_token = page.next_page_token
			_reconnect_attempt = 0
			page_received.emit(page)
			if page.is_terminal():
				stop("chat ended")
				return


func _prepare_url() -> YouTubeApiError:
	var url: String = _api.build_url("/liveChat/messages", {
		"liveChatId": _live_chat_id,
		"part": "id,snippet,authorDetails",
		"maxResults": 2000,
		"pageToken": _page_token,
	})
	_secure = url.begins_with("https://")
	var scheme_marker: int = url.find("://")
	if scheme_marker < 0:
		return YouTubeApiError.invalid("YouTube stream URL has no scheme")
	var remainder: String = url.substr(scheme_marker + 3)
	var slash_index: int = remainder.find("/")
	var authority: String = remainder if slash_index < 0 else remainder.substr(0, slash_index)
	_request_path = "/" if slash_index < 0 else remainder.substr(slash_index)
	_host = authority
	_port = 443 if _secure else 80
	var colon_index: int = authority.rfind(":")
	if colon_index > 0:
		_host = authority.substr(0, colon_index)
		_port = int(authority.substr(colon_index + 1))
	if _host.is_empty() or _port <= 0:
		return YouTubeApiError.invalid("YouTube stream URL has an invalid host or port")
	return null


func _open_connection() -> void:
	_close_client()
	if not _active:
		return
	var url_error: YouTubeApiError = _prepare_url()
	if url_error != null:
		error_occurred.emit(url_error)
		stop("stream URL invalid")
		return
	_client = HTTPClient.new()
	_client.set_read_chunk_size(read_chunk_bytes)
	_request_sent = false
	_request_starting = false
	_response_seen = false
	_framer.reset()
	var connect_error: Error
	if _secure:
		connect_error = _client.connect_to_host(_host, _port, TLSOptions.client())
	else:
		connect_error = _client.connect_to_host(_host, _port)
	if connect_error != OK:
		_schedule_reconnect("Unable to connect to YouTube stream: %s" % error_string(connect_error))


func _schedule_reconnect(reason: String) -> void:
	_close_client()
	if not _active:
		return
	_reconnect_attempt += 1
	if _reconnect_attempt > max_reconnect_attempts:
		var error: YouTubeApiError = YouTubeApiError.custom("stream_unavailable", "%s after %d reconnect attempts" % [reason, max_reconnect_attempts], true)
		error_occurred.emit(error)
		stop("stream unavailable")
		return
	var delay: int = mini(reconnect_max_delay_msec, reconnect_base_delay_msec * (1 << (_reconnect_attempt - 1)))
	_reconnect_at_msec = Time.get_ticks_msec() + delay
	reconnecting.emit(_reconnect_attempt, delay, _page_token)


func _close_client() -> void:
	if _client != null:
		_client.close()
	_client = null


func _on_cancelled(reason: String) -> void:
	stop(reason)


func _exit_tree() -> void:
	stop("stream source freed")
