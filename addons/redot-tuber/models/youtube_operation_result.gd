class_name YouTubeOperationResult
extends RefCounted

var method_id: String = ""
var value: Variant = null
var status_code: int = 0
var error: YouTubeApiError = null


func is_success() -> bool:
	return error == null and status_code >= 200 and status_code < 300
