class_name YouTubeSuperChatEvent
extends RefCounted

var id: String = ""
var channel_id: String = ""
var supporter_channel_id: String = ""
var supporter_display_name: String = ""
var supporter_profile_image_url: String = ""
var comment_text: String = ""
var created_at: String = ""
var amount_micros: int = 0
var currency: String = ""
var display_string: String = ""
var message_type: int = 0
var is_super_sticker: bool = false
var sticker_id: String = ""
var sticker_alt_text: String = ""
var sticker_language: String = ""


static func from_api(source: Dictionary) -> YouTubeSuperChatEvent:
	var value: YouTubeSuperChatEvent = YouTubeSuperChatEvent.new()
	value.id = String(source.get("id", ""))
	var snippet: Dictionary = source.get("snippet", {}) if source.get("snippet", {}) is Dictionary else {}
	var supporter: Dictionary = snippet.get("supporterDetails", {}) if snippet.get("supporterDetails", {}) is Dictionary else {}
	var sticker: Dictionary = snippet.get("superStickerMetadata", {}) if snippet.get("superStickerMetadata", {}) is Dictionary else {}
	value.channel_id = String(snippet.get("channelId", ""))
	value.supporter_channel_id = String(supporter.get("channelId", ""))
	value.supporter_display_name = String(supporter.get("displayName", ""))
	value.supporter_profile_image_url = String(supporter.get("profileImageUrl", ""))
	value.comment_text = String(snippet.get("commentText", ""))
	value.created_at = String(snippet.get("createdAt", ""))
	value.amount_micros = int(snippet.get("amountMicros", 0))
	value.currency = String(snippet.get("currency", ""))
	value.display_string = String(snippet.get("displayString", ""))
	value.message_type = int(snippet.get("messageType", 0))
	value.is_super_sticker = bool(snippet.get("isSuperStickerEvent", false))
	value.sticker_id = String(sticker.get("stickerId", ""))
	value.sticker_alt_text = String(sticker.get("altText", ""))
	value.sticker_language = String(sticker.get("language", ""))
	return value
