class_name YouTubeQuotaLedger
extends RefCounted

var _daily_budget_by_bucket: Dictionary = {}
var _total_units: int = 0
var _units_by_method: Dictionary = {}
var _counts_by_method: Dictionary = {}
var _status_by_method: Dictionary = {}
var _bucket_by_method: Dictionary = {}
var _units_by_bucket: Dictionary = {}


func _init(endpoint_contracts: Array = [], daily_budget: int = 10000, bucket_budgets: Dictionary = {}) -> void:
	_daily_budget_by_bucket = {
		"youtube_data": maxi(0, daily_budget),
		"search_queries": maxi(0, int(bucket_budgets.get("search_queries", 100))),
	}
	for bucket: Variant in bucket_budgets:
		_daily_budget_by_bucket[String(bucket)] = maxi(0, int(bucket_budgets[bucket]))
	for endpoint_value: Variant in endpoint_contracts:
		if not endpoint_value is Dictionary:
			continue
		var endpoint: Dictionary = endpoint_value
		var method_id: String = String(endpoint.get("id", ""))
		if method_id.is_empty():
			continue
		_units_by_method[method_id] = int(endpoint.get("quota_units", 0))
		_status_by_method[method_id] = String(endpoint.get("quota_status", "unknown"))
		_bucket_by_method[method_id] = String(endpoint.get("quota_bucket", "youtube_data"))


func record_request(method_id: String, _recorded_at_msec: int) -> String:
	if not _units_by_method.has(method_id):
		return "unclassified quota method: %s" % method_id
	var units: int = int(_units_by_method[method_id])
	if units <= 0:
		return "invalid quota units for method: %s" % method_id
	var bucket: String = String(_bucket_by_method.get(method_id, "youtube_data"))
	if bucket_remaining_units(bucket) < units:
		return "quota budget exhausted for bucket: %s" % bucket
	_total_units += units
	_units_by_bucket[bucket] = int(_units_by_bucket.get(bucket, 0)) + units
	_counts_by_method[method_id] = int(_counts_by_method.get(method_id, 0)) + 1
	return ""


func total_units() -> int:
	return _total_units


func remaining_units() -> int:
	return bucket_remaining_units("youtube_data")


func bucket_units(bucket: String) -> int:
	return int(_units_by_bucket.get(bucket, 0))


func bucket_remaining_units(bucket: String) -> int:
	if not _daily_budget_by_bucket.has(bucket):
		return 0
	return maxi(0, int(_daily_budget_by_bucket[bucket]) - bucket_units(bucket))


func quota_bucket(method_id: String) -> String:
	return String(_bucket_by_method.get(method_id, "unclassified"))


func set_bucket_budget(bucket: String, units: int) -> void:
	if not bucket.is_empty():
		_daily_budget_by_bucket[bucket] = maxi(0, units)


func request_count(method_id: String) -> int:
	return int(_counts_by_method.get(method_id, 0))


func would_exceed(method_id: String) -> bool:
	if not _units_by_method.has(method_id):
		return true
	var bucket: String = String(_bucket_by_method.get(method_id, "youtube_data"))
	return bucket_remaining_units(bucket) < int(_units_by_method[method_id])


func quota_status(method_id: String) -> String:
	return String(_status_by_method.get(method_id, "unclassified"))


func reset() -> void:
	_total_units = 0
	_counts_by_method.clear()
	_units_by_bucket.clear()
