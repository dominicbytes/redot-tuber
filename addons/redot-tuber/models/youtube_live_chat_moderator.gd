class_name YouTubeLiveChatModerator
extends RefCounted

var id: String = ""
var live_chat_id: String = ""
var channel_id: String = ""
var channel_url: String = ""
var display_name: String = ""
var profile_image_url: String = ""


static func from_api(source: Dictionary) -> YouTubeLiveChatModerator:
	var value: YouTubeLiveChatModerator = YouTubeLiveChatModerator.new()
	value.id = String(source.get("id", ""))
	var snippet: Dictionary = source.get("snippet", {}) if source.get("snippet", {}) is Dictionary else {}
	var details: Dictionary = snippet.get("moderatorDetails", {}) if snippet.get("moderatorDetails", {}) is Dictionary else {}
	value.live_chat_id = String(snippet.get("liveChatId", ""))
	value.channel_id = String(details.get("channelId", ""))
	value.channel_url = String(details.get("channelUrl", ""))
	value.display_name = String(details.get("displayName", ""))
	value.profile_image_url = String(details.get("profileImageUrl", ""))
	return value
