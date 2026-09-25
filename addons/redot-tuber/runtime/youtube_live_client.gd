class_name YouTubeLiveClient
extends Node

const ContractPath: String = "res://addons/redot-tuber/contracts/youtube_api_contract.json"

signal connection_state_changed(previous: String, current: String)
signal authorization_url_ready(authorization_url: String)
signal account_connected(channel: YouTubeChannelIdentity, restored: bool)
signal account_disconnected()
signal capabilities_changed(capabilities: PackedStringArray)
signal live_chat_resolved(resolution: YouTubeLiveChatResolution)
signal event_source_changed(mode: String)
signal event_received(event: YouTubeLiveEvent)
signal event_updated(event: YouTubeLiveEvent)
signal message_received(event: YouTubeLiveEvent)
signal monetization_received(event: YouTubeLiveEvent)
signal membership_received(event: YouTubeLiveEvent)
signal poll_received(event: YouTubeLiveEvent)
signal moderation_received(event: YouTubeLiveEvent)
signal gift_received(event: YouTubeLiveEvent, updated: bool)
signal system_event_received(event: YouTubeLiveEvent)
signal unknown_event_received(event: YouTubeLiveEvent)
signal quota_changed(total_units: int, remaining_units: int)
signal quota_bucket_changed(bucket: String, used_units: int, remaining_units: int)
signal error_occurred(error: YouTubeApiError)

@export var session_slot: String = "default"
@export var prefer_streaming: bool = false
@export var fallback_to_polling: bool = true

var connection_state: String = "unconfigured"
var active_video_id: String = ""
var active_live_chat_id: String = ""
var connected_channel: YouTubeChannelIdentity = null
var event_source_mode: String = "stopped"

var _transport: YouTubeHttpTransport = null
var _quota: YouTubeQuotaLedger = null
var _api: YouTubeApiClient = null
var _videos: YouTubeVideoService = null
var _channels: YouTubeChannelService = null
var _discovery: YouTubeDiscoveryService = null
var _chat: YouTubeLiveChatService = null
var _moderation: YouTubeModerationService = null
var _broadcasts: YouTubeBroadcastService = null
var _streams: YouTubeStreamService = null
var _monetization: YouTubeMonetizationService = null
var _media: YouTubeMediaCache = null
var _capability_gate: YouTubeCapabilityGate = null
var _stream_source: YouTubeLiveChatStreamSource = null
var _poll_scheduler: YouTubeLiveChatPollScheduler = null
var _deduplicator: YouTubeEventDeduplicator = null
var _cancellation: YouTubeCancellationToken = null
var _is_polling: bool = false
var _chat_generation: int = 0
var _poll_generation: int = 0
var _stream_should_fallback: bool = false
var _stream_error_category: String = ""
var _configured_slot: String = ""
var _auth: YouTubeAuthManager = null
var _oauth_api_base_url: String = YouTubeApiClient.DEFAULT_BASE_URL
var _granted_capabilities: PackedStringArray = PackedStringArray()


func configure_public(api_key: String, stable_session_slot: String = "default", base_url: String = YouTubeApiClient.DEFAULT_BASE_URL) -> YouTubeApiError:
	if _auth != null:
		return YouTubeApiError.invalid("This YouTubeLiveClient is already configured for OAuth")
	if not _configured_slot.is_empty() and stable_session_slot != _configured_slot:
		return YouTubeApiError.invalid("A YouTubeLiveClient cannot change session slots after configuration")
	var slot_error: String = _validate_slot(stable_session_slot)
	if not slot_error.is_empty():
		return YouTubeApiError.invalid(slot_error)
	_ensure_runtime()
	var error: YouTubeApiError = _api.configure(api_key, "", base_url)
	if error != null:
		return error
	_configured_slot = stable_session_slot
	session_slot = stable_session_slot
	_granted_capabilities = PackedStringArray(["channel.read", "discovery.read", "chat.read"])
	_capability_gate.configure(_granted_capabilities, false)
	capabilities_changed.emit(_granted_capabilities)
	_set_state("configured")
	return null


func configure_oauth(
	config: YouTubeOAuthConfig,
	capabilities: PackedStringArray,
	stable_session_slot: String = "default",
	credential_client: Variant = null,
	descriptor_store: Variant = null
) -> YouTubeApiError:
	if _auth != null:
		return YouTubeApiError.invalid("YouTube OAuth is already configured for this client")
	if not _configured_slot.is_empty() and _configured_slot != stable_session_slot:
		return YouTubeApiError.invalid("A YouTubeLiveClient cannot change session slots after configuration")
	var slot_error: String = _validate_slot(stable_session_slot)
	if not slot_error.is_empty():
		return YouTubeApiError.invalid(slot_error)
	_ensure_runtime()
	_auth = YouTubeAuthManager.new()
	_auth.name = "YouTubeAuthManager"
	add_child(_auth)
	_auth.state_changed.connect(_on_auth_state_changed)
	_auth.connected.connect(_on_account_connected)
	_auth.disconnected.connect(_on_account_disconnected)
	_auth.error_occurred.connect(func(error: YouTubeApiError) -> void: error_occurred.emit(error))
	var error: YouTubeApiError = _auth.configure(config, capabilities, stable_session_slot, _transport, credential_client, descriptor_store)
	if error != null:
		_auth.queue_free()
		_auth = null
		return error
	_configured_slot = stable_session_slot
	session_slot = stable_session_slot
	_oauth_api_base_url = config.youtube_api_base_url
	_capability_gate.clear()
	_granted_capabilities.clear()
	_set_state("oauth_configured")
	return null


func begin_account_authorization(open_system_browser: bool = true, redirect_uri_override: String = "") -> YouTubeAuthorizationRequest:
	if _auth == null:
		var missing: YouTubeAuthorizationRequest = YouTubeAuthorizationRequest.new()
		missing.error = YouTubeApiError.invalid("Configure OAuth before connecting an account")
		return missing
	var request: YouTubeAuthorizationRequest = _auth.begin_authorization(open_system_browser, redirect_uri_override)
	if request.is_valid():
		authorization_url_ready.emit(request.authorization_url)
	return request


func complete_account_authorization(code: String) -> YouTubeAuthResult:
	if _auth == null:
		var missing: YouTubeAuthResult = YouTubeAuthResult.new()
		missing.error = YouTubeApiError.invalid("Configure OAuth before completing authorization")
		return missing
	var result: YouTubeAuthResult = await _auth.complete_authorization(code)
	if result.is_success():
		_activate_authorized_api()
	return result


func connect_account() -> YouTubeAuthResult:
	if _auth == null:
		var missing: YouTubeAuthResult = YouTubeAuthResult.new()
		missing.error = YouTubeApiError.invalid("Configure OAuth before connecting an account")
		return missing
	var result: YouTubeAuthResult = await _auth.authorize_interactive()
	if result.is_success():
		_activate_authorized_api()
	return result


func restore_account() -> YouTubeAuthResult:
	if _auth == null:
		var missing: YouTubeAuthResult = YouTubeAuthResult.new()
		missing.error = YouTubeApiError.invalid("Configure OAuth before restoring an account")
		return missing
	var result: YouTubeAuthResult = await _auth.restore()
	if result.is_success():
		_activate_authorized_api()
	return result


func refresh_account() -> YouTubeAuthResult:
	if _auth == null:
		var missing: YouTubeAuthResult = YouTubeAuthResult.new()
		missing.error = YouTubeApiError.invalid("No OAuth account is configured")
		return missing
	var result: YouTubeAuthResult = await _auth.refresh_access()
	if result.is_success():
		_activate_authorized_api()
	return result


func disconnect_account(revoke: bool = true) -> YouTubeApiError:
	if _auth == null:
		return null
	stop_chat("account disconnected")
	var error: YouTubeApiError = null
	if revoke:
		error = await _auth.revoke_and_disconnect()
	else:
		error = await _auth.clear_local_data()
	_api.clear_access_token()
	connected_channel = null
	_granted_capabilities.clear()
	_capability_gate.clear()
	capabilities_changed.emit(_granted_capabilities)
	_set_state("oauth_configured")
	return error


func cancel_account_authorization() -> void:
	if _auth != null:
		_auth.cancel_authorization("user cancelled")


func granted_capabilities() -> PackedStringArray:
	return _granted_capabilities.duplicate()


func has_capability(capability: String) -> bool:
	return _granted_capabilities.has(capability)


func capability_matrix() -> Array[YouTubeCapabilityInfo]:
	return YouTubeCapabilityRegistry.all_method_info()


func channel_service() -> YouTubeChannelService:
	_ensure_runtime()
	return _channels


func discovery_service() -> YouTubeDiscoveryService:
	_ensure_runtime()
	return _discovery


func live_chat_service() -> YouTubeLiveChatService:
	_ensure_runtime()
	return _chat


func moderation_service() -> YouTubeModerationService:
	_ensure_runtime()
	return _moderation


func broadcast_service() -> YouTubeBroadcastService:
	_ensure_runtime()
	return _broadcasts


func stream_service() -> YouTubeStreamService:
	_ensure_runtime()
	return _streams


func monetization_service() -> YouTubeMonetizationService:
	_ensure_runtime()
	return _monetization


func media_cache() -> YouTubeMediaCache:
	_ensure_runtime()
	return _media


func quota_snapshot() -> Dictionary:
	if _quota == null:
		return {}
	return {
		"total_units": _quota.total_units(),
		"youtube_data_used": _quota.bucket_units("youtube_data"),
		"youtube_data_remaining": _quota.bucket_remaining_units("youtube_data"),
		"search_queries_used": _quota.bucket_units("search_queries"),
		"search_queries_remaining": _quota.bucket_remaining_units("search_queries"),
	}


func resolve_video(video_id: String) -> YouTubeLiveChatResolution:
	if _videos == null:
		var unconfigured: YouTubeLiveChatResolution = YouTubeLiveChatResolution.new()
		unconfigured.video_id = video_id
		unconfigured.error = YouTubeApiError.invalid("Configure YouTubeLiveClient before resolving a video")
		error_occurred.emit(unconfigured.error)
		return unconfigured
	stop_chat("new video resolution")
	_cancellation = YouTubeCancellationToken.new()
	var generation: int = _chat_generation
	var cancellation: YouTubeCancellationToken = _cancellation
	_set_state("resolving")
	var resolution: YouTubeLiveChatResolution = await _videos.resolve_live_chat(video_id, cancellation)
	if generation != _chat_generation or cancellation.is_cancelled():
		var cancelled: YouTubeLiveChatResolution = YouTubeLiveChatResolution.new()
		cancelled.error = YouTubeApiError.from_transport(ERR_SKIP, "Video resolution was superseded")
		return cancelled
	live_chat_resolved.emit(resolution)
	if generation != _chat_generation or cancellation.is_cancelled():
		resolution.status = YouTubeLiveChatResolution.STATUS_ERROR
		resolution.error = YouTubeApiError.from_transport(ERR_SKIP, "Video resolution was cancelled by its listener")
		return resolution
	if resolution.is_active():
		active_video_id = video_id
		active_live_chat_id = resolution.live_chat_id
		_set_state("ready")
	elif resolution.error != null:
		_set_state("error")
		error_occurred.emit(resolution.error)
	else:
		_set_state(resolution.status)
	return resolution


func start_polling(video_id: String) -> YouTubeLiveChatResolution:
	var resolution: YouTubeLiveChatResolution = await resolve_video(video_id)
	if not resolution.is_active():
		return resolution
	_begin_polling()
	return resolution


func start_events(video_id: String) -> YouTubeLiveChatResolution:
	var resolution: YouTubeLiveChatResolution = await resolve_video(video_id)
	if not resolution.is_active():
		return resolution
	if prefer_streaming:
		var stream_error: YouTubeApiError = _begin_streaming()
		if stream_error == null:
			return resolution
		error_occurred.emit(stream_error)
		if not fallback_to_polling:
			resolution.status = YouTubeLiveChatResolution.STATUS_ERROR
			resolution.error = stream_error
			_set_state("error")
			return resolution
	_begin_polling()
	return resolution


func poll_once() -> YouTubeLiveChatPage:
	var page: YouTubeLiveChatPage = YouTubeLiveChatPage.new()
	if active_live_chat_id.is_empty() or _chat == null:
		page.error = YouTubeApiError.invalid("No active live chat is selected")
		return page
	var next_token: String = _poll_scheduler.next_page_token()
	var generation: int = _chat_generation
	var cancellation: YouTubeCancellationToken = _cancellation
	page = await _chat.list_messages(active_live_chat_id, next_token, 200, cancellation)
	if generation != _chat_generation or (cancellation != null and cancellation.is_cancelled()):
		var cancelled: YouTubeLiveChatPage = YouTubeLiveChatPage.new()
		cancelled.error = YouTubeApiError.from_transport(ERR_SKIP, "Chat request was superseded")
		return cancelled
	if page.error != null:
		error_occurred.emit(page.error)
		return page
	_deliver_page(page, true)
	return page


func stop_chat(reason: String = "stopped") -> void:
	_chat_generation += 1
	_poll_generation += 1
	_is_polling = false
	_stream_should_fallback = false
	if _stream_source != null and _stream_source.is_active():
		_stream_source.stop(reason)
	if _cancellation != null:
		_cancellation.cancel(reason)
	if _transport != null:
		_transport.cancel_all(reason)
	active_video_id = ""
	active_live_chat_id = ""
	if _poll_scheduler != null:
		_poll_scheduler.reset()
	if _deduplicator != null:
		_deduplicator.clear()
	_set_event_source_mode("stopped")
	if connection_state not in ["unconfigured", "configured", "oauth_configured"]:
		_set_state("connected" if connected_channel != null else "configured")


func clear_local_data(revoke: bool = false) -> YouTubeApiError:
	var first_error: YouTubeApiError = await disconnect_account(revoke)
	if _media != null:
		var media_error: YouTubeApiError = _media.clear_data()
		if first_error == null:
			first_error = media_error
	if _discovery != null:
		_discovery.clear_cache()
	return first_error


func _begin_streaming() -> YouTubeApiError:
	if active_live_chat_id.is_empty():
		return YouTubeApiError.invalid("No active live chat is selected")
	if _stream_source == null:
		_stream_source = YouTubeLiveChatStreamSource.new()
		_stream_source.name = "YouTubeLiveChatStreamSource"
		add_child(_stream_source)
		_stream_source.configure(_api, _chat, _capability_gate)
		_stream_source.page_received.connect(_on_stream_page)
		_stream_source.error_occurred.connect(_on_stream_error)
		_stream_source.stopped.connect(_on_stream_stopped)
	_stream_should_fallback = fallback_to_polling
	_stream_error_category = ""
	var start_error: YouTubeApiError = _stream_source.start(active_live_chat_id, _poll_scheduler.next_page_token(), _cancellation)
	if start_error != null:
		_stream_should_fallback = false
		return start_error
	_set_event_source_mode("streaming")
	_set_state("streaming")
	return null


func _begin_polling() -> void:
	if _is_polling:
		return
	_stream_should_fallback = false
	_is_polling = true
	_poll_generation += 1
	_set_event_source_mode("polling")
	_set_state("polling")
	_poll_loop(_poll_generation, _cancellation)


func _deliver_page(page: YouTubeLiveChatPage, update_poll_schedule: bool) -> void:
	var generation: int = _chat_generation
	if update_poll_schedule:
		var response_contract: Dictionary = {
			"nextPageToken": page.next_page_token,
			"pollingIntervalMillis": page.polling_interval_msec,
			"offlineAt": page.offline_at,
		}
		_poll_scheduler.accept_response(response_contract, Time.get_ticks_msec())
	elif not page.next_page_token.is_empty():
		_poll_scheduler.accept_response({"nextPageToken": page.next_page_token, "pollingIntervalMillis": 0, "offlineAt": page.offline_at}, Time.get_ticks_msec())
	for event: YouTubeLiveEvent in page.events:
		var classification: String = _deduplicator.classify(event)
		if classification == "new":
			event_received.emit(event)
			if generation != _chat_generation:
				return
			_emit_typed_event(event, false)
		elif classification == "update":
			event_updated.emit(event)
			if generation != _chat_generation:
				return
			_emit_typed_event(event, true)
		if generation != _chat_generation:
			return
	_emit_quota()
	if generation != _chat_generation:
		return
	if page.is_terminal():
		_is_polling = false
		_stream_should_fallback = false
		_set_event_source_mode("stopped")
		_set_state("ended")


func _emit_typed_event(event: YouTubeLiveEvent, updated: bool) -> void:
	match event.kind:
		"text_message":
			message_received.emit(event)
		"super_chat", "super_sticker":
			monetization_received.emit(event)
		"membership", "membership_gifting", "gift_membership_received":
			membership_received.emit(event)
		"poll":
			poll_received.emit(event)
		"moderation", "deletion":
			moderation_received.emit(event)
		"gift":
			gift_received.emit(event, updated)
		"system", "terminal":
			system_event_received.emit(event)
		_:
			unknown_event_received.emit(event)


func _emit_quota() -> void:
	quota_changed.emit(_quota.total_units(), _quota.remaining_units())
	for bucket: String in ["youtube_data", "search_queries"]:
		quota_bucket_changed.emit(bucket, _quota.bucket_units(bucket), _quota.bucket_remaining_units(bucket))


func _on_stream_page(page: YouTubeLiveChatPage) -> void:
	_deliver_page(page, false)


func _on_stream_error(error: YouTubeApiError) -> void:
	_stream_error_category = error.category
	error_occurred.emit(error)


func _on_stream_stopped(reason: String) -> void:
	_set_event_source_mode("stopped")
	if _stream_should_fallback and reason in ["stream unavailable", "stream framing failed"] and _stream_error_category not in ["authorization", "denied", "quota_exhausted", "rate_limited", "chat_ended", "failed_precondition", "not_found", "invalid_argument"] and not active_live_chat_id.is_empty():
		_begin_polling()
		return
	_stream_should_fallback = false
	if reason in ["stream unavailable", "stream framing failed", "authorization failed", "quota exhausted"]:
		_set_state("error")


func _poll_loop(generation: int, cancellation: YouTubeCancellationToken) -> void:
	while _is_polling and generation == _poll_generation and cancellation != null and not cancellation.is_cancelled():
		var remaining: int = _poll_scheduler.remaining_msec(Time.get_ticks_msec())
		if remaining > 0:
			await get_tree().create_timer(float(remaining) / 1000.0).timeout
			continue
		var page: YouTubeLiveChatPage = await poll_once()
		if generation != _poll_generation or cancellation.is_cancelled():
			return
		if page.error != null or page.is_terminal():
			_is_polling = false
			break


func _ensure_runtime() -> void:
	if _transport != null:
		return
	_transport = YouTubeHttpTransport.new()
	_transport.name = "YouTubeHttpTransport"
	add_child(_transport)
	_quota = YouTubeQuotaLedger.new(_load_endpoint_contracts(), 10000)
	_api = YouTubeApiClient.new(_transport, _quota)
	_capability_gate = YouTubeCapabilityGate.new()
	_videos = YouTubeVideoService.new(_api)
	_channels = YouTubeChannelService.new(_api, _capability_gate)
	_discovery = YouTubeDiscoveryService.new(_api, _capability_gate)
	_chat = YouTubeLiveChatService.new(_api, _capability_gate)
	_moderation = YouTubeModerationService.new(_api, _capability_gate)
	_broadcasts = YouTubeBroadcastService.new(_api, _capability_gate)
	_streams = YouTubeStreamService.new(_api, _capability_gate)
	_monetization = YouTubeMonetizationService.new(_api, _capability_gate)
	_media = YouTubeMediaCache.new(_transport)
	_media.name = "YouTubeMediaCache"
	add_child(_media)
	_poll_scheduler = YouTubeLiveChatPollScheduler.new()
	_deduplicator = YouTubeEventDeduplicator.new()


func _activate_authorized_api() -> void:
	var error: YouTubeApiError = _api.configure("", _auth.access_token(), _oauth_api_base_url)
	if error != null:
		error_occurred.emit(error)
		_set_state("error")
		return
	connected_channel = _auth.channel
	_granted_capabilities = _auth.granted_capabilities()
	_capability_gate.configure(_granted_capabilities, true)
	_api.set_authorization_preflight(_ensure_fresh_authorization)
	capabilities_changed.emit(_granted_capabilities)
	_set_state("connected")


func _on_auth_state_changed(_previous: String, current: String) -> void:
	if current in ["authorizing", "exchanging", "restoring"]:
		_set_state(current)


func _on_account_connected(channel: YouTubeChannelIdentity, restored: bool) -> void:
	connected_channel = channel
	_granted_capabilities = _auth.granted_capabilities()
	_capability_gate.configure(_granted_capabilities, true)
	account_connected.emit(channel, restored)


func _on_account_disconnected() -> void:
	connected_channel = null
	_granted_capabilities.clear()
	_capability_gate.clear()
	account_disconnected.emit()


func _ensure_fresh_authorization() -> YouTubeApiError:
	if _auth == null:
		return null
	var result: YouTubeAuthResult = await _auth.ensure_fresh_access()
	if result.error != null:
		return result.error
	_api.set_access_token(_auth.access_token())
	return null


func _load_endpoint_contracts() -> Array:
	var file: FileAccess = FileAccess.open(ContractPath, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var endpoints: Variant = parsed.get("endpoints", [])
		return endpoints if endpoints is Array else []
	return []


func _validate_slot(value: String) -> String:
	if value.is_empty() or value.length() > 64:
		return "Session slot must contain 1 to 64 characters"
	var allowed: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
	for character: String in value:
		if not allowed.contains(character):
			return "Session slot may contain only letters, digits, dot, underscore, and hyphen"
	return ""


func _set_state(next_state: String) -> void:
	if connection_state == next_state:
		return
	var previous: String = connection_state
	connection_state = next_state
	connection_state_changed.emit(previous, next_state)


func _set_event_source_mode(next_mode: String) -> void:
	if event_source_mode == next_mode:
		return
	event_source_mode = next_mode
	event_source_changed.emit(next_mode)


func _exit_tree() -> void:
	stop_chat("client freed")
