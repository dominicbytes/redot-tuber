class_name YouTubeSessionSlotRegistry
extends RefCounted

static var _owners: Dictionary = {}


static func acquire(qualified_slot: String, owner: Object) -> YouTubeApiError:
	_cleanup()
	if qualified_slot.is_empty() or owner == null:
		return YouTubeApiError.invalid("A qualified session slot and owner are required")
	if _owners.has(qualified_slot):
		var existing: Object = (_owners[qualified_slot] as WeakRef).get_ref()
		if existing != null and existing != owner:
			return YouTubeApiError.invalid("Session slot is already active in another YouTubeLiveClient")
	_owners[qualified_slot] = weakref(owner)
	return null


static func release(qualified_slot: String, owner: Object) -> void:
	if not _owners.has(qualified_slot):
		return
	var existing: Object = (_owners[qualified_slot] as WeakRef).get_ref()
	if existing == null or existing == owner:
		_owners.erase(qualified_slot)


static func clear_for_tests() -> void:
	_owners.clear()


static func _cleanup() -> void:
	var expired: PackedStringArray = PackedStringArray()
	for slot: Variant in _owners:
		if (_owners[slot] as WeakRef).get_ref() == null:
			expired.append(String(slot))
	for slot: String in expired:
		_owners.erase(slot)
