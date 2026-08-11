class_name YouTubeTextMessageDetails
extends RefCounted

var message_text: String = ""


static func from_api(source: Dictionary) -> YouTubeTextMessageDetails:
	var value: YouTubeTextMessageDetails = YouTubeTextMessageDetails.new()
	value.message_text = String(source.get("messageText", ""))
	return value
