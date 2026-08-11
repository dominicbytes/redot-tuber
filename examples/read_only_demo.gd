extends Control

var _client: YouTubeLiveClient
var _connection_panel: YouTubeConnectionPanel
var _fields: Dictionary = {}
var _confirm: CheckBox
var _status: Label
var _log: RichTextLabel
var _redactor: YouTubeRedactor = YouTubeRedactor.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_client()
	_build_ui()


func _create_client() -> void:
	_client = YouTubeLiveClient.new()
	_client.name = "YouTubeLiveClient"
	add_child(_client)
	_client.connection_state_changed.connect(_on_state_changed)
	_client.event_source_changed.connect(func(mode: String) -> void: _append("Event source: %s" % mode))
	_client.live_chat_resolved.connect(_on_live_chat_resolved)
	_client.event_received.connect(_on_event_received)
	_client.event_updated.connect(func(event: YouTubeLiveEvent) -> void: _append("update | %s | %s" % [event.kind, event.display_message]))
	_client.quota_bucket_changed.connect(func(bucket: String, used: int, remaining: int) -> void: _append("quota | %s | used %d | remaining %d" % [bucket, used, remaining]))
	_client.error_occurred.connect(_on_error)


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)
	var heading: Label = Label.new()
	heading.text = "Redot Tuber integration lab"
	heading.add_theme_font_size_override("font_size", 24)
	outer.add_child(heading)
	var note: Label = Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Developer-owned credentials stay in memory; refresh tokens use the operating-system vault. Destructive actions require the confirmation box. Use a controlled test broadcast."
	outer.add_child(note)
	_status = Label.new()
	_status.text = "State: unconfigured | source: stopped"
	outer.add_child(_status)

	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)
	_build_connect_tab(_tab(tabs, "Connect"))
	_build_discovery_tab(_tab(tabs, "Discover"))
	_build_chat_tab(_tab(tabs, "Chat & moderation"))
	_build_broadcast_tab(_tab(tabs, "Broadcasts"))
	_build_stream_tab(_tab(tabs, "Streams"))
	_build_log_tab(_tab(tabs, "Log"))


func _build_connect_tab(parent: VBoxContainer) -> void:
	_heading(parent, "Public/API-key mode")
	_field(parent, "api_key", "Developer-owned YouTube Data API key", true)
	_field(parent, "video_id", "Known live video ID")
	var public_actions: HBoxContainer = _row(parent)
	_button(public_actions, "Configure public", _configure_public)
	_button(public_actions, "Start events", _start_events)
	_button(public_actions, "Stop events", func() -> void: _client.stop_chat("integration lab stop"))

	_separator(parent)
	_heading(parent, "Authorized account mode")
	_field(parent, "oauth_client_id", "Google Desktop OAuth client ID")
	_field(parent, "publisher_id", "Stable publisher ID", false, "example.publisher")
	_field(parent, "application_id", "Stable application ID", false, "redot-tuber-lab")
	_field(parent, "session_slot", "Persistent session slot", false, "integration-lab")
	_field(parent, "capabilities", "Comma-separated capabilities", false, ",".join(YouTubeScopeRegistry.new().all_capabilities()))
	_button(parent, "Configure OAuth", _configure_oauth)
	_connection_panel = YouTubeConnectionPanel.new()
	_connection_panel.name = "YouTubeConnectionPanel"
	_connection_panel.bind_client(_client)
	parent.add_child(_connection_panel)


func _build_discovery_tab(parent: VBoxContainer) -> void:
	_heading(parent, "Manual, quota-aware discovery")
	_field(parent, "channel_handle", "YouTube handle, with or without @")
	_button(parent, "Resolve channel handle", _resolve_channel)
	_field(parent, "search_query", "Live-video search text")
	_field(parent, "search_event_type", "live, upcoming, or completed", false, "live")
	var search_actions: HBoxContainer = _row(parent)
	_button(search_actions, "Search live videos", _search_live)
	_button(search_actions, "Clear discovery cache", func() -> void: _client.discovery_service().clear_cache(); _append("Discovery cache cleared"))
	_separator(parent)
	var owned_actions: HBoxContainer = _row(parent)
	_button(owned_actions, "List my broadcasts", _list_broadcasts)
	_button(owned_actions, "List my streams", _list_streams)
	_button(owned_actions, "List recent Super Chats", _list_super_chats)


func _build_chat_tab(parent: VBoxContainer) -> void:
	_heading(parent, "Chat and polls")
	_field(parent, "chat_id", "Live chat ID (filled after video resolution)")
	_field(parent, "chat_message", "Message text")
	_button(parent, "Send chat message", _send_chat)
	_field(parent, "poll_question", "Poll question")
	_field(parent, "poll_options", "Poll options separated by |", false, "Option A|Option B")
	var poll_actions: HBoxContainer = _row(parent)
	_button(poll_actions, "Create poll", _create_poll)
	_field(parent, "poll_message_id", "Poll message ID to close")
	_button(parent, "Close poll", _close_poll)

	_separator(parent)
	_heading(parent, "Moderation")
	_field(parent, "message_id", "Chat message ID to delete")
	_button(parent, "Delete message", _delete_message)
	_field(parent, "target_channel_id", "Target viewer/moderator channel ID")
	_field(parent, "ban_type", "permanent or temporary", false, "temporary")
	_field(parent, "ban_duration", "Temporary ban duration in seconds", false, "300")
	var ban_actions: HBoxContainer = _row(parent)
	_button(ban_actions, "Ban / timeout", _ban_user)
	_field(parent, "ban_id", "Ban resource ID to remove")
	_button(parent, "Remove ban", _unban_user)
	var moderator_actions: HBoxContainer = _row(parent)
	_button(moderator_actions, "List moderators", _list_moderators)
	_button(moderator_actions, "Add target as moderator", _add_moderator)
	_field(parent, "moderator_id", "Moderator resource ID to remove")
	_button(parent, "Remove moderator", _remove_moderator)


func _build_broadcast_tab(parent: VBoxContainer) -> void:
	_heading(parent, "Broadcast CRUD and lifecycle")
	_field(parent, "broadcast_id", "Broadcast ID")
	_field(parent, "broadcast_title", "Broadcast title", false, "Redot Tuber test")
	_field(parent, "broadcast_description", "Broadcast description")
	_field(parent, "scheduled_start", "ISO 8601 scheduled start, in the future")
	_field(parent, "privacy_status", "private, unlisted, or public", false, "unlisted")
	var crud: HBoxContainer = _row(parent)
	_button(crud, "Create broadcast", _create_broadcast)
	_button(crud, "Update snippet", _update_broadcast)
	_button(crud, "Delete broadcast", _delete_broadcast)
	_separator(parent)
	_field(parent, "bound_stream_id", "Stream ID to bind; blank unbinds")
	_button(parent, "Bind / unbind stream", _bind_stream)
	_field(parent, "current_broadcast_status", "Current lifecycle status", false, "ready")
	_field(parent, "target_broadcast_status", "testing, live, or complete", false, "testing")
	_button(parent, "Transition broadcast", _transition_broadcast)
	_field(parent, "cue_duration", "Ad cuepoint duration seconds", false, "30")
	_button(parent, "Insert immediate ad cuepoint", _insert_cuepoint)


func _build_stream_tab(parent: VBoxContainer) -> void:
	_heading(parent, "Live stream CRUD")
	_field(parent, "stream_id", "Stream ID")
	_field(parent, "stream_title", "Stream title", false, "Redot Tuber encoder")
	_field(parent, "stream_description", "Stream description")
	_field(parent, "ingestion_type", "Ingestion type", false, "rtmp")
	_field(parent, "resolution", "Resolution", false, "1080p")
	_field(parent, "frame_rate", "Frame rate", false, "60fps")
	var actions: HBoxContainer = _row(parent)
	_button(actions, "Create stream", _create_stream)
	_button(actions, "Update snippet", _update_stream)
	_button(actions, "Delete stream", _delete_stream)
	var privacy_note: Label = Label.new()
	privacy_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy_note.text = "The returned ingestion stream name is sensitive, remains memory-only, and is intentionally never printed in this lab."
	parent.add_child(privacy_note)


func _build_log_tab(parent: VBoxContainer) -> void:
	_confirm = CheckBox.new()
	_confirm.text = "Confirm the next destructive or account-impacting action"
	parent.add_child(_confirm)
	var actions: HBoxContainer = _row(parent)
	_button(actions, "Clear log", func() -> void: _log.clear())
	_button(actions, "Clear all local Redot Tuber data", _clear_all_data)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.custom_minimum_size = Vector2(0, 300)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_log)


func _configure_public() -> void:
	var error: YouTubeApiError = _client.configure_public(_text("api_key"), _text("session_slot", "public-lab"))
	_log_error_or("Public API configured", error)


func _configure_oauth() -> void:
	var config: YouTubeOAuthConfig = YouTubeOAuthConfig.new()
	config.client_id = _text("oauth_client_id")
	config.publisher_id = _text("publisher_id")
	config.application_id = _text("application_id")
	var capabilities: PackedStringArray = PackedStringArray()
	for value: String in _text("capabilities").split(",", false):
		var capability: String = value.strip_edges()
		if not capability.is_empty() and not capabilities.has(capability):
			capabilities.append(capability)
	var error: YouTubeApiError = _client.configure_oauth(config, capabilities, _text("session_slot", "integration-lab"))
	_log_error_or("OAuth configured; use Connect or Restore login", error)


func _start_events() -> void:
	var resolution: YouTubeLiveChatResolution = await _client.start_events(_text("video_id"))
	if resolution.error != null:
		_on_error(resolution.error)


func _resolve_channel() -> void:
	var result: YouTubeChannelResult = await _client.channel_service().get_by_handle(_text("channel_handle"))
	if result.error != null:
		_on_error(result.error)
	else:
		_append("Channel: %s | %s" % [result.channel.id, result.channel.title])


func _search_live() -> void:
	var page: YouTubeApiPage = await _client.discovery_service().search_live_videos(_text("search_query"), _text("search_event_type", "live"))
	_log_page("Search", page)


func _list_broadcasts() -> void:
	_log_page("Broadcasts", await _client.broadcast_service().list_broadcasts())


func _list_streams() -> void:
	_log_page("Streams", await _client.stream_service().list_streams())


func _list_super_chats() -> void:
	_log_page("Super Chats", await _client.monetization_service().list_super_chat_events())


func _send_chat() -> void:
	_log_operation("Send chat", await _client.live_chat_service().send_text(_chat_id(), _text("chat_message")))


func _create_poll() -> void:
	var options: PackedStringArray = PackedStringArray()
	for value: String in _text("poll_options").split("|", false):
		options.append(value.strip_edges())
	_log_operation("Create poll", await _client.live_chat_service().create_poll(_chat_id(), _text("poll_question"), options))


func _close_poll() -> void:
	_log_operation("Close poll", await _client.live_chat_service().close_poll(_text("poll_message_id"), _take_confirmation()))


func _delete_message() -> void:
	_log_operation("Delete message", await _client.moderation_service().delete_message(_text("message_id"), _take_confirmation()))


func _ban_user() -> void:
	_log_operation("Ban user", await _client.moderation_service().ban_user(_chat_id(), _text("target_channel_id"), _text("ban_type", "temporary"), int(_text("ban_duration", "300")), _take_confirmation()))


func _unban_user() -> void:
	_log_operation("Remove ban", await _client.moderation_service().unban_user(_text("ban_id"), _take_confirmation()))


func _list_moderators() -> void:
	_log_page("Moderators", await _client.moderation_service().list_moderators(_chat_id()))


func _add_moderator() -> void:
	_log_operation("Add moderator", await _client.moderation_service().add_moderator(_chat_id(), _text("target_channel_id"), _take_confirmation()))


func _remove_moderator() -> void:
	_log_operation("Remove moderator", await _client.moderation_service().remove_moderator(_text("moderator_id"), _take_confirmation()))


func _create_broadcast() -> void:
	var broadcast: YouTubeLiveBroadcast = _broadcast_form()
	_log_operation("Create broadcast", await _client.broadcast_service().create_broadcast(broadcast))


func _update_broadcast() -> void:
	var broadcast: YouTubeLiveBroadcast = _broadcast_form()
	broadcast.id = _text("broadcast_id")
	_log_operation("Update broadcast", await _client.broadcast_service().update_broadcast(broadcast, PackedStringArray(["snippet"])))


func _delete_broadcast() -> void:
	_log_operation("Delete broadcast", await _client.broadcast_service().delete_broadcast(_text("broadcast_id"), _take_confirmation()))


func _bind_stream() -> void:
	_log_operation("Bind stream", await _client.broadcast_service().bind_stream(_text("broadcast_id"), _text("bound_stream_id"), _take_confirmation()))


func _transition_broadcast() -> void:
	_log_operation("Transition broadcast", await _client.broadcast_service().transition_broadcast(_text("broadcast_id"), _text("target_broadcast_status"), _text("current_broadcast_status"), _take_confirmation()))


func _insert_cuepoint() -> void:
	_log_operation("Insert cuepoint", await _client.broadcast_service().insert_cuepoint(_text("broadcast_id"), _take_confirmation(), int(_text("cue_duration", "30"))))


func _create_stream() -> void:
	_log_operation("Create stream", await _client.stream_service().create_stream(_stream_form()))


func _update_stream() -> void:
	var stream: YouTubeLiveStream = _stream_form()
	stream.id = _text("stream_id")
	_log_operation("Update stream", await _client.stream_service().update_stream(stream, PackedStringArray(["snippet"])))


func _delete_stream() -> void:
	_log_operation("Delete stream", await _client.stream_service().delete_stream(_text("stream_id"), _take_confirmation()))


func _clear_all_data() -> void:
	if not _take_confirmation():
		_append("Clear all data: confirmation required")
		return
	_log_error_or("All local Redot Tuber data cleared", await _client.clear_local_data(false))


func _broadcast_form() -> YouTubeLiveBroadcast:
	var broadcast: YouTubeLiveBroadcast = YouTubeLiveBroadcast.new()
	broadcast.title = _text("broadcast_title")
	broadcast.description = _text("broadcast_description")
	broadcast.scheduled_start_time = _text("scheduled_start")
	broadcast.privacy_status = _text("privacy_status", "unlisted")
	return broadcast


func _stream_form() -> YouTubeLiveStream:
	var stream: YouTubeLiveStream = YouTubeLiveStream.new()
	stream.title = _text("stream_title")
	stream.description = _text("stream_description")
	stream.ingestion_type = _text("ingestion_type", "rtmp")
	stream.resolution = _text("resolution", "1080p")
	stream.frame_rate = _text("frame_rate", "60fps")
	return stream


func _chat_id() -> String:
	return _text("chat_id") if not _text("chat_id").is_empty() else _client.active_live_chat_id


func _on_state_changed(_previous: String, current: String) -> void:
	_status.text = "State: %s | source: %s" % [current, _client.event_source_mode]


func _on_live_chat_resolved(resolution: YouTubeLiveChatResolution) -> void:
	_fields.chat_id.text = resolution.live_chat_id
	_append("Video: %s | %s | chat %s" % [resolution.title, resolution.status, resolution.live_chat_id])


func _on_event_received(event: YouTubeLiveEvent) -> void:
	var author_name: String = event.author.display_name if event.author != null else "system"
	_append("event | %s | %s | %s" % [event.kind, author_name, event.display_message])


func _on_error(error: YouTubeApiError) -> void:
	_status.text = "Error: %s | source: %s" % [error.category, _client.event_source_mode]
	_append("[color=red]%s: %s[/color]" % [error.category, _redactor.redact_text(error.message)])


func _log_operation(label: String, result: YouTubeOperationResult) -> void:
	if result.error != null:
		_on_error(result.error)
		return
	_append("%s succeeded | %s" % [label, _describe(result.value)])


func _log_page(label: String, page: YouTubeApiPage) -> void:
	if page.error != null:
		_on_error(page.error)
		return
	_append("%s: %d item(s)%s" % [label, page.items.size(), " (cache)" if page.from_cache else ""])
	for item: Variant in page.items:
		_append("  " + _describe(item))


func _describe(value: Variant) -> String:
	if value is YouTubeLiveBroadcast:
		return "broadcast %s | %s | %s" % [value.id, value.title, value.life_cycle_status]
	if value is YouTubeLiveStream:
		return "stream %s | %s | %s" % [value.id, value.title, value.stream_status]
	if value is YouTubeDiscoveryItem:
		return "%s %s | %s" % [value.resource_type, value.id, value.title]
	if value is YouTubeLiveChatModerator:
		return "moderator %s | %s" % [value.id, value.display_name]
	if value is YouTubeSuperChatEvent:
		return "Super Chat %s | %s | %s" % [value.id, value.supporter_display_name, value.display_string]
	if value is YouTubeLiveEvent:
		return "event %s | %s" % [value.id, value.kind]
	if value is YouTubeLiveChatBan:
		return "ban %s | %s" % [value.id, value.ban_type]
	return "complete" if value == true else str(value)


func _take_confirmation() -> bool:
	var confirmed: bool = _confirm != null and _confirm.button_pressed
	if _confirm != null:
		_confirm.button_pressed = false
	return confirmed


func _log_error_or(success_text: String, error: YouTubeApiError) -> void:
	if error != null:
		_on_error(error)
	else:
		_append(success_text)


func _append(text: String) -> void:
	if _log != null:
		_log.append_text(text + "\n")


func _text(key: String, fallback: String = "") -> String:
	if not _fields.has(key):
		return fallback
	var value: String = (_fields[key] as LineEdit).text.strip_edges()
	return fallback if value.is_empty() else value


func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)
	return content


func _field(parent: VBoxContainer, key: String, placeholder: String, secret: bool = false, default_value: String = "") -> LineEdit:
	var field: LineEdit = LineEdit.new()
	field.placeholder_text = placeholder
	field.text = default_value
	field.secret = secret
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	_fields[key] = field
	return field


func _heading(parent: VBoxContainer, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	parent.add_child(label)


func _row(parent: VBoxContainer) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row


func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _separator(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
