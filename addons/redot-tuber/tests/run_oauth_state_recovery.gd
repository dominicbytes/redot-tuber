extends SceneTree

# Substitute browser/callback I/O so this state test is independent of T2.
class FakeCallbackSession extends YouTubeOAuthSession:
	signal callback_finished(result: YouTubeOAuthCallbackResult)
	var waiting: bool = false
	func launch_authorization() -> YouTubeAuthorizationRequest:
		return prepare_authorization("http://127.0.0.1:49152/oauth2/callback")
	func wait_for_callback() -> YouTubeOAuthCallbackResult:
		waiting = true
		return await callback_finished
	func cancel_authorization(reason: String = "cancelled") -> void:
		super.cancel_authorization(reason)
		if waiting:
			waiting = false
			var result: YouTubeOAuthCallbackResult = YouTubeOAuthCallbackResult.new()
			result.error = YouTubeApiError.custom("cancelled", reason)
			callback_finished.emit(result)

class FakeTokenTransport extends YouTubeHttpTransport:
	func request(_url: String, _headers: PackedStringArray = PackedStringArray(), _method: int = HTTPClient.METHOD_GET, _body: PackedByteArray = PackedByteArray(), _cancellation: YouTubeCancellationToken = null) -> YouTubeHttpTicket:
		var ticket: YouTubeHttpTicket = YouTubeHttpTicket.new()
		var response: YouTubeHttpResponse = YouTubeHttpResponse.new()
		response.request_result = HTTPRequest.RESULT_SUCCESS
		response.status_code = 200
		response.parsed_json = {"access_token": "fixture-access", "expires_in": 3600}
		ticket._complete(response)
		return ticket

var _checks: int = 0
var _failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var client: YouTubeLiveClient = YouTubeLiveClient.new()
	root.add_child(client)
	var config: YouTubeOAuthConfig = YouTubeOAuthConfig.new()
	config.client_id = "fixture.apps.googleusercontent.com"
	config.application_id = "state-regression"
	config.publisher_id = "fixture"
	var store: YouTubeSessionDescriptorStore = YouTubeSessionDescriptorStore.new("res://.test-output/state-sessions")
	store.delete_descriptor("first-run")
	_check(client.configure_oauth(config, PackedStringArray(["chat.read"]), "first-run", null, store) == null, "client configures")
	var panel: YouTubeConnectionPanel = YouTubeConnectionPanel.new()
	root.add_child(panel)
	panel.bind_client(client)
	var restored: YouTubeAuthResult = await client.restore_account()
	_check(restored.error != null and restored.error.category == "not_found", "first-run restore reports no saved session")
	_check(client._auth.state == "configured", "auth rolls back missing-session restore")
	_check_ready(client, panel, "first-run restore")
	var request: YouTubeAuthorizationRequest = client.begin_account_authorization(false, "invalid")
	_check(request.error != null, "invalid callback fails authorization setup")
	_check_ready(client, panel, "failed setup")
	client.begin_account_authorization(false, "http://127.0.0.1:49152/oauth2/callback")
	var invalid: YouTubeAuthResult = await client.complete_account_authorization("")
	_check(invalid.error != null, "empty authorization code fails")
	_check_ready(client, panel, "invalid exchange")
	client._auth._oauth.free()
	var session: FakeCallbackSession = FakeCallbackSession.new()
	session.configure(config, PackedStringArray(["chat.read"]))
	client._auth.add_child(session)
	client._auth._oauth = session
	var pending: Dictionary = {"done": false, "result": null}
	_connect(client, pending)
	_check(client.connection_state == "authorizing" and panel._connect_button.disabled, "connect becomes busy")
	client.cancel_account_authorization()
	_check(pending.done and pending.result.error.category == "cancelled", "cancelled callback resumes connect")
	_check_ready(client, panel, "cancel during connect")
	var transport: FakeTokenTransport = FakeTokenTransport.new()
	client.add_child(transport)
	client._auth._tokens = YouTubeOAuthTokenClient.new(transport)
	client.begin_account_authorization(false, "http://127.0.0.1:49152/oauth2/callback")
	var failed: YouTubeAuthResult = await client.complete_account_authorization("fixture-code")
	_check(failed.error != null and failed.error.category == "persistence_unavailable", "accepted token without refresh token fails persistence")
	_check(client._auth.state == "configured", "token acceptance failure resets auth")
	_check_ready(client, panel, "token acceptance failure")
	client.connected_channel = YouTubeChannelIdentity.new()
	client._set_state("restoring")
	client._on_auth_state_changed("restoring", "configured")
	_check(client.connection_state == "connected", "rollback retains an existing connected channel")
	client._set_state("polling")
	client._on_auth_state_changed("connected", "configured")
	_check(client.connection_state == "polling", "unrelated chat state is preserved")
	panel.free()
	client.free()
	await process_frame
	if _failures.is_empty():
		print("OAUTH STATE RECOVERY PASS: %d checks" % _checks)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)

func _connect(client: YouTubeLiveClient, pending: Dictionary) -> void:
	pending.result = await client.connect_account()
	pending.done = true

func _check_ready(client: YouTubeLiveClient, panel: YouTubeConnectionPanel, label: String) -> void:
	_check(client.connection_state == "oauth_configured", label + " resets facade state")
	_check(not panel._connect_button.disabled and not panel._restore_button.disabled, label + " enables connection controls")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
