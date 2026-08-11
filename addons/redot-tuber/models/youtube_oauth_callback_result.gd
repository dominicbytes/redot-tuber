class_name YouTubeOAuthCallbackResult
extends RefCounted

var code: String = ""
var error: YouTubeApiError = null


func is_success() -> bool:
	return error == null and not code.is_empty()
