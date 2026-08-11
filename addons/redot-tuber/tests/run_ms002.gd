extends SceneTree

const ADDON_ROOT: String = "res://addons/redot-tuber"
const FIXTURE_PATH: String = ADDON_ROOT + "/tests/fixtures/video_resolution.json"

var _checks: int = 0
var _failures: PackedStringArray = []


class FakeApiClient extends RefCounted:
	var response: Variant
	var captured_method_id: String = ""
	var captured_query: Dictionary = {}

	func _init(value: Variant) -> void:
		response = value

	func request_json(method_id: String, _http_method: int, _path: String, query: Dictionary = {}, _body: Dictionary = {}, _cancellation: Variant = null) -> Variant:
		captured_method_id = method_id
		captured_query = query.duplicate(true)
		return response


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var classes: Dictionary = _load_components()
	if classes.is_empty():
		_finish()
		return
	_test_plugin_contract()
	_test_discovery_generator(classes)
	_test_redaction(classes)
	_test_api_errors(classes)
	await _test_video_resolution(classes)
	_test_chat_page(classes)
	_test_public_client_contract(classes)
	_finish()


func _load_components() -> Dictionary:
	var paths: Dictionary = {
		"redactor": ADDON_ROOT + "/diagnostics/youtube_redactor.gd",
		"error": ADDON_ROOT + "/models/youtube_api_error.gd",
		"response": ADDON_ROOT + "/transport/youtube_http_response.gd",
		"resolution": ADDON_ROOT + "/models/youtube_live_chat_resolution.gd",
		"video_service": ADDON_ROOT + "/services/youtube_video_service.gd",
		"chat_page": ADDON_ROOT + "/models/youtube_live_chat_page.gd",
		"chat_service": ADDON_ROOT + "/services/youtube_live_chat_service.gd",
		"client": ADDON_ROOT + "/runtime/youtube_live_client.gd",
		"generator": ADDON_ROOT + "/editor/youtube_discovery_contract_generator.gd",
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


func _test_plugin_contract() -> void:
	var config: ConfigFile = ConfigFile.new()
	_check(config.load(ADDON_ROOT + "/plugin.cfg") == OK, "plugin.cfg loads")
	_check(String(config.get_value("plugin", "name", "")) == "Redot Tuber", "plugin is branded for Redot Tuber")
	_check(String(config.get_value("plugin", "script", "")) == "plugin.gd", "plugin entry script is local")
	var project: ConfigFile = ConfigFile.new()
	_check(project.load("res://project.godot") == OK, "development project loads")
	var enabled: PackedStringArray = project.get_value("editor_plugins", "enabled", PackedStringArray())
	_check(enabled.has("redot-tuber"), "development project enables addon")
	_check(not project.has_section("autoload"), "addon does not require an autoload")
	_check(FileAccess.file_exists("res://LICENSE"), "repository MIT license exists")
	_check(FileAccess.file_exists(ADDON_ROOT + "/LICENSE"), "addon-local license exists")
	_check(FileAccess.file_exists("res://THIRD_PARTY_NOTICES.md"), "third-party notices exist")
	var lineage: String = _read_text("res://docs/lineage/twitcher-reuse.md")
	_check(lineage.contains("5c80a758b1800ac74bdfa36cf2f0274013ba58dc"), "reuse manifest pins donor commit")
	_check(lineage.contains("buffered_http_client.gd") and lineage.contains("Rejected"), "reuse manifest records rejected donor HTTP client")


func _test_discovery_generator(classes: Dictionary) -> void:
	var fixture: Dictionary = _load_json_object(ADDON_ROOT + "/tests/fixtures/youtube_discovery_minimal.json")
	var generator: Variant = classes.generator.new()
	var methods: Array[Dictionary] = generator.extract_methods(fixture)
	_check(methods.size() == 2, "Google Discovery fixture yields all methods")
	_check(String(methods[0].get("id", "")) == "liveChatMessages.list", "generated methods are deterministic and sorted")
	_check((methods[0].get("required_parameters", PackedStringArray()) as PackedStringArray) == PackedStringArray(["liveChatId", "part"]), "generator preserves required parameters")
	var first: String = generator.render_contract_json(fixture)
	var second: String = generator.render_contract_json(fixture)
	_check(first == second, "Google Discovery contract generation is deterministic")
	_check(not first.to_lower().contains("twitch"), "generated YouTube contract contains no Twitch schema")


func _test_redaction(classes: Dictionary) -> void:
	var redactor: Variant = classes.redactor.new()
	var unsafe: String = "Authorization: Bearer access-secret?key=api-secret&code=auth-secret&refresh_token=refresh-secret&client_secret=client-secret"
	var safe: String = redactor.redact_text(unsafe)
	for secret: String in ["access-secret", "api-secret", "auth-secret", "refresh-secret", "client-secret"]:
		_check(not safe.contains(secret), "redactor removes %s" % secret)
	_check(safe.contains("[REDACTED]"), "redactor leaves an explicit marker")
	var nested: Dictionary = {"access_token": "a", "safe": "visible", "child": {"refresh_token": "b"}}
	var redacted: Dictionary = redactor.redact_dictionary(nested)
	_check(redacted.get("safe") == "visible", "dictionary redaction preserves safe data")
	_check(redacted.get("access_token") == "[REDACTED]", "dictionary redaction removes top-level token")
	_check((redacted.get("child", {}) as Dictionary).get("refresh_token") == "[REDACTED]", "dictionary redaction is recursive")


func _test_api_errors(classes: Dictionary) -> void:
	var error: Variant = classes.error.from_http(403, {"error": {"code": 403, "message": "Denied", "errors": [{"reason": "quotaExceeded"}]}})
	_check(error.category == "quota_exhausted", "quotaExceeded maps to typed quota error")
	_check(error.http_status == 403, "typed error preserves HTTP status")
	_check(error.reasons == PackedStringArray(["quotaExceeded"]), "typed error preserves reasons")
	_check(not error.is_retryable, "quota denial is not automatically retried")
	var transient: Variant = classes.error.from_http(503, {"error": {"message": "Unavailable"}})
	_check(transient.category == "server_error" and transient.is_retryable, "server failure is typed retryable")


func _test_video_resolution(classes: Dictionary) -> void:
	var fixture: Dictionary = _load_json_object(FIXTURE_PATH)
	var response_script: Script = classes.response
	for case_name: String in ["valid", "missing", "disabled", "ended", "denied"]:
		var http_response: Variant = response_script.new()
		http_response.status_code = 403 if case_name == "denied" else 200
		http_response.parsed_json = fixture.get(case_name, {})
		var fake: FakeApiClient = FakeApiClient.new(http_response)
		var service: Variant = classes.video_service.new(fake)
		var result: Variant = await service.resolve_live_chat(case_name + "-video")
		var expected: String = {
			"valid": "active",
			"missing": "not_found",
			"disabled": "chat_disabled",
			"ended": "ended",
			"denied": "denied",
		}.get(case_name, "")
		_check(result.status == expected, "video case %s resolves to %s" % [case_name, expected])
		_check(fake.captured_method_id == "videos.list", "video case uses videos.list")
		_check(String(fake.captured_query.get("part", "")).contains("liveStreamingDetails"), "video case requests live streaming details")
		if case_name == "valid":
			_check(result.live_chat_id == "fixture-chat", "active resolution returns live chat id")
			_check(result.title == "Fixture Live", "active resolution returns title")


func _test_chat_page(classes: Dictionary) -> void:
	var fixture: Dictionary = _load_json_object(ADDON_ROOT + "/tests/fixtures/live_chat_stream.json")
	var response: Variant = classes.response.new()
	response.status_code = 200
	response.parsed_json = (fixture.get("responses", []) as Array)[0]
	var fake: FakeApiClient = FakeApiClient.new(response)
	var service: Variant = classes.chat_service.new(fake)
	var page: Variant = await service.list_messages("fixture-chat")
	_check(page.error == null, "chat page succeeds")
	_check(page.events.size() == 1, "chat page normalizes all events")
	_check(page.next_page_token == "fixture-token-1", "chat page preserves continuation token")
	_check(page.polling_interval_msec == 1500, "chat page preserves server polling interval")
	_check(page.events[0].kind == "text_message", "chat page emits typed ordered events")


func _test_public_client_contract(classes: Dictionary) -> void:
	var client: Variant = classes.client.new()
	_check(client.session_slot == "default", "client starts with one stable session slot")
	_check(client.connection_state == "unconfigured", "client starts unconfigured")
	var configuration_error: Variant = client.configure_public("fixture-api-key", "slot-a")
	_check(configuration_error == null, "public API-key configuration succeeds")
	_check(client.connection_state == "configured", "configuration changes typed state")
	_check(client.session_slot == "slot-a", "client owns exactly one configured slot")
	_check(client.configure_public("another-key", "slot-b") != null, "active client rejects slot replacement")
	client.free()


func _load_json_object(path: String) -> Dictionary:
	var text: String = _read_text(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	_check(parsed is Dictionary, "fixture parses: %s" % path)
	return parsed if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	_check(file != null, "file opens: %s" % path)
	return file.get_as_text() if file != null else ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-002 PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-002 FAIL: %s" % failure)
	print("MS-002 FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
