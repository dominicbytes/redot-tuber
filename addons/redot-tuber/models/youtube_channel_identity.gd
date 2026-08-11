class_name YouTubeChannelIdentity
extends RefCounted

var id: String = ""
var title: String = ""
var custom_url: String = ""
var description: String = ""
var thumbnail_url: String = ""


static func from_api(source: Dictionary) -> YouTubeChannelIdentity:
	var value: YouTubeChannelIdentity = YouTubeChannelIdentity.new()
	value.id = String(source.get("id", ""))
	var snippet_value: Variant = source.get("snippet", {})
	if snippet_value is Dictionary:
		value.title = String(snippet_value.get("title", ""))
		value.custom_url = String(snippet_value.get("customUrl", ""))
		value.description = String(snippet_value.get("description", ""))
		var thumbnails: Variant = snippet_value.get("thumbnails", {})
		if thumbnails is Dictionary:
			for size: String in ["high", "medium", "default"]:
				var candidate: Variant = thumbnails.get(size, {})
				if candidate is Dictionary and not String(candidate.get("url", "")).is_empty():
					value.thumbnail_url = String(candidate.get("url", ""))
					break
	return value
