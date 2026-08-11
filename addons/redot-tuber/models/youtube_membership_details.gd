class_name YouTubeMembershipDetails
extends RefCounted

var event_type: String = ""
var user_comment: String = ""
var member_month: int = 0
var member_level_name: String = ""
var is_upgrade: bool = false
var gift_memberships_count: int = 0
var gifter_channel_id: String = ""
var associated_gifting_message_id: String = ""


static func from_api(source: Dictionary, source_type: String) -> YouTubeMembershipDetails:
	var value: YouTubeMembershipDetails = YouTubeMembershipDetails.new()
	value.event_type = source_type
	value.user_comment = String(source.get("userComment", ""))
	value.member_month = int(source.get("memberMonth", 0))
	value.member_level_name = String(source.get("memberLevelName", source.get("giftMembershipsLevelName", "")))
	value.is_upgrade = bool(source.get("isUpgrade", false))
	value.gift_memberships_count = int(source.get("giftMembershipsCount", 0))
	value.gifter_channel_id = String(source.get("gifterChannelId", ""))
	value.associated_gifting_message_id = String(source.get("associatedMembershipGiftingMessageId", ""))
	return value
