class_name YouTubeAuthTokenSet
extends RefCounted

var access_token: String = ""
var refresh_token: String = ""
var token_type: String = "Bearer"
var expires_at_unix: int = 0
var granted_scopes: PackedStringArray = PackedStringArray()


func is_expired(skew_seconds: int = 60) -> bool:
	return access_token.is_empty() or expires_at_unix <= int(Time.get_unix_time_from_system()) + maxi(0, skew_seconds)


func should_refresh(skew_seconds: int = 300) -> bool:
	return is_expired(skew_seconds)


func clear_refresh_token() -> void:
	refresh_token = ""


func clear() -> void:
	access_token = ""
	refresh_token = ""
	token_type = "Bearer"
	expires_at_unix = 0
	granted_scopes.clear()
