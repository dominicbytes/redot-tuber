class_name YouTubeLiveChatBan
extends RefCounted

var id: String = ""
var live_chat_id: String = ""
var banned_channel_id: String = ""
var ban_type: String = ""
var duration_seconds: int = 0


static func from_api(source: Dictionary) -> YouTubeLiveChatBan:
	var value: YouTubeLiveChatBan = YouTubeLiveChatBan.new()
	value.id = String(source.get("id", ""))
	var snippet: Dictionary = source.get("snippet", {}) if source.get("snippet", {}) is Dictionary else {}
	var user: Dictionary = snippet.get("bannedUserDetails", {}) if snippet.get("bannedUserDetails", {}) is Dictionary else {}
	value.live_chat_id = String(snippet.get("liveChatId", ""))
	value.banned_channel_id = String(user.get("channelId", ""))
	value.ban_type = String(snippet.get("type", ""))
	value.duration_seconds = int(snippet.get("banDurationSeconds", 0))
	return value
