class_name YouTubeGiftDetails
extends RefCounted

var jewels_amount: int = 0
var gift_name: String = ""
var gift_url: String = ""
var duration_seconds: int = 0
var duration_nanoseconds: int = 0
var has_visual_effect: bool = false
var combo_count: int = 0
var alt_text: String = ""
var language: String = ""


static func from_api(source: Dictionary) -> YouTubeGiftDetails:
	var value: YouTubeGiftDetails = YouTubeGiftDetails.new()
	var metadata: Dictionary = source.get("giftMetadata", {}) if source.get("giftMetadata", {}) is Dictionary else {}
	var duration: Dictionary = metadata.get("giftDuration", {}) if metadata.get("giftDuration", {}) is Dictionary else {}
	value.jewels_amount = int(metadata.get("jewelsAmount", 0))
	value.gift_name = String(metadata.get("giftName", ""))
	value.gift_url = String(metadata.get("giftUrl", ""))
	value.duration_seconds = int(duration.get("seconds", 0))
	value.duration_nanoseconds = int(duration.get("nanos", 0))
	value.has_visual_effect = bool(metadata.get("hasVisualEffect", false))
	value.combo_count = int(metadata.get("comboCount", 0))
	value.alt_text = String(metadata.get("altText", ""))
	value.language = String(metadata.get("language", ""))
	return value
