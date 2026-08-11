class_name YouTubeChannelService
extends RefCounted

var _api: Variant
var _gate: YouTubeCapabilityGate = null


func _init(api_client: Variant, capability_gate: YouTubeCapabilityGate = null) -> void:
	_api = api_client
	_gate = capability_gate


func get_mine(cancellation: YouTubeCancellationToken = null) -> YouTubeChannelResult:
	var result: YouTubeChannelResult = YouTubeChannelResult.new()
	if _gate != null:
		var gate_error: YouTubeApiError = _gate.require_method("channels.list")
		if gate_error != null:
			result.error = gate_error
			return result
		if not _gate.is_authenticated():
			result.error = YouTubeApiError.custom("authorization", "An authorized YouTube account is required to load the current channel")
			return result
	var response: YouTubeHttpResponse = await _api.request_json(
		"channels.list",
		HTTPClient.METHOD_GET,
		"/channels",
		{"part": "id,snippet", "mine": "true"},
		{},
		cancellation
	)
	if response == null or not response.is_success():
		result.error = response.error if response != null and response.error != null else YouTubeApiError.custom("authorization", "Unable to load the authorized YouTube channel")
		return result
	if not response.parsed_json is Dictionary:
		result.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Channel response is not a JSON object")
		return result
	var items: Variant = response.parsed_json.get("items", [])
	if not items is Array or items.is_empty() or not items[0] is Dictionary:
		result.error = YouTubeApiError.custom("channel_not_found", "The authorized account does not expose a YouTube channel")
		return result
	result.channel = YouTubeChannelIdentity.from_api(items[0])
	if result.channel.id.is_empty():
		result.channel = null
		result.error = YouTubeApiError.from_transport(ERR_INVALID_DATA, "Channel response omitted its ID")
	return result


func list_by_ids(
	channel_ids: PackedStringArray,
	page_token: String = "",
	max_results: int = 50,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeApiPage:
	if channel_ids.is_empty() or channel_ids.size() > 50:
		return _failed_page(YouTubeApiError.invalid("Provide between 1 and 50 channel IDs"))
	return await _list({
		"id": ",".join(channel_ids),
		"part": "id,snippet",
		"maxResults": clampi(max_results, 1, 50),
		"pageToken": page_token,
	}, cancellation)


func get_by_handle(handle: String, cancellation: YouTubeCancellationToken = null) -> YouTubeChannelResult:
	var result: YouTubeChannelResult = YouTubeChannelResult.new()
	var normalized: String = handle.strip_edges()
	if normalized.is_empty():
		result.error = YouTubeApiError.invalid("A YouTube channel handle is required")
		return result
	var page: YouTubeApiPage = await _list({"part": "id,snippet", "forHandle": normalized}, cancellation)
	if page.error != null:
		result.error = page.error
	elif page.items.is_empty():
		result.error = YouTubeApiError.custom("not_found", "No YouTube channel matched that handle")
	else:
		result.channel = page.items[0]
	return result


func _list(query: Dictionary, cancellation: YouTubeCancellationToken) -> YouTubeApiPage:
	if _gate != null:
		var gate_error: YouTubeApiError = _gate.require_method("channels.list")
		if gate_error != null:
			return _failed_page(gate_error)
	var response: YouTubeHttpResponse = await _api.request_json(
		"channels.list", HTTPClient.METHOD_GET, "/channels", query, {}, cancellation
	)
	var page: YouTubeApiPage = YouTubeApiPage.new()
	if response == null or not response.is_success():
		page.error = response.error if response != null and response.error != null else YouTubeApiError.custom("transport", "Unable to list YouTube channels")
		return page
	if not response.parsed_json is Dictionary:
		page.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Channel list response is not a JSON object")
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
				page.items.append(YouTubeChannelIdentity.from_api(item))
	return page


func _failed_page(error: YouTubeApiError) -> YouTubeApiPage:
	var page: YouTubeApiPage = YouTubeApiPage.new()
	page.error = error
	return page
