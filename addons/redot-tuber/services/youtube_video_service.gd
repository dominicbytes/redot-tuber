class_name YouTubeVideoService
extends RefCounted

var _api: Variant


func _init(api_client: Variant) -> void:
	_api = api_client


func resolve_live_chat(video_id: String, cancellation: YouTubeCancellationToken = null) -> YouTubeLiveChatResolution:
	var resolution: YouTubeLiveChatResolution = YouTubeLiveChatResolution.new()
	resolution.video_id = video_id
	if video_id.strip_edges().is_empty():
		resolution.status = YouTubeLiveChatResolution.STATUS_NOT_FOUND
		resolution.error = YouTubeApiError.invalid("Video ID is required")
		return resolution
	var response: YouTubeHttpResponse = await _api.request_json(
		"videos.list",
		HTTPClient.METHOD_GET,
		"/videos",
		{"part": "snippet,liveStreamingDetails", "id": video_id},
		{},
		cancellation
	)
	if response == null:
		resolution.error = YouTubeApiError.from_transport(ERR_CANT_ACQUIRE_RESOURCE, "Video request returned no response")
		return resolution
	if not response.is_success():
		resolution.error = response.error if response.error != null else YouTubeApiError.from_http(response.status_code, response.parsed_json)
		resolution.status = YouTubeLiveChatResolution.STATUS_DENIED if resolution.error.category in ["authorization", "denied"] else YouTubeLiveChatResolution.STATUS_ERROR
		return resolution
	if not response.parsed_json is Dictionary:
		resolution.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Video response is not a JSON object")
		return resolution
	var items_value: Variant = response.parsed_json.get("items", [])
	if not items_value is Array or items_value.is_empty():
		resolution.status = YouTubeLiveChatResolution.STATUS_NOT_FOUND
		return resolution
	var item_value: Variant = items_value[0]
	if not item_value is Dictionary:
		resolution.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Video item is not an object")
		return resolution
	var item: Dictionary = item_value
	var snippet: Dictionary = item.get("snippet", {}) if item.get("snippet", {}) is Dictionary else {}
	var details: Dictionary = item.get("liveStreamingDetails", {}) if item.get("liveStreamingDetails", {}) is Dictionary else {}
	resolution.title = String(snippet.get("title", ""))
	resolution.actual_start_time = String(details.get("actualStartTime", ""))
	resolution.actual_end_time = String(details.get("actualEndTime", ""))
	resolution.scheduled_start_time = String(details.get("scheduledStartTime", ""))
	resolution.live_chat_id = String(details.get("activeLiveChatId", ""))
	if not resolution.actual_end_time.is_empty():
		resolution.status = YouTubeLiveChatResolution.STATUS_ENDED
	elif resolution.live_chat_id.is_empty():
		resolution.status = YouTubeLiveChatResolution.STATUS_CHAT_DISABLED
	else:
		resolution.status = YouTubeLiveChatResolution.STATUS_ACTIVE
	return resolution
