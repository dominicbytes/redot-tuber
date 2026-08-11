class_name YouTubeCapabilityGate
extends RefCounted

var _capabilities: PackedStringArray = PackedStringArray()
var _authenticated: bool = false


func configure(capabilities: PackedStringArray, authenticated: bool) -> void:
	_capabilities = capabilities.duplicate()
	_capabilities.sort()
	_authenticated = authenticated


func clear() -> void:
	_capabilities.clear()
	_authenticated = false


func has_capability(capability: String) -> bool:
	return _capabilities.has(capability)


func capabilities() -> PackedStringArray:
	return _capabilities.duplicate()


func is_authenticated() -> bool:
	return _authenticated


func require_method(method_id: String, confirmed: bool = false) -> YouTubeApiError:
	var info: YouTubeCapabilityInfo = YouTubeCapabilityRegistry.method_info(method_id)
	if info == null:
		return YouTubeApiError.custom("unsupported", "Unsupported YouTube API method: %s" % method_id)
	if not has_capability(info.capability):
		return YouTubeApiError.custom("capability_denied", "Capability '%s' is required for %s" % [info.capability, method_id])
	if info.requires_oauth and not _authenticated:
		return YouTubeApiError.custom("authorization", "An authorized YouTube account is required for %s" % method_id)
	if info.requires_confirmation and not confirmed:
		return YouTubeApiError.custom("confirmation_required", "Explicit confirmation is required for %s" % method_id)
	return null
