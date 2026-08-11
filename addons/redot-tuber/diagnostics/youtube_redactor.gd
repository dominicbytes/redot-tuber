class_name YouTubeRedactor
extends RefCounted

const REDACTED: String = "[REDACTED]"
const SECRET_KEYS: Array[String] = [
	"access_token",
	"authorization",
	"client_secret",
	"code",
	"code_verifier",
	"id_token",
	"key",
	"refresh_token",
	"state",
	"stream_name",
	"streamname",
	"token",
]


func redact_text(value: String) -> String:
	var result: String = value
	var bearer: RegEx = RegEx.new()
	bearer.compile("(?i)(authorization\\s*:\\s*bearer\\s+)[^\\s&]+")
	result = bearer.sub(result, "$1" + REDACTED, true)
	for key: String in SECRET_KEYS:
		var expression: RegEx = RegEx.new()
		expression.compile("(?i)([?&\\s]" + key + "\\s*[=:]\\s*)[^&\\s]+")
		result = expression.sub(result, "$1" + REDACTED, true)
	return result


func redact_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_value: Variant in source:
		var key: String = String(key_value)
		var value: Variant = source[key_value]
		if _is_secret_key(key):
			result[key_value] = REDACTED
		elif value is Dictionary:
			result[key_value] = redact_dictionary(value)
		elif value is Array:
			result[key_value] = _redact_array(value)
		else:
			result[key_value] = value
	return result


func _redact_array(source: Array) -> Array:
	var result: Array = []
	for value: Variant in source:
		if value is Dictionary:
			result.append(redact_dictionary(value))
		elif value is Array:
			result.append(_redact_array(value))
		else:
			result.append(value)
	return result


func _is_secret_key(key: String) -> bool:
	var normalized: String = key.to_lower()
	for secret_key: String in SECRET_KEYS:
		if normalized == secret_key or normalized.ends_with("_" + secret_key):
			return true
	return false
