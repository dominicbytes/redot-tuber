class_name YouTubeTokenOperationResult
extends RefCounted

var token: YouTubeAuthTokenSet = null
var revoked: bool = false
var error: YouTubeApiError = null


func is_success() -> bool:
	return error == null and (token != null or revoked)
