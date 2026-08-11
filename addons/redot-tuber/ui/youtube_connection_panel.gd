class_name YouTubeConnectionPanel
extends VBoxContainer

var _client: YouTubeLiveClient = null
var _status: Label = null
var _identity: Label = null
var _authorization_url: LineEdit = null
var _connect_button: Button = null
var _restore_button: Button = null
var _cancel_button: Button = null
var _disconnect_button: Button = null
var _clear_button: Button = null


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var heading: Label = Label.new()
	heading.text = "YouTube connection"
	heading.add_theme_font_size_override("font_size", 20)
	add_child(heading)
	_status = Label.new()
	_status.text = "Status: not configured"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_identity = Label.new()
	_identity.text = "Channel: none"
	add_child(_identity)
	_authorization_url = LineEdit.new()
	_authorization_url.placeholder_text = "Authorization URL appears here if browser launch needs manual recovery"
	_authorization_url.editable = false
	_authorization_url.secret = false
	add_child(_authorization_url)
	var actions: HBoxContainer = HBoxContainer.new()
	add_child(actions)
	_connect_button = _add_button(actions, "Connect", _connect)
	_restore_button = _add_button(actions, "Restore login", _restore)
	_cancel_button = _add_button(actions, "Cancel", _cancel)
	_disconnect_button = _add_button(actions, "Revoke and disconnect", _disconnect)
	_clear_button = _add_button(actions, "Clear local data", _clear_local)
	_refresh_identity()
	_refresh_buttons()


func bind_client(client: YouTubeLiveClient) -> void:
	if _client == client:
		if is_node_ready():
			_refresh_buttons()
		return
	_disconnect_client_signals()
	_client = client
	if not is_node_ready():
		return
	if _client == null:
		_refresh_identity()
		_refresh_buttons()
		return
	_client.connection_state_changed.connect(_on_state_changed)
	_client.authorization_url_ready.connect(_on_authorization_url)
	_client.account_connected.connect(_on_connected)
	_client.account_disconnected.connect(_on_disconnected)
	_client.error_occurred.connect(_on_error)
	_status.text = "Status: " + _client.connection_state
	_refresh_identity()
	_refresh_buttons()


func _connect() -> void:
	if _client != null:
		_client.connect_account()


func _restore() -> void:
	if _client != null:
		_client.restore_account()


func _cancel() -> void:
	if _client != null:
		_client.cancel_account_authorization()


func _disconnect() -> void:
	if _client != null:
		_client.disconnect_account(true)


func _clear_local() -> void:
	if _client != null:
		_client.clear_local_data(false)


func _on_state_changed(_previous: String, current: String) -> void:
	_status.text = "Status: " + current
	_refresh_buttons()


func _on_authorization_url(url: String) -> void:
	_authorization_url.text = url


func _on_connected(channel: YouTubeChannelIdentity, restored: bool) -> void:
	_identity.text = "Channel: %s%s" % [channel.title, " (restored)" if restored else ""]
	_authorization_url.text = ""
	_refresh_buttons()


func _on_disconnected() -> void:
	_identity.text = "Channel: none"
	_authorization_url.text = ""
	_refresh_buttons()


func _on_error(error: YouTubeApiError) -> void:
	_status.text = "Status: %s — %s" % [error.category, error.message]
	_refresh_buttons()


func _refresh_buttons() -> void:
	if _connect_button == null:
		return
	var available: bool = _client != null
	var current: String = _client.connection_state if available else "unconfigured"
	_connect_button.disabled = not available or current not in ["oauth_configured", "configured", "disconnected"]
	_restore_button.disabled = not available or current not in ["oauth_configured", "configured", "disconnected"]
	_cancel_button.disabled = not available or current not in ["authorizing", "exchanging"]
	_disconnect_button.disabled = not available or current != "connected"
	_clear_button.disabled = not available


func _refresh_identity() -> void:
	if _identity == null:
		return
	if _client != null and _client.connected_channel != null:
		_identity.text = "Channel: %s" % _client.connected_channel.title
	else:
		_identity.text = "Channel: none"


func _disconnect_client_signals() -> void:
	if _client == null:
		return
	for pair: Array in [
		[_client.connection_state_changed, _on_state_changed],
		[_client.authorization_url_ready, _on_authorization_url],
		[_client.account_connected, _on_connected],
		[_client.account_disconnected, _on_disconnected],
		[_client.error_occurred, _on_error],
	]:
		var signal_value: Signal = pair[0]
		var callback: Callable = pair[1]
		if signal_value.is_connected(callback):
			signal_value.disconnect(callback)


func _add_button(parent: HBoxContainer, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
