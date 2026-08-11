class_name YouTubeBroadcastService
extends RefCounted

const ALLOWED_PARTS: PackedStringArray = ["snippet", "status", "contentDetails", "monetizationDetails"]
const ALLOWED_TRANSITIONS: PackedStringArray = ["testing", "live", "complete"]
const TRANSITIONS_BY_STATE: Dictionary = {
	"created": ["testing", "live"],
	"ready": ["testing", "live"],
	"testing": ["live"],
	"live": ["complete"],
}

var _api: Variant
var _gate: YouTubeCapabilityGate


func _init(api_client: Variant, capability_gate: YouTubeCapabilityGate) -> void:
	_api = api_client
	_gate = capability_gate


func list_broadcasts(
	filter: Dictionary = {"mine": "true"},
	page_token: String = "",
	max_results: int = 25,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeApiPage:
	var page: YouTubeApiPage = YouTubeApiPage.new()
	page.error = _guard("liveBroadcasts.list")
	if page.error != null:
		return page
	var filters_present: int = 0
	for key: String in ["broadcastStatus", "id", "mine"]:
		if filter.has(key) and not String(filter[key]).is_empty():
			filters_present += 1
	if filters_present != 1:
		page.error = YouTubeApiError.invalid("Broadcast discovery requires exactly one of broadcastStatus, id, or mine")
		return page
	if filter.has("broadcastStatus") and String(filter.broadcastStatus) not in ["active", "all", "completed", "upcoming"]:
		page.error = YouTubeApiError.invalid("Broadcast status must be active, all, completed, or upcoming")
		return page
	var query: Dictionary = filter.duplicate(true)
	query["part"] = "id,snippet,status,contentDetails,monetizationDetails"
	query["maxResults"] = clampi(max_results, 1, 50)
	query["pageToken"] = page_token
	var response: YouTubeHttpResponse = await _api.request_json(
		"liveBroadcasts.list", HTTPClient.METHOD_GET, "/liveBroadcasts", query, {}, cancellation
	)
	return _broadcast_page(response)


func create_broadcast(
	broadcast: YouTubeLiveBroadcast,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveBroadcasts.insert")
	result.error = _validate_create(broadcast)
	if result.error == null:
		result.error = _guard(result.method_id)
	if result.error != null:
		return result
	var parts: PackedStringArray = ["snippet", "status"]
	if not broadcast.content_details.is_empty():
		parts.append("contentDetails")
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id,
		HTTPClient.METHOD_POST,
		"/liveBroadcasts",
		{"part": ",".join(parts)},
		broadcast.to_insert_body(),
		cancellation
	)
	return _broadcast_result(result, response)


func update_broadcast(
	broadcast: YouTubeLiveBroadcast,
	parts: PackedStringArray,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveBroadcasts.update")
	if broadcast == null or broadcast.id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("A broadcast with an ID is required")
		return result
	result.error = _validate_parts(parts)
	if result.error == null:
		result.error = _guard(result.method_id)
	if result.error != null:
		return result
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id,
		HTTPClient.METHOD_PUT,
		"/liveBroadcasts",
		{"part": ",".join(parts)},
		broadcast.to_update_body(parts),
		cancellation
	)
	return _broadcast_result(result, response)


func delete_broadcast(
	broadcast_id: String,
	confirmed: bool,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	return await _delete("liveBroadcasts.delete", "/liveBroadcasts", broadcast_id, confirmed, cancellation)


func bind_stream(
	broadcast_id: String,
	stream_id: String,
	confirmed: bool,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveBroadcasts.bind")
	if broadcast_id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("Broadcast ID is required")
		return result
	result.error = _guard(result.method_id, confirmed)
	if result.error != null:
		return result
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id,
		HTTPClient.METHOD_POST,
		"/liveBroadcasts/bind",
		{"id": broadcast_id, "streamId": stream_id, "part": "id,snippet,status,contentDetails"},
		{},
		cancellation
	)
	return _broadcast_result(result, response)


func transition_broadcast(
	broadcast_id: String,
	target_status: String,
	current_status: String,
	confirmed: bool,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveBroadcasts.transition")
	if broadcast_id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("Broadcast ID is required")
		return result
	if target_status not in ALLOWED_TRANSITIONS:
		result.error = YouTubeApiError.invalid("Broadcast target status must be testing, live, or complete")
		return result
	var allowed: Array = TRANSITIONS_BY_STATE.get(current_status, [])
	if not allowed.has(target_status):
		result.error = YouTubeApiError.custom("invalid_state", "Cannot transition a broadcast from %s to %s" % [current_status, target_status])
		return result
	result.error = _guard(result.method_id, confirmed)
	if result.error != null:
		return result
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id,
		HTTPClient.METHOD_POST,
		"/liveBroadcasts/transition",
		{"id": broadcast_id, "broadcastStatus": target_status, "part": "id,snippet,status,contentDetails"},
		{},
		cancellation
	)
	return _broadcast_result(result, response)


func insert_cuepoint(
	broadcast_id: String,
	confirmed: bool,
	duration_seconds: int = 30,
	insertion_offset_msec: int = -1,
	walltime_msec: int = -1,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveBroadcasts.cuepoint")
	if broadcast_id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("Broadcast ID is required")
		return result
	if duration_seconds <= 0:
		result.error = YouTubeApiError.invalid("Cuepoint duration must be positive")
		return result
	if insertion_offset_msec >= 0 and walltime_msec >= 0:
		result.error = YouTubeApiError.invalid("A cuepoint may use insertion offset or wall time, not both")
		return result
	result.error = _guard(result.method_id, confirmed)
	if result.error != null:
		return result
	var body: Dictionary = {"cueType": "cueTypeAd", "durationSecs": duration_seconds}
	if insertion_offset_msec >= 0:
		body["insertionOffsetTimeMs"] = insertion_offset_msec
	elif walltime_msec >= 0:
		body["walltimeMs"] = walltime_msec
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id, HTTPClient.METHOD_POST, "/liveBroadcasts/cuepoint", {"id": broadcast_id}, body, cancellation
	)
	return _dictionary_result(result, response)


func _validate_create(broadcast: YouTubeLiveBroadcast) -> YouTubeApiError:
	if broadcast == null:
		return YouTubeApiError.invalid("A broadcast resource is required")
	if broadcast.title.strip_edges().is_empty() or broadcast.title.length() > 100:
		return YouTubeApiError.invalid("Broadcast title must contain between 1 and 100 characters")
	if broadcast.scheduled_start_time.strip_edges().is_empty():
		return YouTubeApiError.invalid("Broadcast scheduled start time is required")
	if broadcast.privacy_status not in ["private", "public", "unlisted"]:
		return YouTubeApiError.invalid("Broadcast privacy status must be private, public, or unlisted")
	return null


func _validate_parts(parts: PackedStringArray) -> YouTubeApiError:
	if parts.is_empty():
		return YouTubeApiError.invalid("At least one mutable broadcast part is required")
	for part: String in parts:
		if part not in ALLOWED_PARTS:
			return YouTubeApiError.invalid("Unsupported mutable broadcast part: %s" % part)
	return null


func _broadcast_page(response: YouTubeHttpResponse) -> YouTubeApiPage:
	var page: YouTubeApiPage = YouTubeApiPage.new()
	if response == null or not response.is_success():
		page.error = response.error if response != null and response.error != null else YouTubeApiError.custom("transport", "Unable to list YouTube broadcasts")
		return page
	if not response.parsed_json is Dictionary:
		page.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Broadcast list response is not a JSON object")
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
				page.items.append(YouTubeLiveBroadcast.from_api(item))
	return page


func _delete(method_id: String, path: String, id: String, confirmed: bool, cancellation: YouTubeCancellationToken) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result(method_id)
	if id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("Broadcast ID is required")
		return result
	result.error = _guard(method_id, confirmed)
	if result.error != null:
		return result
	var response: YouTubeHttpResponse = await _api.request_json(method_id, HTTPClient.METHOD_DELETE, path, {"id": id}, {}, cancellation)
	if response == null:
		result.error = YouTubeApiError.custom("transport", "Broadcast deletion returned no response")
		return result
	result.status_code = response.status_code
	if response.is_success():
		result.value = true
	else:
		result.error = response.error if response.error != null else YouTubeApiError.from_http(response.status_code, response.parsed_json)
	return result


func _broadcast_result(result: YouTubeOperationResult, response: YouTubeHttpResponse) -> YouTubeOperationResult:
	if response == null:
		result.error = YouTubeApiError.custom("transport", "Broadcast operation returned no response")
		return result
	result.status_code = response.status_code
	if not response.is_success():
		result.error = response.error if response.error != null else YouTubeApiError.from_http(response.status_code, response.parsed_json)
	elif response.parsed_json is Dictionary:
		result.value = YouTubeLiveBroadcast.from_api(response.parsed_json)
	else:
		result.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Broadcast operation returned invalid data")
	return result


func _dictionary_result(result: YouTubeOperationResult, response: YouTubeHttpResponse) -> YouTubeOperationResult:
	if response == null:
		result.error = YouTubeApiError.custom("transport", "Broadcast operation returned no response")
		return result
	result.status_code = response.status_code
	if not response.is_success():
		result.error = response.error if response.error != null else YouTubeApiError.from_http(response.status_code, response.parsed_json)
	elif response.parsed_json is Dictionary:
		result.value = response.parsed_json.duplicate(true)
	else:
		result.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Broadcast operation returned invalid data")
	return result


func _guard(method_id: String, confirmed: bool = false) -> YouTubeApiError:
	if _gate == null:
		return YouTubeApiError.custom("capability_unconfigured", "A capability gate is required for broadcast operations")
	return _gate.require_method(method_id, confirmed)


func _new_result(method_id: String) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = YouTubeOperationResult.new()
	result.method_id = method_id
	return result
