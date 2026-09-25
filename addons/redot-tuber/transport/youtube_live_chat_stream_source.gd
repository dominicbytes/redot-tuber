class_name YouTubeLiveChatStreamSource
extends Node
## Native gRPC sidecar. A private stdin request and bounded nonblocking stdout
## frames keep credentials out of process arguments, files, and diagnostics.

const HelperPaths = preload("res://addons/redot-tuber/transport/stream_helper_paths.gd")
const PROTOCOL: String = "RTSL/1"
const MAX_REQUEST_BYTES: int = 16 * 1024
const MAX_FRAMES_PER_TICK: int = 16
const MAX_BYTES_PER_TICK: int = 256 * 1024

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

var helper_path_override: String = ""
var test_loopback_endpoint: String = "" # Editor-only integration fixture.
var _api: YouTubeApiClient = null
var _chat: YouTubeLiveChatService = null
var _gate: YouTubeCapabilityGate = null
var _chat_id: String = ""
var _cursor: String = ""
var _cancellation: YouTubeCancellationToken = null
var _active: bool = false
var _generation: int = 0
var _attempt: int = 0
var _pid: int = -1
var _stdio: FileAccess = null
var _stderr: FileAccess = null
var _buffer: PackedByteArray = PackedByteArray()


func configure(api_client: YouTubeApiClient, chat_service: YouTubeLiveChatService, capability_gate: YouTubeCapabilityGate = null) -> void:
	_api = api_client
	_chat = chat_service
	_gate = capability_gate


func start(live_chat_id: String, page_token: String = "", cancellation: YouTubeCancellationToken = null) -> YouTubeApiError:
	stop("superseded")
	if live_chat_id.is_empty() or _api == null or _chat == null:
		return YouTubeApiError.invalid("A configured live chat is required for streamList")
	if _gate != null:
		var gate_error: YouTubeApiError = _gate.require_method("liveChatMessages.streamList")
		if gate_error != null:
			return gate_error
	var path: String = resolved_helper_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return YouTubeApiError.custom("stream_transport_unavailable", "Native YouTube stream helper is unavailable for this platform")
	if not test_loopback_endpoint.is_empty() and not OS.has_feature("editor"):
		return YouTubeApiError.invalid("Test stream endpoint is editor-only")
	_chat_id = live_chat_id
	_cursor = page_token
	_cancellation = cancellation
	_active = true
	_attempt = 0
	_generation += 1
	set_process(true)
	_connect.call_deferred(_generation)
	return null


func stop(reason: String = "stopped") -> void:
	var was_active: bool = _active
	_active = false
	_generation += 1
	_close_process()
	_chat_id = ""
	_cancellation = null
	set_process(false)
	if was_active:
		stopped.emit(reason)


func is_active() -> bool:
	return _active


func next_page_token() -> String:
	return _cursor


func resolved_helper_path() -> String:
	if not helper_path_override.is_empty():
		return ProjectSettings.globalize_path(helper_path_override) if helper_path_override.begins_with("res://") else helper_path_override
	return HelperPaths.runtime_path(OS.has_feature("editor"), OS.get_name(), Engine.get_architecture_name(), OS.get_executable_path())


func _connect(generation: int) -> void:
	if not _current(generation):
		return
	var auth_error: YouTubeApiError = await _api.prepare_authorized_request()
	if not _current(generation):
		return
	if auth_error != null:
		_fail(auth_error, "authorization failed")
		return
	var quota_error: YouTubeApiError = _api.begin_external_request("liveChatMessages.streamList")
	if quota_error != null:
		_fail(quota_error, "quota exhausted")
		return
	var credential: Dictionary = _api.stream_credential()
	if credential.is_empty():
		_fail(YouTubeApiError.custom("authorization", "A YouTube credential is required"), "authorization failed")
		return
	var request: Dictionary = {
		"protocol": PROTOCOL,
		"auth_kind": credential["auth_kind"],
		"credential": credential["credential"],
		"live_chat_id": _chat_id,
		"page_token": _cursor,
		"idle_timeout_ms": clampi(idle_timeout_msec, 1000, 300000),
	}
	credential.clear()
	var arguments: PackedStringArray = PackedStringArray()
	if not test_loopback_endpoint.is_empty():
		request["endpoint"] = test_loopback_endpoint
		arguments.append("--test-loopback")
	var wire: String = JSON.stringify(request) + "\n"
	request.clear()
	if wire.to_utf8_buffer().size() > MAX_REQUEST_BYTES:
		wire = ""
		_fail(YouTubeApiError.invalid("Stream request exceeds the helper protocol limit"), "stream unavailable")
		return
	var process: Dictionary = OS.execute_with_pipe(resolved_helper_path(), arguments, false)
	_stdio = process.get("stdio", null)
	_stderr = process.get("stderr", null)
	_pid = int(process.get("pid", -1))
	if _stdio == null or _pid <= 0:
		wire = ""
		_fail(YouTubeApiError.custom("stream_transport_unavailable", "Native stream helper could not start"), "stream unavailable")
		return
	_stdio.store_string(wire)
	_stdio.flush()
	wire = ""
	_buffer.clear()


func _process(_delta: float) -> void:
	if not _active:
		return
	if _cancellation != null and _cancellation.is_cancelled():
		stop("cancelled")
		return
	if _stdio == null:
		return
	var available: int = _stdio.get_length()
	var budget: int = MAX_FRAMES_PER_TICK
	var byte_budget: int = MAX_BYTES_PER_TICK
	budget = _drain_buffer(budget)
	if _stdio == null:
		return
	if budget > 0 and _buffer.size() > max_partial_frame_bytes:
		_fail(YouTubeApiError.custom("stream_framing", "Native stream frame exceeded the size limit"), "stream framing failed")
		return
	while available > 0 and budget > 0 and byte_budget > 0 and _active:
		var room: int = max_partial_frame_bytes + 1 - _buffer.size()
		var chunk: PackedByteArray = _stdio.get_buffer(mini(mini(available, read_chunk_bytes), mini(byte_budget, room)))
		if chunk.is_empty():
			break
		byte_budget -= chunk.size()
		_buffer.append_array(chunk)
		budget = _drain_buffer(budget)
		if _stdio == null:
			return
		if budget > 0 and _buffer.size() > max_partial_frame_bytes:
			_fail(YouTubeApiError.custom("stream_framing", "Native stream frame exceeded the size limit"), "stream framing failed")
			return
		available = _stdio.get_length()
	if budget == 0:
		return
	if _pid > 0 and not OS.is_process_running(_pid):
		if _stdio.get_length() == 0:
			if not _buffer.is_empty():
				_fail(YouTubeApiError.custom("stream_framing", "Native stream ended with an incomplete frame"), "stream framing failed")
				return
			_retry_or_stop("unavailable")


func _drain_buffer(budget: int) -> int:
	while budget > 0:
		var end: int = _buffer.find(10)
		if end < 0:
			break
		var line: PackedByteArray = _buffer.slice(0, end)
		_buffer = _buffer.slice(end + 1)
		budget -= 1
		_accept_frame(line)
		if _stdio == null or not _active:
			break
	return budget


func _accept_frame(bytes: PackedByteArray) -> void:
	if bytes.size() > max_partial_frame_bytes:
		_fail(YouTubeApiError.custom("stream_framing", "Native stream frame exceeded the size limit"), "stream framing failed")
		return
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		_fail(YouTubeApiError.custom("stream_framing", "Native stream response was invalid"), "stream framing failed")
		return
	var parsed: Dictionary = parser.data
	if parsed.get("protocol", "") != PROTOCOL:
		_fail(YouTubeApiError.custom("stream_framing", "Native stream response was invalid"), "stream framing failed")
		return
	var frame: Dictionary = parsed
	match String(frame.get("kind", "")):
		"page":
			var payload: Variant = frame.get("page", null)
			if not payload is Dictionary:
				_fail(YouTubeApiError.custom("stream_framing", "Native stream page was invalid"), "stream framing failed")
				return
			var page: YouTubeLiveChatPage = _chat.parse_page(payload)
			if not page.next_page_token.is_empty():
				_cursor = page.next_page_token
			_attempt = 0
			var generation: int = _generation
			page_received.emit(page)
			if not _current(generation):
				return
			if page.is_terminal():
				stop("chat ended")
		"terminal":
			stop("chat ended")
		"eof":
			_retry_or_stop("unavailable")
		"error":
			var code: String = String(frame.get("code", ""))
			if code not in ["canceled", "unknown", "invalid_argument", "deadline_exceeded", "not_found", "already_exists", "permission_denied", "resource_exhausted", "failed_precondition", "aborted", "out_of_range", "unimplemented", "internal", "unavailable", "data_loss", "unauthenticated", "protocol_error", "schema_error", "mapping_error"]:
				code = "unknown"
			if code in ["unauthenticated", "permission_denied", "resource_exhausted", "failed_precondition", "not_found", "invalid_argument", "protocol_error", "schema_error", "mapping_error"]:
				var category: String = {"unauthenticated":"authorization", "permission_denied":"denied", "resource_exhausted":"rate_limited"}.get(code, code)
				var api_error: YouTubeApiError = YouTubeApiError.custom(category, "YouTube streamList failed (%s)" % code)
				var reason: String = String(frame.get("reason", ""))
				if code == "failed_precondition" and reason in ["LIVE_CHAT_DISABLED", "LIVE_CHAT_ENDED"]:
					api_error.reasons.append(reason)
				_fail(api_error, "stream unavailable")
			else:
				_retry_or_stop(code)
		_:
			_fail(YouTubeApiError.custom("stream_framing", "Native stream response type was invalid"), "stream framing failed")


func _retry_or_stop(code: String) -> void:
	_close_process()
	if not _active:
		return
	if _attempt >= max_reconnect_attempts:
		_fail(YouTubeApiError.custom("stream_transport_unavailable", "YouTube streamList stopped after bounded retries (%s)" % code), "stream unavailable")
		return
	_attempt += 1
	var delay: int = mini(reconnect_max_delay_msec, reconnect_base_delay_msec * (1 << mini(_attempt - 1, 10)))
	var generation: int = _generation
	reconnecting.emit(_attempt, delay, _cursor)
	if not _current(generation):
		return
	await get_tree().create_timer(float(delay) / 1000.0).timeout
	if _current(generation):
		_connect(generation)


func _fail(error: YouTubeApiError, reason: String) -> void:
	var generation: int = _generation
	error_occurred.emit(error)
	if _current(generation):
		stop(reason)


func _current(generation: int) -> bool:
	return _active and generation == _generation and (_cancellation == null or not _cancellation.is_cancelled())


func _close_process() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	if _stdio != null:
		_stdio.close()
		_stdio = null
	if _stderr != null:
		_stderr.close()
		_stderr = null
	_buffer.clear()


func _exit_tree() -> void:
	stop("source freed")
