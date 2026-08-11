class_name YouTubeAuthorizationRequest
extends RefCounted

var authorization_url: String = ""
var redirect_uri: String = ""
var expires_at_msec: int = 0
var error: YouTubeApiError = null


func is_valid() -> bool:
	return error == null and not authorization_url.is_empty() and not redirect_uri.is_empty()
