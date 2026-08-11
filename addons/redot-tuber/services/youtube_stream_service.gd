class_name YouTubeStreamService
extends RefCounted

const ALLOWED_PARTS: PackedStringArray = ["snippet", "cdn", "contentDetails"]

var _api: Variant
var _gate: YouTubeCapabilityGate


func _init(api_client: Variant, capability_gate: YouTubeCapabilityGate) -> void:
	_api = api_client
	_gate = capability_gate


func list_streams(
	filter: Dictionary = {"mine": "true"},
	page_token: String = "",
	max_results: int = 25,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeApiPage:
	var page: YouTubeApiPage = YouTubeApiPage.new()
	page.error = _guard("liveStreams.list")
	if page.error != null:
		return page
	var filters_present: int = 0
	for key: String in ["id", "mine"]:
		if filter.has(key) and not String(filter[key]).is_empty():
			filters_present += 1
	if filters_present != 1:
		page.error = YouTubeApiError.invalid("Stream discovery requires exactly one of id or mine")
		return page
	var query: Dictionary = filter.duplicate(true)
	query["part"] = "id,snippet,cdn,status,contentDetails"
	query["maxResults"] = clampi(max_results, 1, 50)
	query["pageToken"] = page_token
	var response: YouTubeHttpResponse = await _api.request_json(
		"liveStreams.list", HTTPClient.METHOD_GET, "/liveStreams", query, {}, cancellation
	)
	return _stream_page(response)


func create_stream(stream: YouTubeLiveStream, cancellation: YouTubeCancellationToken = null) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveStreams.insert")
	result.error = _validate_create(stream)
	if result.error == null:
		result.error = _guard(result.method_id)
	if result.error != null:
		return result
	var parts: PackedStringArray = ["snippet", "cdn"]
	if not stream.content_details.is_empty():
		parts.append("contentDetails")
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id,
		HTTPClient.METHOD_POST,
		"/liveStreams",
		{"part": ",".join(parts)},
		stream.to_insert_body(),
		cancellation
	)
	return _stream_result(result, response)


func update_stream(
	stream: YouTubeLiveStream,
	parts: PackedStringArray,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveStreams.update")
	if stream == null or stream.id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("A stream with an ID is required")
		return result
	result.error = _validate_parts(parts)
	if result.error == null:
		result.error = _guard(result.method_id)
	if result.error != null:
		return result
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id,
		HTTPClient.METHOD_PUT,
		"/liveStreams",
		{"part": ",".join(parts)},
		stream.to_update_body(parts),
		cancellation
	)
	return _stream_result(result, response)


func delete_stream(
	stream_id: String,
	confirmed: bool,
	cancellation: YouTubeCancellationToken = null
) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = _new_result("liveStreams.delete")
	if stream_id.strip_edges().is_empty():
		result.error = YouTubeApiError.invalid("Stream ID is required")
		return result
	result.error = _guard(result.method_id, confirmed)
	if result.error != null:
		return result
	var response: YouTubeHttpResponse = await _api.request_json(
		result.method_id, HTTPClient.METHOD_DELETE, "/liveStreams", {"id": stream_id}, {}, cancellation
	)
	if response == null:
		result.error = YouTubeApiError.custom("transport", "Stream deletion returned no response")
		return result
	result.status_code = response.status_code
	if response.is_success():
		result.value = true
	else:
		result.error = response.error if response.error != null else YouTubeApiError.from_http(response.status_code, response.parsed_json)
	return result


func _validate_create(stream: YouTubeLiveStream) -> YouTubeApiError:
	if stream == null:
		return YouTubeApiError.invalid("A stream resource is required")
	if stream.title.strip_edges().is_empty() or stream.title.length() > 128:
		return YouTubeApiError.invalid("Stream title must contain between 1 and 128 characters")
	if stream.ingestion_type.strip_edges().is_empty():
		return YouTubeApiError.invalid("Stream ingestion type is required")
	if stream.resolution.strip_edges().is_empty() or stream.frame_rate.strip_edges().is_empty():
		return YouTubeApiError.invalid("Stream resolution and frame rate are required")
	return null


func _validate_parts(parts: PackedStringArray) -> YouTubeApiError:
	if parts.is_empty():
		return YouTubeApiError.invalid("At least one mutable stream part is required")
	for part: String in parts:
		if part not in ALLOWED_PARTS:
			return YouTubeApiError.invalid("Unsupported mutable stream part: %s" % part)
	return null


func _stream_page(response: YouTubeHttpResponse) -> YouTubeApiPage:
	var page: YouTubeApiPage = YouTubeApiPage.new()
	if response == null or not response.is_success():
		page.error = response.error if response != null and response.error != null else YouTubeApiError.custom("transport", "Unable to list YouTube streams")
		return page
	if not response.parsed_json is Dictionary:
		page.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Stream list response is not a JSON object")
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
				page.items.append(YouTubeLiveStream.from_api(item))
	return page


func _stream_result(result: YouTubeOperationResult, response: YouTubeHttpResponse) -> YouTubeOperationResult:
	if response == null:
		result.error = YouTubeApiError.custom("transport", "Stream operation returned no response")
		return result
	result.status_code = response.status_code
	if not response.is_success():
		result.error = response.error if response.error != null else YouTubeApiError.from_http(response.status_code, response.parsed_json)
	elif response.parsed_json is Dictionary:
		result.value = YouTubeLiveStream.from_api(response.parsed_json)
	else:
		result.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Stream operation returned invalid data")
	return result


func _guard(method_id: String, confirmed: bool = false) -> YouTubeApiError:
	if _gate == null:
		return YouTubeApiError.custom("capability_unconfigured", "A capability gate is required for stream operations")
	return _gate.require_method(method_id, confirmed)


func _new_result(method_id: String) -> YouTubeOperationResult:
	var result: YouTubeOperationResult = YouTubeOperationResult.new()
	result.method_id = method_id
	return result
