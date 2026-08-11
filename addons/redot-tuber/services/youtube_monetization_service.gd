class_name YouTubeMonetizationService
extends RefCounted

var _api: Variant
var _gate: YouTubeCapabilityGate


func _init(api_client: Variant, capability_gate: YouTubeCapabilityGate) -> void:
	_api = api_client
	_gate = capability_gate


func list_super_chat_events(
	page_token: String = "",
	max_results: int = 50,
	language: String = "",
	cancellation: YouTubeCancellationToken = null
) -> YouTubeApiPage:
	var page: YouTubeApiPage = YouTubeApiPage.new()
	if _gate == null:
		page.error = YouTubeApiError.custom("capability_unconfigured", "A capability gate is required for monetization reads")
		return page
	page.error = _gate.require_method("superChatEvents.list")
	if page.error != null:
		return page
	var response: YouTubeHttpResponse = await _api.request_json(
		"superChatEvents.list",
		HTTPClient.METHOD_GET,
		"/superChatEvents",
		{"part": "id,snippet", "maxResults": clampi(max_results, 1, 50), "pageToken": page_token, "hl": language},
		{},
		cancellation
	)
	if response == null or not response.is_success():
		page.error = response.error if response != null and response.error != null else YouTubeApiError.custom("transport", "Unable to list Super Chat events")
		return page
	if not response.parsed_json is Dictionary:
		page.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Super Chat response is not a JSON object")
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
				page.items.append(YouTubeSuperChatEvent.from_api(item))
	return page
