extends SceneTree

const ADDON_ROOT: String = "res://addons/redot-tuber"
const CONTRACT_FIXTURE: String = ADDON_ROOT + "/contracts/youtube_api_contract.json"
const EVENT_FIXTURE: String = ADDON_ROOT + "/tests/fixtures/live_chat_events.json"
const STREAM_FIXTURE: String = ADDON_ROOT + "/tests/fixtures/live_chat_stream.json"

var _failures: PackedStringArray = []
var _checks: int = 0


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var components: Dictionary = _load_components()
	if components.is_empty():
		_finish()
		return

	_test_contracts(components)
	_test_json_stream_framer(components)
	_test_poll_scheduler(components)
	_test_cancellation_token(components)
	_test_event_normalization(components)
	_test_quota_ledger(components)
	_test_data_lifecycle(components)
	_finish()


func _load_components() -> Dictionary:
	var paths: Dictionary = {
		"framer": ADDON_ROOT + "/transport/json_stream_framer.gd",
		"scheduler": ADDON_ROOT + "/transport/live_chat_poll_scheduler.gd",
		"cancellation": ADDON_ROOT + "/transport/cancellation_token.gd",
		"normalizer": ADDON_ROOT + "/models/youtube_live_event_normalizer.gd",
		"deduplicator": ADDON_ROOT + "/models/youtube_event_deduplicator.gd",
		"quota": ADDON_ROOT + "/diagnostics/youtube_quota_ledger.gd",
		"lifecycle": ADDON_ROOT + "/diagnostics/youtube_data_lifecycle_policy.gd",
	}
	var loaded: Dictionary = {}
	for component_name: String in paths:
		var path: String = paths[component_name]
		var script: Script = load(path)
		_check(script != null and script.can_instantiate(), "component loads: %s" % path)
		if script == null or not script.can_instantiate():
			return {}
		loaded[component_name] = script
	return loaded


func _test_contracts(components: Dictionary) -> void:
	var contract: Dictionary = _load_json_object(CONTRACT_FIXTURE)
	_check(not contract.is_empty(), "contract fixture parses")
	_check(contract.get("schema_version", 0) == 2, "contract schema is versioned")

	var endpoints: Array = contract.get("endpoints", [])
	var endpoint_ids: Dictionary = {}
	for endpoint: Variant in endpoints:
		if endpoint is Dictionary:
			endpoint_ids[endpoint.get("id", "")] = true
			_check(int(endpoint.get("quota_units", 0)) > 0, "endpoint has positive quota classification: %s" % endpoint.get("id", "missing"))
			_check(String(endpoint.get("source", "")).begins_with("https://developers.google.com/"), "endpoint has official source: %s" % endpoint.get("id", "missing"))
	for required_id: String in ["videos.list", "liveChatMessages.list", "liveChatMessages.streamList", "liveChatMessages.insert", "liveChatBans.insert", "liveChatModerators.list", "liveBroadcasts.transition", "liveStreams.insert"]:
		_check(endpoint_ids.has(required_id), "required endpoint contract exists: %s" % required_id)

	var lifecycle_policy: Variant = components.lifecycle.new(contract.get("data_lifecycle", []))
	_check(lifecycle_policy.validate_contract().is_empty(), "data lifecycle contract is complete")


func _test_json_stream_framer(components: Dictionary) -> void:
	var fixture: Dictionary = _load_json_object(STREAM_FIXTURE)
	var responses: Array = fixture.get("responses", [])
	var encoded_responses: PackedStringArray = []
	for response: Variant in responses:
		encoded_responses.append(JSON.stringify(response))
	var wire: PackedByteArray = ("\n".join(encoded_responses) + "\n").to_utf8_buffer()

	var framer: Variant = components.framer.new(1024 * 1024)
	var frames: Array[Dictionary] = []
	for byte_index: int in wire.size():
		var chunk: PackedByteArray = wire.slice(byte_index, byte_index + 1)
		frames.append_array(framer.push_chunk(chunk))
	_check(frames.size() == responses.size(), "one-byte chunks produce every stream response")
	_check(framer.buffered_byte_count() == 0, "framer drains complete stream")
	_check(framer.last_error().is_empty(), "valid one-byte chunks have no framing error")
	if frames.size() == responses.size():
		_check(frames[0].get("nextPageToken", "") == "fixture-token-1", "first continuation token preserved")
		_check(frames[2].get("offlineAt", "") != "", "offline terminal marker preserved")

	framer.reset()
	var all_at_once: Array[Dictionary] = framer.push_chunk(wire)
	_check(all_at_once.size() == responses.size(), "one chunk may contain multiple response frames")

	var bounded: Variant = components.framer.new(64)
	var oversized: PackedByteArray = ("{\"unterminated\":\"" + "x".repeat(80)).to_utf8_buffer()
	_check(bounded.push_chunk(oversized).is_empty(), "oversized partial frame is rejected")
	_check(not bounded.last_error().is_empty(), "oversized partial frame reports an error")
	_check(bounded.buffered_byte_count() == 0, "overflow clears buffered bytes")


func _test_poll_scheduler(components: Dictionary) -> void:
	var scheduler: Variant = components.scheduler.new()
	var response: Dictionary = {
		"nextPageToken": "fixture-token-2",
		"pollingIntervalMillis": 2500,
		"items": [],
	}
	_check(scheduler.accept_response(response, 1000).is_empty(), "poll response is accepted")
	_check(scheduler.next_page_token() == "fixture-token-2", "poll continuation is stored")
	_check(not scheduler.can_poll(3499), "poll cannot run before server interval")
	_check(scheduler.can_poll(3500), "poll can run at server interval")
	_check(scheduler.remaining_msec(2000) == 1500, "remaining poll interval is deterministic")

	var terminal: Dictionary = response.duplicate(true)
	terminal["offlineAt"] = "2026-08-10T12:00:03Z"
	scheduler.accept_response(terminal, 3500)
	_check(scheduler.is_terminal(), "offlineAt makes polling terminal")
	_check(not scheduler.can_poll(999999), "terminal scheduler never polls")


func _test_cancellation_token(components: Dictionary) -> void:
	var token: Variant = components.cancellation.new()
	var emissions: Array[int] = [0]
	token.cancelled.connect(func(_reason: String) -> void: emissions[0] += 1)
	_check(not token.is_cancelled(), "new cancellation token is active")
	token.cancel("fixture-stop")
	token.cancel("duplicate-stop")
	_check(token.is_cancelled(), "cancellation token records cancellation")
	_check(token.reason() == "fixture-stop", "first cancellation reason wins")
	_check(emissions[0] == 1, "cancellation signal is idempotent")


func _test_event_normalization(components: Dictionary) -> void:
	var fixture: Dictionary = _load_json_object(EVENT_FIXTURE)
	var normalizer: Variant = components.normalizer.new()
	var seen_kinds: Dictionary = {}
	var unknown_count: int = 0
	for raw_message: Variant in fixture.get("items", []):
		var event: Variant = normalizer.normalize(raw_message)
		_check(event != null, "event fixture normalizes")
		if event == null:
			continue
		seen_kinds[event.kind] = true
		if event.is_unknown:
			unknown_count += 1
	_check(seen_kinds.has("poll"), "pollEvent and pollDetails normalize to poll")
	_check(seen_kinds.has("gift"), "gift event remains YouTube-native")
	_check(seen_kinds.has("terminal"), "chat-ended event is terminal")
	_check(unknown_count == 1, "unknown future event uses forward-compatible path")

	var deduplicator: Variant = components.deduplicator.new()
	var stream_fixture: Dictionary = _load_json_object(STREAM_FIXTURE)
	var stream_responses: Array = stream_fixture.get("responses", [])
	var first_gift: Variant = normalizer.normalize(stream_responses[1]["items"][0])
	var combo_update: Variant = normalizer.normalize(stream_responses[2]["items"][0])
	_check(deduplicator.classify(first_gift) == "new", "first event is new")
	_check(deduplicator.classify(first_gift) == "duplicate", "unchanged replay is duplicate")
	_check(deduplicator.classify(combo_update) == "update", "gift combo with reused id is an update")
	deduplicator.clear()
	_check(deduplicator.size() == 0, "deduplicator state can be cleared")


func _test_quota_ledger(components: Dictionary) -> void:
	var contract: Dictionary = _load_json_object(CONTRACT_FIXTURE)
	var ledger: Variant = components.quota.new(contract.get("endpoints", []), 10000)
	_check(ledger.record_request("videos.list", 1000).is_empty(), "known quota request is recorded")
	_check(ledger.record_request("liveChatMessages.insert", 2000).is_empty(), "write quota request is recorded")
	_check(ledger.total_units() == 51, "quota ledger totals classified units")
	_check(ledger.request_count("videos.list") == 1, "quota ledger counts request categories")
	_check(not ledger.record_request("unknown.method", 3000).is_empty(), "unknown quota method is rejected")
	_check(ledger.remaining_units() == 9949, "quota ledger exposes remaining budget")


func _test_data_lifecycle(components: Dictionary) -> void:
	var contract: Dictionary = _load_json_object(CONTRACT_FIXTURE)
	var policy: Variant = components.lifecycle.new(contract.get("data_lifecycle", []))
	_check(policy.storage_for("oauth_refresh_token") == "os_vault_only", "refresh token requires OS vault")
	_check(policy.storage_for("oauth_access_token") == "memory_only", "access token stays in memory")
	_check(not policy.may_write_plaintext("oauth_refresh_token"), "refresh token cannot use plaintext storage")
	_check(policy.clear_trigger_for("session_descriptor").contains("clear_data"), "session descriptor has clear-data trigger")
	_check(not policy.has_item("client_secret"), "desktop client secret is not a stored datum")


func _load_json_object(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	_check(file != null, "fixture opens: %s" % path)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(parsed is Dictionary, "fixture is a JSON object: %s" % path)
	return parsed if parsed is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-001 PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-001 FAIL: %s" % failure)
	print("MS-001 FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
