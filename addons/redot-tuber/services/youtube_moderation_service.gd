class_name YouTubeModerationService
extends RefCounted

var _api: Variant
var _gate: YouTubeCapabilityGate


func _init(api_client: Variant, capability_gate: YouTubeCapabilityGate) -> void:
	_api = api_client
	_gate = capability_gate


func delete_message(
	message_id: String,
	confirmed: bool,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	return await _delete_by_id("liveChatMessages.delete", "/liveChat/messages", message_id, confirmed, cancellation)


func ban_user(
	live_chat_id: String,
	channel_id: String,
	ban_type: String = "permanent",
	duration_seconds: int = 0,
	confirmed: bool = false,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveChatBans.insert")
	if live_chat_id.strip_edges().is_empty() or channel_id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("Live chat ID and target channel ID are required")
		return result
	if ban_type not in ["permanent", "temporary"]:
		result.error = YouTubeApiError.invalid("Ban type must be permanent or temporary")
		return result
	if ban_type == "temporary" and duration_seconds <= 0:
		result.error = YouTubeApiError.invalid("Temporary bans require a positive duration in seconds")
		return result
	result.error = _guard(result.method_id, confirmed)
	if result.error != null:
		return result
	var snippet: Dictionary = {
		"liveChatId": live_chat_id,
		"type": ban_type,
		"bannedUserDetails": {"channelId": channel_id},
	}
	if ban_type == "temporary":
		snippet["banDurationSeconds"] = duration_seconds
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id,
		HTTPClient.METHOD_POST,
		"/liveChat/bans",
		{"part": "snippet"},
		{"snippet": snippet},
		cancellation
	)
	return _resource_result(result, response, func(payload: Dictionary) -> YouTubeLiveChatBan: return YouTubeLiveChatBan.from_api(payload))


func unban_user(
	ban_id: String,
	confirmed: bool,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	return await _delete_by_id("liveChatBans.delete", "/liveChat/bans", ban_id, confirmed, cancellation)


func list_moderators(
	live_chat_id: String,
	page_token: String = "",
	max_results: int = 50,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeApiPage:
	var page: YouTubeApiPage = YouTubeApiPage.new()
	if live_chat_id.strip_edges().is_empty():
		page.error = YouTubeApiError.invalid("Live chat ID is required")
		return page
	page.error = _guard("liveChatModerators.list")
	if page.error != null:
		return page
	var response: YouTubeHttpResponse = await _api.request_json(
		"liveChatModerators.list",
		HTTPClient.METHOD_GET,
		"/liveChat/moderators",
		{"liveChatId": live_chat_id, "part": "id,snippet", "maxResults": clampi(max_results, 5, 50), "pageToken": page_token},
		{},
		cancellation
	)
	return _moderator_page(response)


func add_moderator(
	live_chat_id: String,
	channel_id: String,
	confirmed: bool,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveChatModerators.insert")
	if live_chat_id.strip_edges().is_empty() or channel_id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("Live chat ID and moderator channel ID are required")
		return result
	result.error = _guard(result.method_id, confirmed)
	if result.error != null:
		return result
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id,
		HTTPClient.METHOD_POST,
		"/liveChat/moderators",
		{"part": "snippet"},
		{"snippet": {"liveChatId": live_chat_id, "moderatorDetails": {"channelId": channel_id}}},
		cancellation
	)
	return _resource_result(result, response, func(payload: Dictionary) -> YouTubeLiveChatModerator: return YouTubeLiveChatModerator.from_api(payload))


func remove_moderator(
	moderator_id: String,
	confirmed: bool,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	return await _delete_by_id("liveChatModerators.delete", "/liveChat/moderators", moderator_id, confirmed, cancellation)


func _delete_by_id(
	method_id: String,
	path: String,
	resource_id: String,
	confirmed: bool,
	cancellation: YouTubeCancellationToken
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result(method_id)
	if resource_id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("A YouTube resource ID is required")
		return result
	result.error = _guard(method_id, confirmed)
	if result.error != null:
		return result
	var response: YouTubeHttpResponse = await _api.request_json(
		method_id, HTTPClient.METHOD_DELETE, path, {"id": resource_id}, {}, cancellation
	)
	return _resource_result(result, response, func(_payload: Dictionary) -> bool: return true, true)


func _moderator_page(response: YouTubeHttpResponse) -> YouTubeApiPage:
	var page: YouTubeApiPage = YouTubeApiPage.new()
	if response == null or not response.is_success():
		page.error = response.error if response != null and response.error != null else YouTubeApiError.custom("transport", "Unable to list live chat moderators")
		return page
	if not response.parsed_json is Dictionary:
		page.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Moderator list response is not a JSON object")
		return page
	var payload: Dictionary = response.parsed_json
	page.next_page_token = String(payload.get("nextPageToken", ""))
	page.previous_page_token = String(payload.get("prevPageToken", ""))
	var page_info: Dictionary = payload.get("pageInfo", {}) if payload.get("pageInfo", {}) is Dictionary else {}
	page.total_results = int(page_info.get("totalResults", 0))
	page.results_per_page = int(page_info.get("resultsPerPage", 0))
	var items: Variant = payload.get("items", [])
	if items is Array:
		for item: Variant in items:
			if item is Dictionary:
				page.items.append(YouTubeLiveChatModerator.from_api(item))
	return page


func _resource_result(
	result: YouTubeOperationResult,
	response: YouTubeHttpResponse,
	parser: Callable,
	empty_success: bool = false
) -> YouTubeOperationResult:
	if response == null:
		result.error = YouTubeApiError.custom("transport", "YouTube moderation operation returned no response")
		return result
	result.status_code = response.status_code
	if not response.is_success():
		result.error = response.error if response.error != null else YouTubeApiError.from_http(response.status_code, response.parsed_json)
		return result
	if empty_success:
		result.value = true
	elif response.parsed_json is Dictionary:
		result.value = parser.call(response.parsed_json)
	if result.value == null:
		result.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "YouTube moderation operation returned invalid data")
	return result


func _guard(method_id: String, confirmed: bool = false) -> YouTubeApiError:
	if _gate == null:
		return YouTubeApiError.custom("capability_unconfigured", "A capability gate is required for YouTube moderation operations")
	return _gate.require_method(method_id, confirmed)


func _new_result(method_id: String) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = YouTubeOperationResult.new()
	result.method_id = method_id
	return result
