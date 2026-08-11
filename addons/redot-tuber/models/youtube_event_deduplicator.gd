class_name YouTubeEventDeduplicator
extends RefCounted

var _max_entries: int
var _fingerprints: Dictionary = {}
var _insertion_order: Array[String] = []


func _init(max_entries: int = 5000) -> void:
	_max_entries = maxi(1, max_entries)


func classify(event: Variant) -> String:
	if event == null or event.id.is_empty():
		return "new"
	var fingerprint: String = event.fingerprint()
	if not _fingerprints.has(event.id):
		_fingerprints[event.id] = fingerprint
		_insertion_order.append(event.id)
		_evict_if_needed()
		return "new"
	if String(_fingerprints[event.id]) == fingerprint:
		return "duplicate"
	_fingerprints[event.id] = fingerprint
	return "update"


func clear() -> void:
	_fingerprints.clear()
	_insertion_order.clear()


func size() -> int:
	return _fingerprints.size()


func _evict_if_needed() -> void:
	while _insertion_order.size() > _max_entries:
		var oldest_id: String = _insertion_order.pop_front()
		_fingerprints.erase(oldest_id)
