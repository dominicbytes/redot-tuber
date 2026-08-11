class_name YouTubeDiscoveryItem
extends RefCounted

var resource_type: String = ""
var id: String = ""
var channel_id: String = ""
var channel_title: String = ""
var title: String = ""
var description: String = ""
var published_at: String = ""
var live_broadcast_content: String = ""
var thumbnail_url: String = ""


static func from_api(source: Dictionary) -> YouTubeDiscoveryItem:
	var value: YouTubeDiscoveryItem = YouTubeDiscoveryItem.new()
	var id_value: Variant = source.get("id", {})
	if id_value is Dictionary:
		value.resource_type = String(id_value.get("kind", "")).trim_prefix("youtube#")
		match value.resource_type:
			"video":
				value.id = String(id_value.get("videoId", ""))
			"channel":
				value.id = String(id_value.get("channelId", ""))
			"playlist":
				value.id = String(id_value.get("playlistId", ""))
	else:
		value.id = String(id_value)
	var snippet: Dictionary = source.get("snippet", {}) if source.get("snippet", {}) is Dictionary else {}
	value.channel_id = String(snippet.get("channelId", ""))
	value.channel_title = String(snippet.get("channelTitle", ""))
	value.title = String(snippet.get("title", ""))
	value.description = String(snippet.get("description", ""))
	value.published_at = String(snippet.get("publishedAt", ""))
	value.live_broadcast_content = String(snippet.get("liveBroadcastContent", ""))
	value.thumbnail_url = _best_thumbnail(snippet.get("thumbnails", {}))
	return value


static func _best_thumbnail(value: Variant) -> String:
	if not value is Dictionary:
		return ""
	for size: String in ["maxres", "standard", "high", "medium", "default"]:
		var candidate: Variant = value.get(size, {})
		if candidate is Dictionary:
			var url: String = String(candidate.get("url", ""))
			if not url.is_empty():
				return url
	return ""
