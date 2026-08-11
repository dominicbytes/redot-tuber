class_name YouTubeScopeRegistry
extends RefCounted

const SCOPE_READONLY: String = "https://www.googleapis.com/auth/youtube.readonly"
const SCOPE_FORCE_SSL: String = "https://www.googleapis.com/auth/youtube.force-ssl"
const SCOPE_MANAGE: String = "https://www.googleapis.com/auth/youtube"

const CAPABILITY_SCOPES: Dictionary = {
	"channel.read": [SCOPE_READONLY],
	"discovery.read": [SCOPE_READONLY],
	"chat.read": [SCOPE_READONLY],
	"chat.write": [SCOPE_FORCE_SSL],
	"poll.manage": [SCOPE_FORCE_SSL],
	"moderation.read": [SCOPE_FORCE_SSL],
	"moderation.delete_message": [SCOPE_FORCE_SSL],
	"moderation.ban": [SCOPE_FORCE_SSL],
	"moderation.unban": [SCOPE_FORCE_SSL],
	"moderation.manage": [SCOPE_FORCE_SSL],
	"broadcast.read": [SCOPE_READONLY],
	"broadcast.manage": [SCOPE_FORCE_SSL],
	"broadcast.bind": [SCOPE_FORCE_SSL],
	"broadcast.transition": [SCOPE_FORCE_SSL],
	"broadcast.cuepoint": [SCOPE_FORCE_SSL],
	"stream.read": [SCOPE_READONLY],
	"stream.manage": [SCOPE_FORCE_SSL],
	"monetization.read": [SCOPE_READONLY],
}


func validate_capabilities(capabilities: PackedStringArray) -> YouTubeApiError:
	if capabilities.is_empty():
		return YouTubeApiError.invalid("At least one YouTube capability is required")
	for capability: String in capabilities:
		if not CAPABILITY_SCOPES.has(capability):
			return YouTubeApiError.invalid("Unknown YouTube capability: %s" % capability)
	return null


func scopes_for(capabilities: PackedStringArray) -> PackedStringArray:
	if validate_capabilities(capabilities) != null:
		return PackedStringArray()
	var unique: Dictionary = {}
	for capability: String in capabilities:
		for scope: String in CAPABILITY_SCOPES[capability]:
			unique[scope] = true
	if unique.has(SCOPE_MANAGE):
		return PackedStringArray([SCOPE_MANAGE])
	if unique.has(SCOPE_FORCE_SSL):
		return PackedStringArray([SCOPE_FORCE_SSL])
	return PackedStringArray([SCOPE_READONLY])


func all_capabilities() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for capability: Variant in CAPABILITY_SCOPES:
		result.append(String(capability))
	result.sort()
	return result
