class_name YouTubeApiError
extends RefCounted

var category: String = "unknown"
var message: String = "Unknown YouTube API error"
var http_status: int = 0
var transport_error: int = OK
var reasons: PackedStringArray = PackedStringArray()
var is_retryable: bool = false


static func from_transport(error_code: int, error_message: String) -> YouTubeApiError:
	var value: YouTubeApiError = YouTubeApiError.new()
	value.category = "cancelled" if error_code == ERR_SKIP else "transport"
	value.message = error_message
	value.transport_error = error_code
	value.is_retryable = error_code not in [OK, ERR_SKIP, ERR_INVALID_PARAMETER, ERR_OUT_OF_MEMORY]
	return value


static func from_http(status_code: int, payload: Variant) -> YouTubeApiError:
	var value: YouTubeApiError = YouTubeApiError.new()
	value.http_status = status_code
	var error_body: Dictionary = {}
	if payload is Dictionary:
		var candidate: Variant = payload.get("error", payload)
		if candidate is Dictionary:
			error_body = candidate
	value.message = String(error_body.get("message", "YouTube request failed with HTTP %d" % status_code))
	var errors_value: Variant = error_body.get("errors", [])
	if errors_value is Array:
		for item: Variant in errors_value:
			if item is Dictionary:
				var reason: String = String(item.get("reason", ""))
				if not reason.is_empty() and not value.reasons.has(reason):
					value.reasons.append(reason)
	value.category = _category_for(status_code, value.reasons)
	value.is_retryable = status_code == 408 or status_code == 429 or status_code >= 500
	return value


static func invalid(message_text: String) -> YouTubeApiError:
	var value: YouTubeApiError = YouTubeApiError.new()
	value.category = "invalid_request"
	value.message = message_text
	value.transport_error = ERR_INVALID_PARAMETER
	return value


static func custom(category_name: String, message_text: String, retryable: bool = false) -> YouTubeApiError:
	var value: YouTubeApiError = YouTubeApiError.new()
	value.category = category_name
	value.message = message_text
	value.is_retryable = retryable
	return value


static func _category_for(status_code: int, error_reasons: PackedStringArray) -> String:
	for reason: String in error_reasons:
		match reason:
			"quotaExceeded", "dailyLimitExceeded", "dailyLimitExceededUnreg":
				return "quota_exhausted"
			"rateLimitExceeded", "userRateLimitExceeded":
				return "rate_limited"
			"authError", "invalidCredentials", "youtubeSignupRequired":
				return "authorization"
			"liveChatDisabled":
				return "chat_disabled"
			"liveChatEnded":
				return "chat_ended"
			"notFound", "liveChatNotFound":
				return "not_found"
			"forbidden", "insufficientPermissions":
				return "denied"
	if status_code == 401:
		return "authorization"
	if status_code == 403:
		return "denied"
	if status_code == 404:
		return "not_found"
	if status_code == 408:
		return "timeout"
	if status_code == 429:
		return "rate_limited"
	if status_code >= 500:
		return "server_error"
	if status_code >= 400:
		return "invalid_request"
	return "unknown"
