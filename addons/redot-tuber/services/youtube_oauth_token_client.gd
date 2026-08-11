class_name YouTubeOAuthTokenClient
extends RefCounted

var _transport: YouTubeHttpTransport


func _init(transport: YouTubeHttpTransport) -> void:
	_transport = transport


func exchange(endpoint: String, parameters: Dictionary, cancellation: YouTubeCancellationToken = null) -> YouTubeTokenOperationResult:
	return await _post_token(endpoint, parameters, cancellation)


func refresh(endpoint: String, client_id: String, refresh_token: String, cancellation: YouTubeCancellationToken = null) -> YouTubeTokenOperationResult:
	if client_id.is_empty() or refresh_token.is_empty():
		var invalid: YouTubeTokenOperationResult = YouTubeTokenOperationResult.new()
		invalid.error = YouTubeApiError.invalid("Client ID and refresh token are required")
		return invalid
	return await _post_token(endpoint, {
		"client_id": client_id,
		"grant_type": "refresh_token",
		"refresh_token": refresh_token,
	}, cancellation)


func revoke(endpoint: String, token: String, cancellation: YouTubeCancellationToken = null) -> YouTubeTokenOperationResult:
	var result: YouTubeTokenOperationResult = YouTubeTokenOperationResult.new()
	if token.is_empty():
		result.error = YouTubeApiError.invalid("A token is required for revocation")
		return result
	var ticket: YouTubeHttpTicket = _transport.request(
		endpoint,
		PackedStringArray(["Accept: application/json", "Content-Type: application/x-www-form-urlencoded"]),
		HTTPClient.METHOD_POST,
		_encode_form({"token": token}).to_utf8_buffer(),
		cancellation
	)
	var response: YouTubeHttpResponse = await ticket.wait_for_response()
	if not response.is_success():
		result.error = _oauth_error(response)
		return result
	result.revoked = true
	return result


func _post_token(endpoint: String, parameters: Dictionary, cancellation: YouTubeCancellationToken) -> YouTubeTokenOperationResult:
	var result: YouTubeTokenOperationResult = YouTubeTokenOperationResult.new()
	if _transport == null:
		result.error = YouTubeApiError.from_transport(ERR_UNCONFIGURED, "OAuth transport is unavailable")
		return result
	if parameters.has("client_secret"):
		result.error = YouTubeApiError.invalid("Installed-app OAuth must not send a client secret")
		return result
	var ticket: YouTubeHttpTicket = _transport.request(
		endpoint,
		PackedStringArray(["Accept: application/json", "Content-Type: application/x-www-form-urlencoded"]),
		HTTPClient.METHOD_POST,
		_encode_form(parameters).to_utf8_buffer(),
		cancellation
	)
	var response: YouTubeHttpResponse = await ticket.wait_for_response()
	if not response.is_success():
		result.error = _oauth_error(response)
		return result
	if not response.parsed_json is Dictionary:
		result.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "OAuth token endpoint returned invalid JSON")
		return result
	var payload: Dictionary = response.parsed_json
	var access_token: String = String(payload.get("access_token", ""))
	var expires_in: int = int(payload.get("expires_in", 0))
	if access_token.is_empty() or expires_in <= 0:
		result.error = YouTubeApiError.from_transport(ERR_INVALID_DATA, "OAuth token response omitted required fields")
		return result
	var token: YouTubeAuthTokenSet = YouTubeAuthTokenSet.new()
	token.access_token = access_token
	token.refresh_token = String(payload.get("refresh_token", ""))
	token.token_type = String(payload.get("token_type", "Bearer"))
	token.expires_at_unix = int(Time.get_unix_time_from_system()) + expires_in
	var scope_value: Variant = payload.get("scope", "")
	if scope_value is String:
		token.granted_scopes = PackedStringArray(String(scope_value).split(" ", false))
	elif scope_value is Array:
		for scope: Variant in scope_value:
			token.granted_scopes.append(String(scope))
	token.granted_scopes.sort()
	result.token = token
	return result


func _encode_form(parameters: Dictionary) -> String:
	var keys: Array = parameters.keys()
	keys.sort()
	var pairs: PackedStringArray = PackedStringArray()
	for key_value: Variant in keys:
		pairs.append("%s=%s" % [String(key_value).uri_encode(), String(parameters[key_value]).uri_encode()])
	return "&".join(pairs)


func _oauth_error(response: YouTubeHttpResponse) -> YouTubeApiError:
	if response.error != null and response.error.category in ["transport", "cancelled", "timeout", "server_error", "rate_limited"]:
		return response.error
	var error_name: String = ""
	var description: String = "OAuth request failed"
	if response.parsed_json is Dictionary:
		error_name = String(response.parsed_json.get("error", ""))
		description = String(response.parsed_json.get("error_description", description))
	var category: String = "authorization"
	if error_name in ["temporarily_unavailable", "server_error"]:
		category = "server_error"
	elif error_name == "access_denied":
		category = "authorization_denied"
	elif error_name == "invalid_request":
		category = "invalid_request"
	return YouTubeApiError.custom(category, description, category == "server_error")
