extends SceneTree

const ADDON_ROOT: String = "res://addons/redot-tuber"
const TEST_DESCRIPTOR_DIR: String = "res://.test-output/session-descriptors-ms003"

var _checks: int = 0
var _failures: PackedStringArray = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var classes: Dictionary = _load_components()
	if classes.is_empty():
		_finish()
		return
	_test_pkce(classes)
	_test_scopes(classes)
	_test_oauth_config(classes)
	_test_protocol(classes)
	_test_descriptor_store(classes)
	_test_slot_registry(classes)
	_test_token_lifecycle(classes)
	_test_authorization_request(classes)
	await _test_client_oauth_contract(classes)
	_finish()


func _load_components() -> Dictionary:
	var paths: Dictionary = {
		"pkce": ADDON_ROOT + "/auth/youtube_oauth_pkce.gd",
		"scopes": ADDON_ROOT + "/auth/youtube_scope_registry.gd",
		"config": ADDON_ROOT + "/auth/youtube_oauth_config.gd",
		"protocol": ADDON_ROOT + "/auth/youtube_credential_protocol.gd",
		"credential_result": ADDON_ROOT + "/models/youtube_credential_result.gd",
		"descriptor": ADDON_ROOT + "/models/youtube_session_descriptor.gd",
		"descriptor_store": ADDON_ROOT + "/auth/youtube_session_descriptor_store.gd",
		"slot_registry": ADDON_ROOT + "/auth/youtube_session_slot_registry.gd",
		"token": ADDON_ROOT + "/models/youtube_auth_token_set.gd",
		"authorization_request": ADDON_ROOT + "/models/youtube_authorization_request.gd",
		"oauth_session": ADDON_ROOT + "/auth/youtube_oauth_session.gd",
		"client": ADDON_ROOT + "/runtime/youtube_live_client.gd",
		"connection_panel": ADDON_ROOT + "/ui/youtube_connection_panel.gd",
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


func _test_pkce(classes: Dictionary) -> void:
	var pkce: Variant = classes.pkce.new()
	var verifier: String = pkce.generate_verifier()
	var state: String = pkce.generate_state()
	_check(verifier.length() >= 43 and verifier.length() <= 128, "PKCE verifier has RFC length")
	_check(_is_base64url(verifier), "PKCE verifier uses unreserved base64url characters")
	_check(state.length() >= 32 and _is_base64url(state), "OAuth state is high-entropy base64url")
	_check(verifier != pkce.generate_verifier(), "PKCE verifier is freshly randomized")
	_check(state != pkce.generate_state(), "OAuth state is freshly randomized")
	var rfc_verifier: String = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
	_check(pkce.challenge_for(rfc_verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "PKCE S256 matches RFC 7636 vector")


func _test_scopes(classes: Dictionary) -> void:
	var registry: Variant = classes.scopes.new()
	var read_scopes: PackedStringArray = registry.scopes_for(PackedStringArray(["chat.read", "channel.read"]))
	_check(read_scopes == PackedStringArray(["https://www.googleapis.com/auth/youtube.readonly"]), "read capabilities collapse to one least-privilege scope")
	var write_scopes: PackedStringArray = registry.scopes_for(PackedStringArray(["chat.write", "moderation.manage"]))
	_check(write_scopes == PackedStringArray(["https://www.googleapis.com/auth/youtube.force-ssl"]), "chat and moderation writes use force-ssl scope")
	var broadcast_scopes: PackedStringArray = registry.scopes_for(PackedStringArray(["broadcast.manage", "chat.read"]))
	_check(broadcast_scopes == PackedStringArray(["https://www.googleapis.com/auth/youtube.force-ssl"]), "broadcast management uses the current least-privilege force-ssl scope")
	_check(not broadcast_scopes.has("https://www.googleapis.com/auth/youtube.readonly"), "stronger scope removes redundant readonly scope")
	_check(registry.validate_capabilities(PackedStringArray(["not.real"])) != null, "unknown capability is rejected")
	_check(registry.all_capabilities().has("stream.manage"), "full registry includes stream management")


func _test_oauth_config(classes: Dictionary) -> void:
	var config: Variant = classes.config.new()
	_check(config.validate() != null, "OAuth config requires a developer client ID")
	config.client_id = "fixture.apps.googleusercontent.com"
	config.application_id = "com.example.fixture"
	config.publisher_id = "fixture-publisher"
	_check(config.validate() == null, "developer-owned desktop OAuth config validates")
	var property_names: PackedStringArray = PackedStringArray()
	for property: Dictionary in config.get_property_list():
		property_names.append(String(property.get("name", "")))
	_check(not property_names.has("client_secret"), "desktop OAuth config has no client-secret field")
	config.authorization_endpoint = "http://example.com/unsafe"
	_check(config.validate() != null, "non-loopback insecure OAuth endpoint is rejected")


func _test_protocol(classes: Dictionary) -> void:
	var protocol: Variant = classes.protocol.new()
	var secret: String = "fixture-refresh-secret"
	var request: String = protocol.encode_request("store", "publisher/app/slot", secret)
	_check(request.split("\n", false).size() == 4, "credential request has a fixed four-line frame")
	_check(not request.contains(secret), "credential request does not contain raw secret text")
	var decoded: Dictionary = protocol.decode_request_for_test(request)
	_check(decoded.get("version") == 1 and decoded.get("command") == "store", "credential protocol is versioned")
	_check(decoded.get("target") == "publisher/app/slot", "credential target round-trips")
	_check(decoded.get("secret") == secret, "credential secret round-trips only through pipe codec")
	var ok: Variant = protocol.decode_response("RTCH/1\nOK\n%s\n\n" % Marshalls.raw_to_base64(secret.to_utf8_buffer()))
	_check(ok.is_success() and ok.secret == secret, "credential read response decodes in memory")
	var missing: Variant = protocol.decode_response("RTCH/1\nNOT_FOUND\n\nmissing\n")
	_check(missing.status == "not_found" and missing.secret.is_empty(), "missing credential is typed without a secret")
	var mismatch: Variant = protocol.decode_response("RTCH/99\nOK\n\n\n")
	_check(mismatch.status == "protocol_error", "helper protocol mismatch is rejected")


func _test_descriptor_store(classes: Dictionary) -> void:
	var store: Variant = classes.descriptor_store.new(TEST_DESCRIPTOR_DIR)
	var descriptor: Variant = classes.descriptor.new()
	descriptor.session_slot = "primary"
	descriptor.credential_target = "publisher/app/primary"
	descriptor.channel_id = "fixture-channel"
	descriptor.channel_title = "Fixture Creator"
	descriptor.granted_capabilities = PackedStringArray(["channel.read", "chat.read"])
	descriptor.granted_scopes = PackedStringArray(["https://www.googleapis.com/auth/youtube.readonly"])
	_check(store.save(descriptor) == null, "non-secret descriptor saves")
	var path: String = store.path_for_slot("primary")
	var raw: String = FileAccess.get_file_as_string(path)
	_check(raw.contains("fixture-channel") and raw.contains("publisher/app/primary"), "descriptor stores approved account metadata")
	_check(not raw.contains("fixture-refresh-secret") and not raw.contains("access_token") and not raw.contains("refresh_token"), "descriptor contains no token fields")
	var loaded: Variant = store.load_descriptor("primary")
	_check(loaded.error == null and loaded.descriptor.channel_id == "fixture-channel", "descriptor round-trips")
	_check(store.path_for_slot("../escape").is_empty(), "descriptor path rejects traversal")
	_check(store.delete_descriptor("primary") == null, "descriptor clear-data deletion succeeds")
	_check(not FileAccess.file_exists(path), "descriptor file is removed")


func _test_slot_registry(classes: Dictionary) -> void:
	classes.slot_registry.clear_for_tests()
	var owner_a: RefCounted = RefCounted.new()
	var owner_b: RefCounted = RefCounted.new()
	_check(classes.slot_registry.acquire("publisher/app/slot-a", owner_a) == null, "first client acquires a session slot")
	_check(classes.slot_registry.acquire("publisher/app/slot-a", owner_b) != null, "second live client cannot acquire duplicate slot")
	_check(classes.slot_registry.acquire("publisher/app/slot-b", owner_b) == null, "independent slot supports a second client")
	classes.slot_registry.release("publisher/app/slot-a", owner_a)
	_check(classes.slot_registry.acquire("publisher/app/slot-a", owner_b) == null, "released slot can be restored by another client")
	classes.slot_registry.clear_for_tests()


func _test_token_lifecycle(classes: Dictionary) -> void:
	var token: Variant = classes.token.new()
	token.access_token = "memory-only-access"
	token.refresh_token = "transient-refresh"
	token.expires_at_unix = Time.get_unix_time_from_system() + 3600
	_check(not token.is_expired(), "fresh access token is valid")
	_check(token.should_refresh(3700), "refresh skew can request early rotation")
	token.clear_refresh_token()
	_check(token.refresh_token.is_empty() and token.access_token == "memory-only-access", "refresh token can be cleared independently after vault storage")
	token.clear()
	_check(token.access_token.is_empty() and token.granted_scopes.is_empty(), "disconnect clears token memory")


func _test_authorization_request(classes: Dictionary) -> void:
	var config: Variant = classes.config.new()
	config.client_id = "fixture.apps.googleusercontent.com"
	config.application_id = "com.example.fixture"
	config.publisher_id = "fixture-publisher"
	var session: Node = classes.oauth_session.new()
	root.add_child(session)
	var configure_error: Variant = session.configure(config, PackedStringArray(["channel.read", "chat.read"]))
	_check(configure_error == null, "OAuth session configuration succeeds")
	var request: Variant = session.prepare_authorization("http://127.0.0.1:49152/oauth2/callback")
	_check(request.error == null, "authorization request is prepared")
	_check(request.authorization_url.begins_with(config.authorization_endpoint + "?"), "authorization uses configured Google endpoint")
	for required: String in ["client_id=", "redirect_uri=", "response_type=code", "scope=", "state=", "code_challenge=", "code_challenge_method=S256", "access_type=offline"]:
		_check(request.authorization_url.contains(required), "authorization URL contains %s" % required)
	_check(not request.authorization_url.contains("client_secret"), "authorization URL never contains a client secret")
	_check(session.pending_verifier_length_for_test() >= 43, "PKCE verifier remains private session memory")
	session.cancel_authorization("fixture complete")
	_check(session.pending_verifier_length_for_test() == 0, "cancel clears verifier and state memory")
	session.free()


func _test_client_oauth_contract(classes: Dictionary) -> void:
	classes.slot_registry.clear_for_tests()
	var config: Variant = classes.config.new()
	config.client_id = "fixture.apps.googleusercontent.com"
	config.application_id = "com.example.client-contract"
	config.publisher_id = "fixture-publisher"
	var client_a: Node = classes.client.new()
	var client_b: Node = classes.client.new()
	var duplicate: Node = classes.client.new()
	root.add_child(client_a)
	root.add_child(client_b)
	root.add_child(duplicate)
	var capabilities: PackedStringArray = PackedStringArray(["channel.read", "chat.read"])
	_check(client_a.configure_oauth(config, capabilities, "slot-a") == null, "first public client configures OAuth slot")
	_check(client_b.configure_oauth(config, capabilities, "slot-b") == null, "second public client configures independent OAuth slot")
	_check(duplicate.configure_oauth(config, capabilities, "slot-a") != null, "public facade rejects a duplicate active OAuth slot")
	_check(client_a.connection_state == "oauth_configured", "OAuth facade exposes configured state")
	_check(client_a.configure_public("key", "slot-a") != null, "OAuth facade rejects mixed public reconfiguration")
	var panel: Control = classes.connection_panel.new()
	root.add_child(panel)
	await process_frame
	panel.bind_client(client_a)
	_check(panel.get_child_count() >= 5, "optional connection panel builds text-labelled controls")
	var button_count: int = 0
	for child: Node in panel.find_children("*", "Button", true, false):
		button_count += 1
	_check(button_count == 5, "connection panel exposes connect, restore, cancel, revoke, and clear actions")
	panel.free()
	duplicate.free()
	client_b.free()
	client_a.free()
	await process_frame
	classes.slot_registry.clear_for_tests()


func _is_base64url(value: String) -> bool:
	var allowed: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
	for character: String in value:
		if not allowed.contains(character):
			return false
	return true


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-003 PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-003 FAIL: %s" % failure)
	print("MS-003 FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
