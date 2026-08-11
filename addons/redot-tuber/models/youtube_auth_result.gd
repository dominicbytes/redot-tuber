class_name YouTubeAuthResult
extends RefCounted

var channel: YouTubeChannelIdentity = null
var granted_capabilities: PackedStringArray = PackedStringArray()
var granted_scopes: PackedStringArray = PackedStringArray()
var restored: bool = false
var error: YouTubeApiError = null


func is_success() -> bool:
	return channel != null and error == null
