class_name YouTubeHttpTransport
extends Node

const TicketClass = preload("res://addons/redot-tuber/transport/youtube_http_ticket.gd")
const ResponseClass = preload("res://addons/redot-tuber/transport/youtube_http_response.gd")
const ApiErrorClass = preload("res://addons/redot-tuber/models/youtube_api_error.gd")
const RedactorClass = preload("res://addons/redot-tuber/diagnostics/youtube_redactor.gd")

signal request_started(ticket_id: int, redacted_url: String, attempt: int)
signal request_retried(ticket_id: int, attempt: int, delay_msec: int)
signal diagnostic(message: String)
signal became_idle()

@export_range(1, 16, 1) var max_concurrent_requests: int = 4
@export_range(0, 5, 1) var max_retries: int = 2
@export_range(0.1, 120.0, 0.1) var timeout_seconds: float = 20.0
@export_range(1024, 67108864, 1024) var response_body_limit_bytes: int = 8 * 1024 * 1024
@export_range(1024, 16777216, 1024) var request_body_limit_bytes: int = 2 * 1024 * 1024
@export_range(1, 512, 1) var max_queued_requests: int = 64
@export_range(0, 60000, 10) var retry_base_delay_msec: int = 500

var _next_ticket_id: int = 1
var _pending: Array[Dictionary] = []
var _active: Dictionary = {}
var _redactor: YouTubeRedactor = RedactorClass.new()


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	_pump()


func request(
	url: String,
	headers: PackedStringArray = PackedStringArray(),
	method: int = HTTPClient.METHOD_GET,
	body: PackedByteArray = PackedByteArray(),
	cancellation: YouTubeCancellationToken = null
) -> YouTubeHttpTicket:
	var ticket: YouTubeHttpTicket = TicketClass.new()
	ticket.id = _next_ticket_id
	_next_ticket_id += 1
	ticket.redacted_url = _redactor.redact_text(url)

	var validation_error: String = _validate_request(url, body)
	if not validation_error.is_empty():
		_complete_immediate_error(ticket, ERR_INVALID_PARAMETER, validation_error)
		return ticket
	if _pending.size() + _active.size() >= max_queued_requests + max_concurrent_requests:
		_complete_immediate_error(ticket, ERR_BUSY, "YouTube request queue is full")
		return ticket

	var item: Dictionary = {
		"ticket": ticket,
		"url": url,
		"headers": headers,
		"method": method,
		"body": body,
		"cancellation": cancellation,
		"attempt": 0,
		"ready_at_msec": 0,
		"started_at_msec": 0,
		"http": null,
	}
	_pending.append(item)
	if cancellation != null:
		cancellation.cancelled.connect(_on_cancel_requested.bind(ticket.id), CONNECT_ONE_SHOT)
		if cancellation.is_cancelled():
			_on_cancel_requested(cancellation.reason(), ticket.id)
	_pump()
	return ticket


func cancel_all(reason: String = "transport stopped") -> void:
	var ids: Array[int] = []
	for item: Dictionary in _pending:
		ids.append((item.ticket as YouTubeHttpTicket).id)
	for ticket_id: Variant in _active:
		ids.append(int(ticket_id))
	for ticket_id: int in ids:
		_on_cancel_requested(reason, ticket_id)


func queued_count() -> int:
	return _pending.size()


func active_count() -> int:
	return _active.size()


func _pump() -> void:
	var now: int = Time.get_ticks_msec()
	var index: int = 0
	while _active.size() < max_concurrent_requests and index < _pending.size():
		var item: Dictionary = _pending[index]
		if int(item.ready_at_msec) > now:
			index += 1
			continue
		_pending.remove_at(index)
		var ticket: YouTubeHttpTicket = item.ticket
		if ticket.is_completed:
			continue
		_start_item(item)
	set_process(not _pending.is_empty())
	_emit_idle_if_needed()


func _start_item(item: Dictionary) -> void:
	var ticket: YouTubeHttpTicket = item.ticket
	item.attempt = int(item.attempt) + 1
	item.started_at_msec = Time.get_ticks_msec()
	var http: HTTPRequest = HTTPRequest.new()
	http.name = "YouTubeHttpRequest%d" % ticket.id
	http.timeout = timeout_seconds
	http.body_size_limit = response_body_limit_bytes
	http.accept_gzip = true
	# One non-threaded HTTPRequest node per active slot keeps completion on the
	# scene thread; bounded concurrency still permits parallel in-flight I/O.
	http.use_threads = false
	add_child(http)
	item.http = http
	_active[ticket.id] = item
	http.request_completed.connect(_on_request_completed.bind(ticket.id), CONNECT_ONE_SHOT)
	request_started.emit(ticket.id, ticket.redacted_url, int(item.attempt))
	var start_error: Error = http.request_raw(item.url, item.headers, int(item.method), item.body)
	if start_error != OK:
		_active.erase(ticket.id)
		http.queue_free()
		var response: YouTubeHttpResponse = ResponseClass.new()
		response.request_result = HTTPRequest.RESULT_CANT_CONNECT
		response.attempt_count = int(item.attempt)
		response.error = ApiErrorClass.from_transport(start_error, "Unable to start YouTube request: %s" % error_string(start_error))
		_finish_or_retry(item, response)


func _on_request_completed(result: int, status_code: int, headers: PackedStringArray, body: PackedByteArray, ticket_id: int) -> void:
	if not _active.has(ticket_id):
		return
	var item: Dictionary = _active[ticket_id]
	_active.erase(ticket_id)
	var http: HTTPRequest = item.http
	if is_instance_valid(http):
		http.queue_free()
	var ticket: YouTubeHttpTicket = item.ticket
	if ticket.is_completed:
		_pump()
		return

	var response: YouTubeHttpResponse = ResponseClass.new()
	response.request_result = result
	response.status_code = status_code
	response.headers = headers
	response.body = body
	response.attempt_count = int(item.attempt)
	response.elapsed_msec = Time.get_ticks_msec() - int(item.started_at_msec)
	if not body.is_empty() and _should_parse_json(headers, body):
		response.parsed_json = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS:
		response.error = ApiErrorClass.from_transport(result, "YouTube transport failed (result %d)" % result)
	elif status_code < 200 or status_code >= 300:
		response.error = ApiErrorClass.from_http(status_code, response.parsed_json)
	_finish_or_retry(item, response)


func _finish_or_retry(item: Dictionary, response: YouTubeHttpResponse) -> void:
	var ticket: YouTubeHttpTicket = item.ticket
	var cancellation: YouTubeCancellationToken = item.cancellation
	var cancelled: bool = ticket.is_cancelled or (cancellation != null and cancellation.is_cancelled())
	if not cancelled and _should_retry(response) and int(item.attempt) <= max_retries:
		var delay_msec: int = retry_base_delay_msec * (1 << (int(item.attempt) - 1))
		item.ready_at_msec = Time.get_ticks_msec() + delay_msec
		item.http = null
		_pending.append(item)
		request_retried.emit(ticket.id, int(item.attempt) + 1, delay_msec)
		set_process(true)
	else:
		ticket._complete(response)
	_pump()


func _should_retry(response: YouTubeHttpResponse) -> bool:
	if response.request_result != HTTPRequest.RESULT_SUCCESS:
		return true
	return response.status_code in [408, 429, 500, 502, 503, 504]


func _on_cancel_requested(reason: String, ticket_id: int) -> void:
	for index: int in range(_pending.size() - 1, -1, -1):
		var pending_item: Dictionary = _pending[index]
		var pending_ticket: YouTubeHttpTicket = pending_item.ticket
		if pending_ticket.id == ticket_id:
			_pending.remove_at(index)
			_complete_cancelled(pending_ticket, reason, int(pending_item.attempt))
			_pump()
			return
	if not _active.has(ticket_id):
		return
	var item: Dictionary = _active[ticket_id]
	_active.erase(ticket_id)
	var http: HTTPRequest = item.http
	if is_instance_valid(http):
		http.cancel_request()
		http.queue_free()
	_complete_cancelled(item.ticket, reason, int(item.attempt))
	_pump()


func _complete_cancelled(ticket: YouTubeHttpTicket, reason: String, attempt_count: int) -> void:
	ticket._mark_cancelled(reason)
	var response: YouTubeHttpResponse = ResponseClass.new()
	response.request_result = HTTPRequest.RESULT_REQUEST_FAILED
	response.attempt_count = attempt_count
	response.error = ApiErrorClass.from_transport(ERR_SKIP, "YouTube request cancelled")
	ticket._complete(response)


func _complete_immediate_error(ticket: YouTubeHttpTicket, code: int, message: String) -> void:
	var response: YouTubeHttpResponse = ResponseClass.new()
	response.request_result = HTTPRequest.RESULT_REQUEST_FAILED
	response.error = ApiErrorClass.from_transport(code, message)
	ticket._complete(response)


func _validate_request(url: String, body: PackedByteArray) -> String:
	if url.is_empty():
		return "Request URL is empty"
	var secure: bool = url.begins_with("https://")
	var loopback: bool = url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")
	if not secure and not loopback:
		return "Only HTTPS or local loopback HTTP requests are allowed"
	if body.size() > request_body_limit_bytes:
		return "Request body exceeds the configured limit"
	return ""


func _should_parse_json(headers: PackedStringArray, body: PackedByteArray) -> bool:
	for header: String in headers:
		if header.to_lower().begins_with("content-type:"):
			var content_type: String = header.get_slice(":", 1).strip_edges().to_lower()
			return content_type.contains("application/json") or content_type.contains("+json")
	for byte: int in body:
		if byte in [9, 10, 13, 32]:
			continue
		return byte == 123 or byte == 91
	return false


func _emit_idle_if_needed() -> void:
	if _pending.is_empty() and _active.is_empty():
		set_process(false)
		became_idle.emit()
