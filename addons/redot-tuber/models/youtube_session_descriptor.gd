class_name YouTubeSessionDescriptor
extends RefCounted

const SCHEMA_VERSION: int = 1

var session_slot: String = ""
var credential_target: String = ""
var channel_id: String = ""
var channel_title: String = ""
var channel_custom_url: String = ""
var granted_capabilities: PackedStringArray = PackedStringArray()
var granted_scopes: PackedStringArray = PackedStringArray()
var saved_at_unix: int = 0


func to_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"session_slot": session_slot,
		"credential_target": credential_target,
		"channel": {
			"id": channel_id,
			"title": channel_title,
			"custom_url": channel_custom_url,
		},
		"granted_capabilities": Array(granted_capabilities),
		"granted_scopes": Array(granted_scopes),
		"saved_at_unix": saved_at_unix if saved_at_unix > 0 else int(Time.get_unix_time_from_system()),
	}


static func from_dictionary(source: Dictionary) -> YouTubeSessionDescriptor:
	if int(source.get("schema_version", 0)) != SCHEMA_VERSION:
		return null
	var value: YouTubeSessionDescriptor = YouTubeSessionDescriptor.new()
	value.session_slot = String(source.get("session_slot", ""))
	value.credential_target = String(source.get("credential_target", ""))
	var channel_value: Variant = source.get("channel", {})
	if channel_value is Dictionary:
		value.channel_id = String(channel_value.get("id", ""))
		value.channel_title = String(channel_value.get("title", ""))
		value.channel_custom_url = String(channel_value.get("custom_url", ""))
	value.granted_capabilities = _to_string_array(source.get("granted_capabilities", []))
	value.granted_scopes = _to_string_array(source.get("granted_scopes", []))
	value.saved_at_unix = int(source.get("saved_at_unix", 0))
	return value


static func _to_string_array(source: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if source is Array:
		for item: Variant in source:
			result.append(String(item))
	return result
