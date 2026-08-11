class_name YouTubeLiveBroadcast
extends RefCounted

var id: String = ""
var title: String = ""
var description: String = ""
var channel_id: String = ""
var published_at: String = ""
var scheduled_start_time: String = ""
var scheduled_end_time: String = ""
var actual_start_time: String = ""
var actual_end_time: String = ""
var live_chat_id: String = ""
var thumbnail_url: String = ""
var life_cycle_status: String = ""
var privacy_status: String = ""
var recording_status: String = ""
var made_for_kids: bool = false
var self_declared_made_for_kids: bool = false
var bound_stream_id: String = ""
var total_chat_count: int = 0
var snippet_details: Dictionary = {}
var status_details: Dictionary = {}
var content_details: Dictionary = {}
var monetization_details: Dictionary = {}


static func from_api(source: Dictionary) -> YouTubeLiveBroadcast:
	var value: YouTubeLiveBroadcast = YouTubeLiveBroadcast.new()
	value.id = String(source.get("id", ""))
	value.snippet_details = _copy_section(source, "snippet")
	value.status_details = _copy_section(source, "status")
	value.content_details = _copy_section(source, "contentDetails")
	value.monetization_details = _copy_section(source, "monetizationDetails")
	value.title = String(value.snippet_details.get("title", ""))
	value.description = String(value.snippet_details.get("description", ""))
	value.channel_id = String(value.snippet_details.get("channelId", ""))
	value.published_at = String(value.snippet_details.get("publishedAt", ""))
	value.scheduled_start_time = String(value.snippet_details.get("scheduledStartTime", ""))
	value.scheduled_end_time = String(value.snippet_details.get("scheduledEndTime", ""))
	value.actual_start_time = String(value.snippet_details.get("actualStartTime", ""))
	value.actual_end_time = String(value.snippet_details.get("actualEndTime", ""))
	value.live_chat_id = String(value.snippet_details.get("liveChatId", ""))
	value.thumbnail_url = _best_thumbnail(value.snippet_details.get("thumbnails", {}))
	value.life_cycle_status = String(value.status_details.get("lifeCycleStatus", ""))
	value.privacy_status = String(value.status_details.get("privacyStatus", ""))
	value.recording_status = String(value.status_details.get("recordingStatus", ""))
	value.made_for_kids = bool(value.status_details.get("madeForKids", false))
	value.self_declared_made_for_kids = bool(value.status_details.get("selfDeclaredMadeForKids", false))
	value.bound_stream_id = String(value.content_details.get("boundStreamId", ""))
	var statistics: Dictionary = _copy_section(source, "statistics")
	value.total_chat_count = int(statistics.get("totalChatCount", 0))
	return value


func to_insert_body() -> Dictionary:
	var snippet: Dictionary = snippet_details.duplicate(true)
	snippet["title"] = title
	snippet["scheduledStartTime"] = scheduled_start_time
	if not description.is_empty():
		snippet["description"] = description
	if not scheduled_end_time.is_empty():
		snippet["scheduledEndTime"] = scheduled_end_time
	var status: Dictionary = status_details.duplicate(true)
	status["privacyStatus"] = privacy_status
	status["selfDeclaredMadeForKids"] = self_declared_made_for_kids
	var body: Dictionary = {"snippet": snippet, "status": status}
	if not content_details.is_empty():
		body["contentDetails"] = content_details.duplicate(true)
	return body


func to_update_body(parts: PackedStringArray) -> Dictionary:
	var body: Dictionary = {"id": id}
	if parts.has("snippet"):
		var snippet: Dictionary = snippet_details.duplicate(true)
		if not title.is_empty():
			snippet["title"] = title
		if not description.is_empty() or snippet.has("description"):
			snippet["description"] = description
		if not scheduled_start_time.is_empty():
			snippet["scheduledStartTime"] = scheduled_start_time
		if not scheduled_end_time.is_empty() or snippet.has("scheduledEndTime"):
			snippet["scheduledEndTime"] = scheduled_end_time
		body["snippet"] = snippet
	if parts.has("status"):
		var status: Dictionary = status_details.duplicate(true)
		if not privacy_status.is_empty():
			status["privacyStatus"] = privacy_status
		status["selfDeclaredMadeForKids"] = self_declared_made_for_kids
		body["status"] = status
	if parts.has("contentDetails"):
		body["contentDetails"] = content_details.duplicate(true)
	if parts.has("monetizationDetails"):
		body["monetizationDetails"] = monetization_details.duplicate(true)
	return body


static func _copy_section(source: Dictionary, key: String) -> Dictionary:
	var candidate: Variant = source.get(key, {})
	return candidate.duplicate(true) if candidate is Dictionary else {}


static func _best_thumbnail(value: Variant) -> String:
	if not value is Dictionary:
		return ""
	for size: String in ["maxres", "standard", "high", "medium", "default"]:
		var candidate: Variant = value.get(size, {})
		if candidate is Dictionary and not String(candidate.get("url", "")).is_empty():
			return String(candidate.get("url", ""))
	return ""
