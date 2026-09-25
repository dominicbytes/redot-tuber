class_name YouTubeMonetizationDetails
extends RefCounted

var event_type: String = ""
var amount_micros: int = 0
var amount_micros_exact: String = "0" # Protobuf uint64 can exceed Redot's signed int.
var currency: String = ""
var amount_display_string: String = ""
var user_comment: String = ""
var tier: int = 0
var sticker_id: String = ""
var sticker_alt_text: String = ""
var sticker_language: String = ""


static func from_api(source: Dictionary, source_type: String) -> YouTubeMonetizationDetails:
	var value: YouTubeMonetizationDetails = YouTubeMonetizationDetails.new()
	value.event_type = source_type
	value.amount_micros_exact = String(source.get("amountMicros", 0))
	if value.amount_micros_exact.length() < 19 or (value.amount_micros_exact.length() == 19 and value.amount_micros_exact <= "9223372036854775807"):
		value.amount_micros = int(value.amount_micros_exact)
	value.currency = String(source.get("currency", ""))
	value.amount_display_string = String(source.get("amountDisplayString", ""))
	value.user_comment = String(source.get("userComment", ""))
	value.tier = int(source.get("tier", 0))
	var sticker: Dictionary = source.get("superStickerMetadata", {}) if source.get("superStickerMetadata", {}) is Dictionary else {}
	value.sticker_id = String(sticker.get("stickerId", ""))
	value.sticker_alt_text = String(sticker.get("altText", ""))
	value.sticker_language = String(sticker.get("language", ""))
	return value
