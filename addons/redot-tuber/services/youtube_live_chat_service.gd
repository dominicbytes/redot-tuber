class_name YouTubeLiveChatService
extends RefCounted

const NormalizerClass = preload("res://addons/redot-tuber/models/youtube_live_event_normalizer.gd")

var _api: Variant
var _normalizer: YouTubeLiveEventNormalizer = NormalizerClass.new()
var _gate: YouTubeCapabilityGate = null


func _init(api_client: Variant, capability_gate: YouTubeCapabilityGate = null) -> void:
	_api = api_client
	_gate = capability_gate


func list_messages(
	live_chat_id: String,
	page_token: String = "",
	max_results: int = 200,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeLiveChatPage:
	var page: YouTubeLiveChatPage = YouTubeLiveChatPage.new()
	if live_chat_id.is_empty():
		page.error = YouTubeApiError.invalid("Live chat ID is required")
		return page
	if _gate != null:
		var gate_error: YouTubeApiError = _gate.require_method("liveChatMessages.list")
		if gate_error != null:
			page.error = gate_error
			return page
	var query: Dictionary = {
		"liveChatId": live_chat_id,
		"part": "id,snippet,authorDetails",
		"maxResults": clampi(max_results, 200, 2000),
	}
	if not page_token.is_empty():
		query["pageToken"] = page_token
	var response: YouTubeHttpResponse = await _api.request_json(
		"liveChatMessages.list",
		HTTPClient.METHOD_GET,
		"/liveChat/messages",
		query,
		{},
		cancellation
	)
	if response == null:
		page.error = YouTubeApiError.from_transport(ERR_CANT_ACQUIRE_RESOURCE, "Chat request returned no response")
		return page
	if not response.is_success():
		page.error = response.error if response.error != null else YouTubeApiError.from_http(response.status_code, response.parsed_json)
		return page
	if not response.parsed_json is Dictionary:
		page.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Chat response is not a JSON object")
		return page
	return parse_page(response.parsed_json)


func parse_page(payload: Dictionary) -> YouTubeLiveChatPage:
	var page: YouTubeLiveChatPage = YouTubeLiveChatPage.new()
	page.next_page_token = String(payload.get("nextPageToken", ""))
	page.polling_interval_msec = maxi(0, int(payload.get("pollingIntervalMillis", 5000)))
	page.offline_at = String(payload.get("offlineAt", ""))
	var items: Variant = payload.get("items", [])
	if items is Array:
		for raw: Variant in items:
			var event: YouTubeLiveEvent = _normalizer.normalize(raw)
			if event != null:
				page.events.append(event)
	return page


func send_text(
	live_chat_id: String,
	message_text: String,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var validation: YouTubeApiError = _validate_live_chat(live_chat_id)
	if validation == null and (message_text.strip_edges().is_empty() or message_text.length() > 200):
		validation = YouTubeApiError.invalid("Chat text must contain between 1 and 200 characters")
	return await _insert_message(
		"liveChatMessages.insert",
		{"snippet": {
			"liveChatId": live_chat_id,
			"type": "textMessageEvent",
			"textMessageDetails": {"messageText": message_text},
		}},
		validation,
		cancellation
	)


func create_poll(
	live_chat_id: String,
	question_text: String,
	option_texts: PackedStringArray,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var validation: YouTubeApiError = _validate_live_chat(live_chat_id)
	if validation == null and question_text.strip_edges().is_empty():
		validation = YouTubeApiError.invalid("Poll question is required")
	if validation == null and (option_texts.size() < 2 or option_texts.size() > 4):
		validation = YouTubeApiError.invalid("A YouTube live poll requires between 2 and 4 options")
	var options: Array[Dictionary] = []
	for option_text: String in option_texts:
		if validation == null and option_text.strip_edges().is_empty():
			validation = YouTubeApiError.invalid("Poll options cannot be empty")
		options.append({"optionText": option_text})
	return await _insert_message(
		"liveChatMessages.insert",
		{"snippet": {
			"liveChatId": live_chat_id,
			"type": "pollEvent",
			"pollDetails": {"metadata": {"questionText": question_text, "options": options}},
		}},
		validation,
		cancellation
	)


func close_poll(
	message_id: String,
	confirmed: bool,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveChatMessages.transition")
	if message_id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("Poll message ID is required")
		return result
	result.error = _guard_write(result.method_id, confirmed)
	if result.error != null:
		return result
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id,
		HTTPClient.METHOD_POST,
		"/liveChat/messages/transition",
		{"id": message_id, "status": "closed", "part": "snippet,authorDetails"},
		{},
		cancellation
	)
	return _event_result(result, response)


func _insert_message(
	method_id: String,
	body: Dictionary,
	validation: YouTubeApiError,
	cancellation: YouTubeCancellationToken
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result(method_id)
	if validation != null:
		result.error = validation
		return result
	result.error = _guard_write(method_id)
	if result.error != null:
		return result
	var response: YouTubeHttpResponse = await _api.request_json(
		method_id, HTTPClient.METHOD_POST, "/liveChat/messages", {"part": "snippet"}, body, cancellation
	)
	return _event_result(result, response)


func _event_result(result: YouTubeOperationResult, response: YouTubeHttpResponse) -> YouTubeOperationResult:
	if response == null:
		result.error = YouTubeApiError.custom("transport", "YouTube chat operation returned no response")
		return result
	result.status_code = response.status_code
	if not response.is_success():
		result.error = response.error if response.error != null else YouTubeApiError.from_http(response.status_code, response.parsed_json)
		return result
	if response.parsed_json is Dictionary:
		result.value = _normalizer.normalize(response.parsed_json)
	if result.value == null:
		result.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "YouTube chat operation returned an invalid message")
	return result


func _validate_live_chat(live_chat_id: String) -> YouTubeApiError:
	return YouTubeApiError.invalid("Live chat ID is required") if live_chat_id.strip_edges().is_empty() else null


func _guard_write(method_id: String, confirmed: bool = false) -> YouTubeApiError:
	if _gate == null:
		return YouTubeApiError.custom("capability_unconfigured", "A capability gate is required for YouTube write operations")
	return _gate.require_method(method_id, confirmed)


func _new_result(method_id: String) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = YouTubeOperationResult.new()
	result.method_id = method_id
	return result
