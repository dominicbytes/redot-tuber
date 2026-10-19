extends SceneTree

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
	var server: TCPServer = TCPServer.new()
	_check(server.listen(0, "127.0.0.1") == OK, "hanging endpoint binds")
	var client: YouTubeLiveClient = YouTubeLiveClient.new()
	root.add_child(client)
	var config: YouTubeOAuthConfig = YouTubeOAuthConfig.new()
	config.client_id = "fixture.apps.googleusercontent.com"
	config.application_id = "stop-chat-regression"
	config.publisher_id = "fixture"
	var store: YouTubeSessionDescriptorStore = YouTubeSessionDescriptorStore.new("res://.test-output/stop-chat-sessions")
	_check(client.configure_oauth(config, PackedStringArray(["chat.read"]), "primary", FakeCredentialProvider.new(), store) == null, "client configures with fake credential provider")
	var transport: YouTubeHttpTransport = client._transport
	transport.max_retries = 0
	transport.max_concurrent_requests = 1
	var url: String = "http://127.0.0.1:%d/hang" % server.get_local_port()
	var unrelated: YouTubeHttpTicket = transport.request(url)
	var chat: YouTubeHttpTicket = _queue_chat(client, url)
	_check(not unrelated.is_completed and not chat.is_completed, "requests are pending")
	client.stop_chat("fixture stop")
	_check(chat.is_completed and chat.is_cancelled, "stop_chat cancels chat request")
	_check(not unrelated.is_completed and transport.active_count() == 1, "stop_chat preserves unrelated request")
	client.begin_account_authorization(false)
	var callback: YouTubeLoopbackCallbackServer = client._auth._oauth._callback_server
	var disconnect_chat: YouTubeHttpTicket = _queue_chat(client, url)
	_check(await client.disconnect_account(false) == null, "local disconnect completes")
	_check(disconnect_chat.is_completed and disconnect_chat.is_cancelled, "disconnect cancels chat request")
	_check(callback.port() == 0, "disconnect closes pending authorization listener")
	_check(client.connected_channel == null and client.connection_state == "oauth_configured", "disconnect clears account state")
	_check(not unrelated.is_completed, "disconnect preserves unrelated request")
	root.remove_child(client)
	_check(unrelated.is_completed and unrelated.is_cancelled, "exit_tree still cancels all outstanding transport work")
	client.free()
	server.stop()
	await process_frame
	if _failures.is_empty():
		print("STOP CHAT ISOLATION PASS: %d checks" % _checks)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)

func _queue_chat(client: YouTubeLiveClient, url: String) -> YouTubeHttpTicket:
	client._cancellation = YouTubeCancellationToken.new()
	client.active_live_chat_id = "fixture-chat"
	return client._transport.request(url, PackedStringArray(), HTTPClient.METHOD_GET, PackedByteArray(), client._cancellation)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
