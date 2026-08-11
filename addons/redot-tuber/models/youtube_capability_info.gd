class_name YouTubeCapabilityInfo
extends RefCounted

var method_id: String = ""
var capability: String = ""
var required_scope: String = ""
var quota_units: int = 0
var quota_bucket: String = "youtube_data"
var requires_oauth: bool = false
var is_write: bool = false
var requires_confirmation: bool = false
var availability_note: String = ""


static func from_definition(id: String, source: Dictionary) -> YouTubeCapabilityInfo:
	var value: YouTubeCapabilityInfo = YouTubeCapabilityInfo.new()
	value.method_id = id
	value.capability = String(source.get("capability", ""))
	value.required_scope = String(source.get("scope", ""))
	value.quota_units = int(source.get("quota_units", 0))
	value.quota_bucket = String(source.get("quota_bucket", "youtube_data"))
	value.requires_oauth = bool(source.get("oauth", false))
	value.is_write = bool(source.get("write", false))
	value.requires_confirmation = bool(source.get("confirm", false))
	value.availability_note = String(source.get("availability", "documented"))
	return value
