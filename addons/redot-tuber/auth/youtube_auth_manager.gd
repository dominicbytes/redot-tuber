class_name YouTubeAuthManager
extends Node

const OAuthSessionClass = preload("res://addons/redot-tuber/auth/youtube_oauth_session.gd")
const TokenClientClass = preload("res://addons/redot-tuber/services/youtube_oauth_token_client.gd")
const CredentialClientClass = preload("res://addons/redot-tuber/auth/youtube_credential_helper_client.gd")
const DescriptorStoreClass = preload("res://addons/redot-tuber/auth/youtube_session_descriptor_store.gd")

signal state_changed(previous: String, current: String)
signal connected(channel: YouTubeChannelIdentity, restored: bool)
signal disconnected()
signal error_occurred(error: YouTubeApiError)

var state: String = "unconfigured"
var session_slot: String = ""
var channel: YouTubeChannelIdentity = null

var _config: YouTubeOAuthConfig = null
var _capabilities: PackedStringArray = PackedStringArray()
var _transport: YouTubeHttpTransport = null
var _owns_transport: bool = false
var _oauth: YouTubeOAuthSession = null
var _tokens: YouTubeOAuthTokenClient = null
var _credential_client: Variant = null
var _descriptor_store: Variant = null
var _access: YouTubeAuthTokenSet = YouTubeAuthTokenSet.new()
var _pending_redirect_uri: String = ""
var _slot_held: bool = false


func configure(
	config: YouTubeOAuthConfig,
	capabilities: PackedStringArray,
	stable_session_slot: String,
	transport: YouTubeHttpTransport = null,
	credential_client: Variant = null,
	descriptor_store: Variant = null
) -> YouTubeApiError:
	if _config != null and stable_session_slot != session_slot:
		return YouTubeApiError.invalid("An auth manager cannot change session slots after configuration")
	if _config != null:
		return YouTubeApiError.invalid("YouTube authentication is already configured for this client")
	if not _is_valid_slot(stable_session_slot):
		return YouTubeApiError.invalid("Session slot may contain 1–64 letters, digits, dots, underscores, or hyphens")
	var session: YouTubeOAuthSession = OAuthSessionClass.new()
	var configuration_error: YouTubeApiError = session.configure(config, capabilities)
	if configuration_error != null:
		session.free()
		return configuration_error
	var qualified_slot: String = config.credential_target(stable_session_slot)
	var lease_error: YouTubeApiError = YouTubeSessionSlotRegistry.acquire(qualified_slot, self)
	if lease_error != null:
		session.free()
		return lease_error
	_slot_held = true
	_config = config
	_capabilities = capabilities.duplicate()
	_capabilities.sort()
	session_slot = stable_session_slot
	_oauth = session
	_oauth.name = "YouTubeOAuthSession"
	add_child(_oauth)
	_transport = transport
	if _transport == null:
		_transport = YouTubeHttpTransport.new()
		_transport.name = "YouTubeOAuthTransport"
		add_child(_transport)
		_owns_transport = true
	_tokens = TokenClientClass.new(_transport)
	_credential_client = credential_client if credential_client != null else CredentialClientClass.new()
	if credential_client == null and not config.helper_path_override.is_empty():
		_credential_client.helper_path_override = config.helper_path_override
	_descriptor_store = descriptor_store if descriptor_store != null else DescriptorStoreClass.new()
	_set_state("configured")
	return null


func begin_authorization(open_system_browser: bool = true, redirect_uri_override: String = "") -> YouTubeAuthorizationRequest:
	var request: YouTubeAuthorizationRequest = YouTubeAuthorizationRequest.new()
	var readiness_error: YouTubeApiError = _ensure_ready_slot()
	if readiness_error != null:
		request.error = readiness_error
		return request
	_set_state("authorizing")
	request = _oauth.launch_authorization() if open_system_browser else _oauth.prepare_authorization(redirect_uri_override)
	_pending_redirect_uri = request.redirect_uri
	if request.error != null:
		_set_state("configured")
		error_occurred.emit(request.error)
	return request


func authorize_interactive() -> YouTubeAuthResult:
	var request: YouTubeAuthorizationRequest = begin_authorization(true)
	if request.error != null:
		return _failed(request.error)
	var callback: YouTubeOAuthCallbackResult = await _oauth.wait_for_callback()
	if callback.error != null:
		_set_state("configured")
		error_occurred.emit(callback.error)
		return _failed(callback.error)
	return await complete_authorization(callback.code)


func complete_authorization(code: String) -> YouTubeAuthResult:
	if _oauth == null or _pending_redirect_uri.is_empty():
		return _failed(YouTubeApiError.invalid("No OAuth authorization exchange is pending"))
	var parameters: Dictionary = _oauth.consume_exchange_parameters(code, _pending_redirect_uri)
	_pending_redirect_uri = ""
	if parameters.is_empty():
		return _failed(YouTubeApiError.invalid("OAuth authorization exchange parameters are unavailable"))
	_set_state("exchanging")
	var operation: YouTubeTokenOperationResult = await _tokens.exchange(_config.token_endpoint, parameters)
	parameters.clear()
	if operation.error != null:
		_set_state("configured")
		error_occurred.emit(operation.error)
		return _failed(operation.error)
	return await _accept_token(operation.token, "", false)


func restore() -> YouTubeAuthResult:
	var readiness_error: YouTubeApiError = _ensure_ready_slot()
	if readiness_error != null:
		return _failed(readiness_error)
	_set_state("restoring")
	var loaded: YouTubeSessionDescriptorLoadResult = _descriptor_store.load_descriptor(session_slot)
	if loaded.error != null:
		_set_state("configured")
		return _failed(loaded.error)
	var expected_target: String = _config.credential_target(session_slot)
	if loaded.descriptor.credential_target != expected_target:
		var mismatch: YouTubeApiError = YouTubeApiError.custom("descriptor_mismatch", "Saved session credential target does not match this application")
		_set_state("configured")
		return _failed(mismatch)
	var credential: YouTubeCredentialResult = await _credential_client.read(expected_target)
	if not credential.is_success():
		_set_state("configured")
		return _failed(credential.error if credential.error != null else YouTubeApiError.custom(credential.status, "Stored credential is unavailable"))
	var refresh_value: String = credential.secret
	credential.clear_secret()
	var operation: YouTubeTokenOperationResult = await _tokens.refresh(_config.token_endpoint, _config.client_id, refresh_value)
	if operation.error != null:
		refresh_value = ""
		_set_state("configured")
		return _failed(operation.error)
	var accepted: YouTubeAuthResult = await _accept_token(operation.token, refresh_value, true)
	refresh_value = ""
	return accepted


func refresh_access() -> YouTubeAuthResult:
	if state != "connected" or _config == null:
		return _failed(YouTubeApiError.invalid("No connected YouTube account can be refreshed"))
	var credential: YouTubeCredentialResult = await _credential_client.read(_config.credential_target(session_slot))
	if not credential.is_success():
		return _failed(credential.error if credential.error != null else YouTubeApiError.custom(credential.status, "Stored credential is unavailable"))
	var refresh_value: String = credential.secret
	credential.clear_secret()
	var operation: YouTubeTokenOperationResult = await _tokens.refresh(_config.token_endpoint, _config.client_id, refresh_value)
	if operation.error != null:
		refresh_value = ""
		return _failed(operation.error)
	var accepted: YouTubeAuthResult = await _accept_token(operation.token, refresh_value, true)
	refresh_value = ""
	return accepted


func ensure_fresh_access(skew_seconds: int = 300) -> YouTubeAuthResult:
	if not _access.should_refresh(skew_seconds):
		return _current_result(false)
	return await refresh_access()


func revoke_and_disconnect() -> YouTubeApiError:
	return await _disconnect_internal(true)


func clear_local_data() -> YouTubeApiError:
	return await _disconnect_internal(false)


func cancel_authorization(reason: String = "cancelled") -> void:
	if _oauth != null:
		_oauth.cancel_authorization(reason)
	_pending_redirect_uri = ""
	if state in ["authorizing", "exchanging"]:
		_set_state("configured")


func access_token() -> String:
	return _access.access_token


func granted_scopes() -> PackedStringArray:
	return _access.granted_scopes.duplicate()


func granted_capabilities() -> PackedStringArray:
	return _capabilities.duplicate() if state == "connected" else PackedStringArray()


func _accept_token(token: YouTubeAuthTokenSet, fallback_refresh: String, restored: bool) -> YouTubeAuthResult:
	if token == null:
		fallback_refresh = ""
		return _failed(YouTubeApiError.from_transport(ERR_INVALID_DATA, "OAuth token result is missing"))
	if token.granted_scopes.is_empty():
		token.granted_scopes = _oauth.requested_scopes()
	var refresh_to_store: String = token.refresh_token if not token.refresh_token.is_empty() else fallback_refresh
	if refresh_to_store.is_empty():
		token.clear()
		return _failed(YouTubeApiError.custom("persistence_unavailable", "Google did not return a refresh token; reconnect with consent to enable persistent login"))
	var api: YouTubeApiClient = YouTubeApiClient.new(_transport)
	var api_error: YouTubeApiError = api.configure("", token.access_token, _config.youtube_api_base_url)
	if api_error != null:
		refresh_to_store = ""
		token.clear()
		return _failed(api_error)
	var channels: YouTubeChannelService = YouTubeChannelService.new(api)
	var channel_result: YouTubeChannelResult = await channels.get_mine()
	if channel_result.error != null:
		refresh_to_store = ""
		token.clear()
		return _failed(channel_result.error)
	var target: String = _config.credential_target(session_slot)
	var stored: YouTubeCredentialResult = await _credential_client.store(target, refresh_to_store)
	refresh_to_store = ""
	token.clear_refresh_token()
	if not stored.is_success():
		token.clear()
		return _failed(stored.error if stored.error != null else YouTubeApiError.custom(stored.status, "Unable to persist the YouTube session"))
	var descriptor: YouTubeSessionDescriptor = YouTubeSessionDescriptor.new()
	descriptor.session_slot = session_slot
	descriptor.credential_target = target
	descriptor.channel_id = channel_result.channel.id
	descriptor.channel_title = channel_result.channel.title
	descriptor.channel_custom_url = channel_result.channel.custom_url
	descriptor.granted_capabilities = _capabilities.duplicate()
	descriptor.granted_scopes = token.granted_scopes.duplicate()
	var descriptor_error: YouTubeApiError = _descriptor_store.save(descriptor)
	if descriptor_error != null:
		await _credential_client.delete(target)
		token.clear()
		return _failed(descriptor_error)
	_access.clear()
	_access = token
	channel = channel_result.channel
	_set_state("connected")
	connected.emit(channel, restored)
	return _current_result(restored)


func _disconnect_internal(revoke: bool) -> YouTubeApiError:
	if _config == null:
		return null
	cancel_authorization("disconnect")
	var first_error: YouTubeApiError = null
	var target: String = _config.credential_target(session_slot)
	if revoke:
		var credential: YouTubeCredentialResult = await _credential_client.read(target)
		if credential.is_success():
			var revoke_value: String = credential.secret
			credential.clear_secret()
			var revoke_result: YouTubeTokenOperationResult = await _tokens.revoke(_config.revocation_endpoint, revoke_value)
			revoke_value = ""
			if revoke_result.error != null:
				first_error = revoke_result.error
		elif credential.status != "not_found":
			first_error = credential.error
	var deleted: YouTubeCredentialResult = await _credential_client.delete(target)
	if not deleted.is_success() and deleted.status != "not_found" and first_error == null:
		first_error = deleted.error
	var descriptor_error: YouTubeApiError = _descriptor_store.delete_descriptor(session_slot)
	if descriptor_error != null and first_error == null:
		first_error = descriptor_error
	_access.clear()
	channel = null
	_release_slot()
	_set_state("disconnected")
	disconnected.emit()
	return first_error


func _ensure_ready_slot() -> YouTubeApiError:
	if _config == null or _oauth == null:
		return YouTubeApiError.invalid("Configure YouTube authentication first")
	if not _slot_held:
		var lease_error: YouTubeApiError = YouTubeSessionSlotRegistry.acquire(_config.credential_target(session_slot), self)
		if lease_error != null:
			return lease_error
		_slot_held = true
	return null


func _release_slot() -> void:
	if _slot_held and _config != null:
		YouTubeSessionSlotRegistry.release(_config.credential_target(session_slot), self)
	_slot_held = false


func _current_result(restored: bool) -> YouTubeAuthResult:
	var result: YouTubeAuthResult = YouTubeAuthResult.new()
	result.channel = channel
	result.granted_capabilities = _capabilities.duplicate()
	result.granted_scopes = _access.granted_scopes.duplicate()
	result.restored = restored
	return result


func _failed(error: YouTubeApiError) -> YouTubeAuthResult:
	var result: YouTubeAuthResult = YouTubeAuthResult.new()
	result.error = error
	return result


func _set_state(next_state: String) -> void:
	if state == next_state:
		return
	var previous: String = state
	state = next_state
	state_changed.emit(previous, next_state)


func _is_valid_slot(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	var allowed: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
	for character: String in value:
		if not allowed.contains(character):
			return false
	return true


func _exit_tree() -> void:
	_access.clear()
	_release_slot()
	if _owns_transport and is_instance_valid(_transport):
		_transport.cancel_all("auth manager freed")
