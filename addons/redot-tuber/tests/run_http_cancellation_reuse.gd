extends SceneTree

var _checks: int = 0
var _failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var transport: YouTubeHttpTransport = YouTubeHttpTransport.new()
	transport.max_retries = 0
	transport.timeout_seconds = 2.0
	root.add_child(transport)
	var token: YouTubeCancellationToken = YouTubeCancellationToken.new()
	for index: int in 3:
		var ticket: YouTubeHttpTicket = _request(transport, "http://127.0.0.1:9/x", token)
		await _wait_for_ticket(ticket)
		_check(ticket.is_completed and not ticket.is_cancelled, "sequential request %d finishes" % index)
		_check(token.cancelled.get_connections().is_empty(), "sequential request %d disconnects cancellation handler" % index)
	var server: TCPServer = TCPServer.new()
	_check(server.listen(0, "127.0.0.1") == OK, "hanging endpoint binds")
	var url: String = "http://127.0.0.1:%d/hang" % server.get_local_port()
	var current: YouTubeHttpTicket = _request(transport, url, token)
	_check(not current.is_completed and token.cancelled.get_connections().size() == 1, "reused token attaches to current request")
	token.cancel("cancel current")
	_check(current.is_completed and current.is_cancelled and current.cancellation_reason == "cancel current", "reused token cancels current request")
	_check(token.cancelled.get_connections().is_empty() and transport.active_count() == 0, "active cancellation releases handler and slot")
	var already_cancelled: YouTubeHttpTicket = _request(transport, url, token)
	_check(already_cancelled.is_completed and already_cancelled.is_cancelled, "already-cancelled token completes immediately")
	_check(token.cancelled.get_connections().is_empty(), "already-cancelled token releases handler")
	transport.max_concurrent_requests = 1
	var active_token: YouTubeCancellationToken = YouTubeCancellationToken.new()
	var queued_token: YouTubeCancellationToken = YouTubeCancellationToken.new()
	var active: YouTubeHttpTicket = _request(transport, url, active_token)
	var queued: YouTubeHttpTicket = _request(transport, url, queued_token)
	_check(transport.active_count() == 1 and transport.queued_count() == 1, "second request queues")
	queued_token.cancel("queued cancel")
	_check(queued.is_cancelled and queued_token.cancelled.get_connections().is_empty(), "queued cancellation releases handler")
	transport.cancel_all("fixture cleanup")
	_check(active.is_cancelled and active_token.cancelled.get_connections().is_empty(), "cancel_all releases handler")
	transport.max_retries = 1
	transport.retry_base_delay_msec = 0
	var retry_token: YouTubeCancellationToken = YouTubeCancellationToken.new()
	var retry: YouTubeHttpTicket = _request(transport, "http://127.0.0.1:9/retry", retry_token)
	await _wait_for_ticket(retry)
	_check(retry.response != null and retry.response.attempt_count == 2, "request retries before final completion")
	_check(retry_token.cancelled.get_connections().is_empty(), "final retry releases handler")
	transport.free()
	server.stop()
	await process_frame
	if _failures.is_empty():
		print("HTTP CANCELLATION REUSE PASS: %d checks" % _checks)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)

func _wait_for_ticket(ticket: YouTubeHttpTicket) -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while not ticket.is_completed and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(ticket.is_completed, "HTTP ticket completes within deadline")

func _request(transport: YouTubeHttpTransport, url: String, token: YouTubeCancellationToken) -> YouTubeHttpTicket:
	return transport.request(url, PackedStringArray(), HTTPClient.METHOD_GET, PackedByteArray(), token)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
