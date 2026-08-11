class_name YouTubeLiveAuthor
extends RefCounted

var channel_id: String = ""
var channel_url: String = ""
var display_name: String = ""
var profile_image_url: String = ""
var is_verified: bool = false
var is_chat_owner: bool = false
var is_chat_sponsor: bool = false
var is_chat_moderator: bool = false


static func from_api(source: Dictionary) -> YouTubeLiveAuthor:
	var value: YouTubeLiveAuthor = YouTubeLiveAuthor.new()
	value.channel_id = String(source.get("channelId", ""))
	value.channel_url = String(source.get("channelUrl", ""))
	value.display_name = String(source.get("displayName", ""))
	value.profile_image_url = String(source.get("profileImageUrl", ""))
	value.is_verified = bool(source.get("isVerified", false))
	value.is_chat_owner = bool(source.get("isChatOwner", false))
	value.is_chat_sponsor = bool(source.get("isChatSponsor", false))
	value.is_chat_moderator = bool(source.get("isChatModerator", false))
	return value
