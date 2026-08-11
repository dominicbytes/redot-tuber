class_name YouTubeLiveEventNormalizer
extends RefCounted

const YouTubeLiveEventClass = preload("res://addons/redot-tuber/models/youtube_live_event.gd")
const AuthorClass = preload("res://addons/redot-tuber/models/youtube_live_author.gd")
const TextDetailsClass = preload("res://addons/redot-tuber/models/youtube_text_message_details.gd")
const MonetizationDetailsClass = preload("res://addons/redot-tuber/models/youtube_monetization_details.gd")
const MembershipDetailsClass = preload("res://addons/redot-tuber/models/youtube_membership_details.gd")
const PollDetailsClass = preload("res://addons/redot-tuber/models/youtube_poll_details.gd")
const ModerationDetailsClass = preload("res://addons/redot-tuber/models/youtube_moderation_details.gd")
const GiftDetailsClass = preload("res://addons/redot-tuber/models/youtube_gift_details.gd")

const TYPE_TO_KIND: Dictionary = {
	"chatEndedEvent": "terminal",
	"sponsorOnlyModeEndedEvent": "system",
	"sponsorOnlyModeStartedEvent": "system",
	"newSponsorEvent": "membership",
	"memberMilestoneChatEvent": "membership",
	"superChatEvent": "super_chat",
	"superStickerEvent": "super_sticker",
	"textMessageEvent": "text_message",
	"tombstone": "deletion",
	"userBannedEvent": "moderation",
	"membershipGiftingEvent": "membership_gifting",
	"giftMembershipReceivedEvent": "gift_membership_received",
	"pollEvent": "poll",
	"pollDetails": "poll",
	"giftEvent": "gift",
}

const TYPE_DETAIL_KEYS: Dictionary = {
	"newSponsorEvent": "newSponsorDetails",
	"memberMilestoneChatEvent": "memberMilestoneChatDetails",
	"superChatEvent": "superChatDetails",
	"superStickerEvent": "superStickerDetails",
	"textMessageEvent": "textMessageDetails",
	"userBannedEvent": "userBannedDetails",
	"membershipGiftingEvent": "membershipGiftingDetails",
	"giftMembershipReceivedEvent": "giftMembershipReceivedDetails",
	"pollEvent": "pollDetails",
	"pollDetails": "pollDetails",
	"giftEvent": "giftEventDetails",
}


func normalize(raw_message: Variant) -> RefCounted:
	if not raw_message is Dictionary:
		return null
	var raw: Dictionary = raw_message
	var snippet_value: Variant = raw.get("snippet", {})
	if not snippet_value is Dictionary:
		return null
	var snippet: Dictionary = snippet_value
	var source_type: String = String(snippet.get("type", ""))
	if source_type.is_empty():
		return null

	var event: Variant = YouTubeLiveEventClass.new()
	event.id = String(raw.get("id", ""))
	event.source_type = source_type
	event.kind = String(TYPE_TO_KIND.get(source_type, "unknown"))
	event.live_chat_id = String(snippet.get("liveChatId", ""))
	event.author_channel_id = String(snippet.get("authorChannelId", ""))
	event.published_at = String(snippet.get("publishedAt", ""))
	event.has_display_content = bool(snippet.get("hasDisplayContent", false))
	event.display_message = String(snippet.get("displayMessage", ""))
	event.is_unknown = not TYPE_TO_KIND.has(source_type)
	event.is_terminal = source_type == "chatEndedEvent"
	var author_value: Variant = raw.get("authorDetails", {})
	if author_value is Dictionary:
		event.author = AuthorClass.from_api(author_value)
	var detail_key: String = String(TYPE_DETAIL_KEYS.get(source_type, ""))
	var detail_value: Variant = snippet.get(detail_key, {}) if not detail_key.is_empty() else {}
	if detail_value is Dictionary:
		event.details = detail_value.duplicate(true)
		match source_type:
			"textMessageEvent":
				event.text_details = TextDetailsClass.from_api(detail_value)
			"superChatEvent", "superStickerEvent":
				event.monetization_details = MonetizationDetailsClass.from_api(detail_value, source_type)
			"newSponsorEvent", "memberMilestoneChatEvent", "membershipGiftingEvent", "giftMembershipReceivedEvent":
				event.membership_details = MembershipDetailsClass.from_api(detail_value, source_type)
			"pollEvent", "pollDetails":
				event.poll_details = PollDetailsClass.from_api(detail_value)
			"userBannedEvent":
				event.moderation_details = ModerationDetailsClass.from_api(detail_value)
			"giftEvent":
				event.gift_details = GiftDetailsClass.from_api(detail_value)
	event.raw_payload = raw.duplicate(true)
	return event
