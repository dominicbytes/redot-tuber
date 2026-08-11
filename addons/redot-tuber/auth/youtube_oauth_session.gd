class_name YouTubeOAuthSession
extends Node

const PkceClass = preload("res://addons/redot-tuber/auth/youtube_oauth_pkce.gd")
const ScopeRegistryClass = preload("res://addons/redot-tuber/auth/youtube_scope_registry.gd")
const CallbackServerClass = preload("res://addons/redot-tuber/auth/youtube_loopback_callback_server.gd")

signal browser_authorization_required(authorization_url: String)

var _config: YouTubeOAuthConfig = null
var _capabilities: PackedStringArray = PackedStringArray()
var _scopes: PackedStringArray = PackedStringArray()
var _pkce: YouTubeOAuthPkce = PkceClass.new()
var _callback_server: YouTubeLoopbackCallbackServer = null
var _pending_state: String = ""
var _pending_verifier: String = ""


func configure(config: YouTubeOAuthConfig, capabilities: PackedStringArray) -> YouTubeApiError:
	if config == null:
		return YouTubeApiError.invalid("OAuth configuration is required")
	var config_error: YouTubeApiError = config.validate()
	if config_error != null:
		return config_error
	var registry: YouTubeScopeRegistry = ScopeRegistryClass.new()
	var capability_error: YouTubeApiError = registry.validate_capabilities(capabilities)
	if capability_error != null:
		return capability_error
	_config = config
	_capabilities = capabilities.duplicate()
	_capabilities.sort()
	_scopes = registry.scopes_for(_capabilities)
	return null


func prepare_authorization(redirect_uri_override: String = "") -> YouTubeAuthorizationRequest:
	cancel_authorization("authorization replaced")
	var request: YouTubeAuthorizationRequest = YouTubeAuthorizationRequest.new()
	if _config == null:
		request.error = YouTubeApiError.invalid("Configure the OAuth session before authorization")
		return request
	_pending_state = _pkce.generate_state()
	_pending_verifier = _pkce.generate_verifier()
	var challenge: String = _pkce.challenge_for(_pending_verifier)
	if challenge.is_empty():
		request.error = YouTubeApiError.from_transport(ERR_CANT_CREATE, "Unable to create the PKCE challenge")
		_clear_pending_secrets()
		return request

	var redirect_uri: String = redirect_uri_override
	if redirect_uri.is_empty():
		_callback_server = CallbackServerClass.new()
		add_child(_callback_server)
		var start_error: YouTubeApiError = _callback_server.start(_pending_state, _config.callback_timeout_msec)
		if start_error != null:
			request.error = start_error
			_callback_server.queue_free()
			_callback_server = null
			_clear_pending_secrets()
			return request
		redirect_uri = _callback_server.redirect_uri()
	if not redirect_uri.begins_with("http://127.0.0.1:") or not redirect_uri.ends_with(YouTubeLoopbackCallbackServer.CALLBACK_PATH):
		request.error = YouTubeApiError.invalid("OAuth redirect must be an IPv4 loopback callback")
		cancel_authorization("invalid redirect")
		return request

	var query: Dictionary = {
		"access_type": "offline",
		"client_id": _config.client_id,
		"code_challenge": challenge,
		"code_challenge_method": "S256",
		"include_granted_scopes": "true",
		"prompt": "consent",
		"redirect_uri": redirect_uri,
		"response_type": "code",
		"scope": " ".join(_scopes),
		"state": _pending_state,
	}
	request.authorization_url = _build_url(_config.authorization_endpoint, query)
	request.redirect_uri = redirect_uri
	request.expires_at_msec = Time.get_ticks_msec() + _config.callback_timeout_msec
	return request


func launch_authorization() -> YouTubeAuthorizationRequest:
	var request: YouTubeAuthorizationRequest = prepare_authorization()
	if request.error != null:
		return request
	var open_error: Error = OS.shell_open(request.authorization_url)
	if open_error != OK:
		request.error = YouTubeApiError.custom("browser_unavailable", "Unable to open the system browser")
		# The URL remains available to the caller for copy/paste recovery.
	else:
		browser_authorization_required.emit(request.authorization_url)
	return request


func wait_for_callback() -> YouTubeOAuthCallbackResult:
	if _callback_server == null:
		var missing: YouTubeOAuthCallbackResult = YouTubeOAuthCallbackResult.new()
		missing.error = YouTubeApiError.invalid("No OAuth callback is pending")
		return missing
	var result: YouTubeOAuthCallbackResult = await _callback_server.wait_for_result()
	if result.error != null:
		_clear_pending_secrets()
	return result


func consume_exchange_parameters(code: String, redirect_uri: String) -> Dictionary:
	if code.is_empty() or _pending_verifier.is_empty() or _config == null:
		return {}
	var parameters: Dictionary = {
		"client_id": _config.client_id,
		"code": code,
		"code_verifier": _pending_verifier,
		"grant_type": "authorization_code",
		"redirect_uri": redirect_uri,
	}
	_clear_pending_secrets()
	return parameters


func cancel_authorization(_reason: String = "cancelled") -> void:
	if _callback_server != null:
		_callback_server.stop()
		_callback_server.queue_free()
		_callback_server = null
	_clear_pending_secrets()


func requested_capabilities() -> PackedStringArray:
	return _capabilities.duplicate()


func requested_scopes() -> PackedStringArray:
	return _scopes.duplicate()


func pending_verifier_length_for_test() -> int:
	return _pending_verifier.length()


func _exit_tree() -> void:
	cancel_authorization("session freed")


func _clear_pending_secrets() -> void:
	_pending_state = ""
	_pending_verifier = ""


func _build_url(base_url: String, query: Dictionary) -> String:
	var keys: Array = query.keys()
	keys.sort()
	var pairs: PackedStringArray = PackedStringArray()
	for key_value: Variant in keys:
		pairs.append("%s=%s" % [String(key_value).uri_encode(), String(query[key_value]).uri_encode()])
	return base_url + "?" + "&".join(pairs)
