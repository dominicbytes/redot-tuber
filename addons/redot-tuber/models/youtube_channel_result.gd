class_name YouTubeChannelResult
extends RefCounted

var channel: YouTubeChannelIdentity = null
var error: YouTubeApiError = null


func is_success() -> bool:
	return channel != null and error == null
