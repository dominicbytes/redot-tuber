class_name YouTubeApiClient
extends RefCounted

const DEFAULT_BASE_URL: String = "https://www.googleapis.com/youtube/v3"

var _transport: YouTubeHttpTransport
var _api_key: String = ""
var _access_token: String = ""
var _base_url: String = DEFAULT_BASE_URL
var _quota_ledger: YouTubeQuotaLedger = null
var _authorization_preflight: Callable = Callable()


func _init(transport: YouTubeHttpTransport = null, quota_ledger: YouTubeQuotaLedger = null) -> void:
	_transport = transport
	_quota_ledger = quota_ledger


func configure(api_key: String = "", access_token: String = "", base_url: String = DEFAULT_BASE_URL) -> YouTubeApiError:
	if api_key.is_empty() and access_token.is_empty():
		return YouTubeApiError.invalid("An API key or OAuth access token is required")
	if not base_url.begins_with("https://") and not base_url.begins_with("http://127.0.0.1:") and not base_url.begins_with("http://localhost:"):
		return YouTubeApiError.invalid("YouTube API base URL must use HTTPS")
	_api_key = api_key
	_access_token = access_token
	_base_url = base_url.trim_suffix("/")
	return null


func set_access_token(access_token: String) -> void:
	_access_token = access_token


func clear_access_token() -> void:
	_access_token = ""


func request_headers() -> PackedStringArray:
	var headers: PackedStringArray = PackedStringArray(["Accept: application/json"])
	if not _access_token.is_empty():
		headers.append("Authorization: Bearer %s" % _access_token)
	return headers


func begin_external_request(method_id: String) -> YouTubeApiError:
	if _quota_ledger == null:
		return null
	var quota_error: String = _quota_ledger.record_request(method_id, Time.get_ticks_msec())
	return YouTubeApiError.custom("quota_budget", quota_error) if not quota_error.is_empty() else null


func quota_ledger() -> YouTubeQuotaLedger:
	return _quota_ledger


func set_authorization_preflight(callback: Callable) -> void:
	_authorization_preflight = callback


func prepare_authorized_request() -> YouTubeApiError:
	if not _authorization_preflight.is_valid():
		return null
	var result: Variant = await _authorization_preflight.call()
	return result if result is YouTubeApiError else null


func build_url(path: String, query: Dictionary = {}) -> String:
	var pairs: PackedStringArray = PackedStringArray()
	var keys: Array = query.keys()
	keys.sort()
	for key_value: Variant in keys:
		var key: String = str(key_value)
		var value: Variant = query[key_value]
		if value == null or str(value).is_empty():
			continue
		pairs.append("%s=%s" % [key.uri_encode(), str(value).uri_encode()])
	if not _api_key.is_empty():
		pairs.append("key=%s" % _api_key.uri_encode())
	var url: String = _base_url + (path if path.begins_with("/") else "/" + path)
	if not pairs.is_empty():
		url += "?" + "&".join(pairs)
	return url


func request_json(
	method_id: String,
	http_method: int,
	path: String,
	query: Dictionary = {},
	body: Dictionary = {},
	cancellation: YouTubeCancellationToken = null
) -> YouTubeHttpResponse:
	if _transport == null:
		var unavailable: YouTubeHttpResponse = YouTubeHttpResponse.new()
		unavailable.request_result = HTTPRequest.RESULT_REQUEST_FAILED
		unavailable.error = YouTubeApiError.from_transport(ERR_UNCONFIGURED, "YouTube HTTP transport is unavailable")
		return unavailable
	var authorization_error: YouTubeApiError = await prepare_authorized_request()
	if authorization_error != null:
		var unauthorized: YouTubeHttpResponse = YouTubeHttpResponse.new()
		unauthorized.request_result = HTTPRequest.RESULT_REQUEST_FAILED
		unauthorized.error = authorization_error
		return unauthorized
	var headers: PackedStringArray = request_headers()
	var bytes: PackedByteArray = PackedByteArray()
	if not body.is_empty():
		headers.append("Content-Type: application/json; charset=utf-8")
		bytes = JSON.stringify(body).to_utf8_buffer()
	var quota_failure: YouTubeApiError = begin_external_request(method_id)
	if quota_failure != null:
			var rejected: YouTubeHttpResponse = YouTubeHttpResponse.new()
			rejected.request_result = HTTPRequest.RESULT_REQUEST_FAILED
			rejected.error = quota_failure
			return rejected
	var ticket: YouTubeHttpTicket = _transport.request(build_url(path, query), headers, http_method, bytes, cancellation)
	return await ticket.wait_for_response()
