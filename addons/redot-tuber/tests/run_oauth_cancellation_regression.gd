extends SceneTree

class HeadlessOAuthSession extends YouTubeOAuthSession:
	func launch_authorization() -> YouTubeAuthorizationRequest:
		return prepare_authorization()

class FakeCredentialProvider extends RefCounted:
	func delete(_target: String, _cancellation: Variant = null) -> YouTubeCredentialResult:
		var result: YouTubeCredentialResult = YouTubeCredentialResult.new()
		result.status = "not_found"
		return result

var _checks: int = 0
var _failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	for action: String in ["cancel", "replace", "disconnect"]:
		await _test_connect_cancellation(action)
	if _failures.is_empty():
		print("OAUTH CANCELLATION PASS: %d checks" % _checks)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)

func _test_connect_cancellation(action: String) -> void:
	var client: YouTubeLiveClient = YouTubeLiveClient.new()
	root.add_child(client)
	var config: YouTubeOAuthConfig = YouTubeOAuthConfig.new()
	config.client_id = "fixture.apps.googleusercontent.com"
	config.application_id = "cancel-regression"
	config.publisher_id = "fixture"
	var store: YouTubeSessionDescriptorStore = YouTubeSessionDescriptorStore.new("res://.test-output/cancel-sessions")
	_check(client.configure_oauth(config, PackedStringArray(["chat.read"]), action, FakeCredentialProvider.new(), store) == null, action + " configures")
	var auth: YouTubeAuthManager = client._auth
	auth._oauth.free()
	var session: HeadlessOAuthSession = HeadlessOAuthSession.new()
	_check(session.configure(config, PackedStringArray(["chat.read"])) == null, action + " configures headless browser seam")
	auth.add_child(session)
	auth._oauth = session
	var pending: Dictionary = {"done": false, "result": null}
	_connect(client, pending)
	await process_frame
	_check(not pending.done and auth.state == "authorizing", action + " waits for callback")
	var server: YouTubeLoopbackCallbackServer = session._callback_server
	var emissions: Array[YouTubeOAuthCallbackResult] = []
	server.result_received.connect(func(result: YouTubeOAuthCallbackResult) -> void: emissions.append(result))
	if action == "cancel":
		client.cancel_account_authorization()
	elif action == "replace":
		_check(auth.begin_authorization(false).is_valid(), "replacement authorization starts")
	else:
		_check(await client.disconnect_account(false) == null, "disconnect completes with fake credentials")
	_check(server.port() == 0, action + " closes listener before completion")
	_check(emissions.size() == 1, action + " emits exactly one terminal result")
	if emissions.size() == 1:
		_check(emissions[0].error != null and emissions[0].error.category == "cancelled", action + " reports cancellation")
		_check(not emissions[0].error.message.is_empty(), action + " preserves reason")
	for _frame: int in 5:
		await process_frame
	_check(pending.done, action + " resumes connect_account")
	if pending.done:
		var result: YouTubeAuthResult = pending.result
		_check(result.error != null and result.error.category == "cancelled", action + " returns typed cancellation")
	if action == "replace":
		_check(session.pending_verifier_length_for_test() >= 43, "replacement retains fresh PKCE verifier")
	else:
		_check(session.pending_verifier_length_for_test() == 0, action + " clears PKCE verifier")
	client.free()
	await process_frame

func _connect(client: YouTubeLiveClient, pending: Dictionary) -> void:
	pending.result = await client.connect_account()
	pending.done = true

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
