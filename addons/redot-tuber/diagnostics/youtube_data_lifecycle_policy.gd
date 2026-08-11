class_name YouTubeDataLifecyclePolicy
extends RefCounted

const REQUIRED_FIELDS: PackedStringArray = ["id", "secret", "storage", "retention", "clear_trigger"]

var _items: Dictionary = {}


func _init(contract_items: Array = []) -> void:
	for item_value: Variant in contract_items:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var item_id: String = String(item.get("id", ""))
		if not item_id.is_empty():
			_items[item_id] = item.duplicate(true)


func validate_contract() -> PackedStringArray:
	var errors: PackedStringArray = []
	for item_id: String in _items:
		var item: Dictionary = _items[item_id]
		for field: String in REQUIRED_FIELDS:
			if not item.has(field):
				errors.append("%s is missing %s" % [item_id, field])
		if bool(item.get("secret", false)) and not String(item.get("storage", "")).contains("memory") and not String(item.get("storage", "")).contains("vault"):
			errors.append("%s uses an invalid secret storage class" % item_id)
	return errors


func has_item(item_id: String) -> bool:
	return _items.has(item_id)


func storage_for(item_id: String) -> String:
	if not _items.has(item_id):
		return ""
	return String(_items[item_id].get("storage", ""))


func clear_trigger_for(item_id: String) -> String:
	if not _items.has(item_id):
		return ""
	return String(_items[item_id].get("clear_trigger", ""))


func may_write_plaintext(item_id: String) -> bool:
	if not _items.has(item_id):
		return false
	var item: Dictionary = _items[item_id]
	if bool(item.get("secret", false)):
		return false
	return String(item.get("storage", "")).begins_with("user_directory")
