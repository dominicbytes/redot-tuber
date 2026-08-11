class_name YouTubeLiveStream
extends RefCounted

var id: String = ""
var title: String = ""
var description: String = ""
var channel_id: String = ""
var published_at: String = ""
var ingestion_type: String = ""
var resolution: String = ""
var frame_rate: String = ""
var ingestion_address: String = ""
var backup_ingestion_address: String = ""
var stream_name: String = ""
var stream_status: String = ""
var health_status: String = ""
var health_issues: Array[Dictionary] = []
var is_reusable: bool = false
var snippet_details: Dictionary = {}
var cdn_details: Dictionary = {}
var status_details: Dictionary = {}
var content_details: Dictionary = {}


static func from_api(source: Dictionary) -> YouTubeLiveStream:
	var value: YouTubeLiveStream = YouTubeLiveStream.new()
	value.id = String(source.get("id", ""))
	value.snippet_details = _copy_section(source, "snippet")
	value.cdn_details = _copy_section(source, "cdn")
	value.status_details = _copy_section(source, "status")
	value.content_details = _copy_section(source, "contentDetails")
	value.title = String(value.snippet_details.get("title", ""))
	value.description = String(value.snippet_details.get("description", ""))
	value.channel_id = String(value.snippet_details.get("channelId", ""))
	value.published_at = String(value.snippet_details.get("publishedAt", ""))
	value.ingestion_type = String(value.cdn_details.get("ingestionType", ""))
	value.resolution = String(value.cdn_details.get("resolution", ""))
	value.frame_rate = String(value.cdn_details.get("frameRate", ""))
	var ingestion: Dictionary = value.cdn_details.get("ingestionInfo", {}) if value.cdn_details.get("ingestionInfo", {}) is Dictionary else {}
	value.stream_name = String(ingestion.get("streamName", ""))
	value.ingestion_address = String(ingestion.get("ingestionAddress", ""))
	value.backup_ingestion_address = String(ingestion.get("backupIngestionAddress", ""))
	value.stream_status = String(value.status_details.get("streamStatus", ""))
	var health: Dictionary = value.status_details.get("healthStatus", {}) if value.status_details.get("healthStatus", {}) is Dictionary else {}
	value.health_status = String(health.get("status", ""))
	var issues: Variant = health.get("configurationIssues", [])
	if issues is Array:
		for issue: Variant in issues:
			if issue is Dictionary:
				value.health_issues.append(issue.duplicate(true))
	value.is_reusable = bool(value.content_details.get("isReusable", false))
	return value


func to_insert_body() -> Dictionary:
	var snippet: Dictionary = snippet_details.duplicate(true)
	snippet["title"] = title
	if not description.is_empty():
		snippet["description"] = description
	var cdn: Dictionary = cdn_details.duplicate(true)
	cdn.erase("ingestionInfo")
	cdn["ingestionType"] = ingestion_type
	cdn["resolution"] = resolution
	cdn["frameRate"] = frame_rate
	var body: Dictionary = {"snippet": snippet, "cdn": cdn}
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
		body["snippet"] = snippet
	if parts.has("cdn"):
		var cdn: Dictionary = cdn_details.duplicate(true)
		cdn.erase("ingestionInfo")
		if not ingestion_type.is_empty():
			cdn["ingestionType"] = ingestion_type
		if not resolution.is_empty():
			cdn["resolution"] = resolution
		if not frame_rate.is_empty():
			cdn["frameRate"] = frame_rate
		body["cdn"] = cdn
	if parts.has("contentDetails"):
		body["contentDetails"] = content_details.duplicate(true)
	return body


func clear_sensitive() -> void:
	stream_name = ""
	var ingestion: Variant = cdn_details.get("ingestionInfo", {})
	if ingestion is Dictionary:
		ingestion["streamName"] = ""


static func _copy_section(source: Dictionary, key: String) -> Dictionary:
	var candidate: Variant = source.get(key, {})
	return candidate.duplicate(true) if candidate is Dictionary else {}
