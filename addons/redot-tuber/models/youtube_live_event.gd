class_name YouTubeLiveEvent
extends RefCounted

var id: String = ""
var source_type: String = ""
var kind: String = "unknown"
var live_chat_id: String = ""
var author_channel_id: String = ""
var published_at: String = ""
var has_display_content: bool = false
var display_message: String = ""
var author: YouTubeLiveAuthor = null
var text_details: YouTubeTextMessageDetails = null
var monetization_details: YouTubeMonetizationDetails = null
var membership_details: YouTubeMembershipDetails = null
var poll_details: YouTubePollDetails = null
var moderation_details: YouTubeModerationDetails = null
var gift_details: YouTubeGiftDetails = null
var details: Dictionary = {}
var raw_payload: Dictionary = {}
var is_unknown: bool = false
var is_terminal: bool = false


func fingerprint() -> String:
	return JSON.stringify(raw_payload)
