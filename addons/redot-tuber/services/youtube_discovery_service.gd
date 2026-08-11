class_name YouTubeDiscoveryService
extends RefCounted

var minimum_search_interval_msec: int = 30000
var cache_ttl_msec: int = 60000

var _api: Variant
var _gate: YouTubeCapabilityGate = null
var _cache: Dictionary = {}
var _last_search_at_msec: int = -30000


func _init(api_client: Variant, capability_gate: YouTubeCapabilityGate = null) -> void:
	_api = api_client
	_gate = capability_gate


func search_live_videos(
	query_text: String = "",
	event_type: String = "live",
	channel_id: String = "",
	page_token: String = "",
	max_results: int = 25,
	force_refresh: bool = false,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeApiPage:
	if event_type not in ["live", "upcoming", "completed"]:
		return _failed(YouTubeApiError.invalid("Search event type must be live, upcoming, or completed"))
	if _gate != null:
		var gate_error: YouTubeApiError = _gate.require_method("search.list")
		if gate_error != null:
			return _failed(gate_error)
	var query: Dictionary = {
		"part": "snippet",
		"type": "video",
		"eventType": event_type,
		"maxResults": clampi(max_results, 1, 50),
		"q": query_text.strip_edges(),
		"channelId": channel_id.strip_edges(),
		"pageToken": page_token,
	}
	var cache_key: String = JSON.stringify(query)
	var now: int = Time.get_ticks_msec()
	if not force_refresh and _cache.has(cache_key):
		var cached: Dictionary = _cache[cache_key]
		if int(cached.get("expires_at", 0)) > now:
			var page: YouTubeApiPage = cached.page
			page.from_cache = true
			return page
	if now - _last_search_at_msec < minimum_search_interval_msec:
		return _failed(YouTubeApiError.custom("discovery_throttled", "YouTube search is manual and may be refreshed again after the configured interval", true))
	_last_search_at_msec = now
	var response: YouTubeHttpResponse = await _api.request_json(
		"search.list", HTTPClient.METHOD_GET, "/search", query, {}, cancellation
	)
	var page: YouTubeApiPage = YouTubeApiPage.new()
	if response == null or not response.is_success():
		page.error = response.error if response != null and response.error != null else YouTubeApiError.custom("transport", "Unable to search YouTube live videos")
		return page
	if not response.parsed_json is Dictionary:
		page.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "YouTube search response is not a JSON object")
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
				page.items.append(YouTubeDiscoveryItem.from_api(item))
	_cache[cache_key] = {"expires_at": now + maxi(0, cache_ttl_msec), "page": page}
	return page


func clear_cache() -> void:
	_cache.clear()


func cached_query_count() -> int:
	return _cache.size()


func _failed(error: YouTubeApiError) -> YouTubeApiPage:
	var page: YouTubeApiPage = YouTubeApiPage.new()
	page.error = error
	return page
