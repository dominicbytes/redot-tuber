class_name YouTubeModerationDetails
extends RefCounted

var banned_channel_id: String = ""
var banned_channel_url: String = ""
var banned_display_name: String = ""
var banned_profile_image_url: String = ""
var ban_type: String = ""
var ban_duration_seconds: int = 0
var ban_duration_seconds_exact: String = "0" # Protobuf uint64 can exceed Redot's signed int.


static func from_api(source: Dictionary) -> YouTubeModerationDetails:
	var value: YouTubeModerationDetails = YouTubeModerationDetails.new()
	var user: Dictionary = source.get("bannedUserDetails", {}) if source.get("bannedUserDetails", {}) is Dictionary else {}
	value.banned_channel_id = String(user.get("channelId", ""))
	value.banned_channel_url = String(user.get("channelUrl", ""))
	value.banned_display_name = String(user.get("displayName", ""))
	value.banned_profile_image_url = String(user.get("profileImageUrl", ""))
	value.ban_type = String(source.get("banType", ""))
	value.ban_duration_seconds_exact = String(source.get("banDurationSeconds", 0))
	if value.ban_duration_seconds_exact.length() < 19 or (value.ban_duration_seconds_exact.length() == 19 and value.ban_duration_seconds_exact <= "9223372036854775807"):
		value.ban_duration_seconds = int(value.ban_duration_seconds_exact)
	return value
