# Runtime YouTube account connection

Redot Tuber uses Google's installed-app authorization-code flow with PKCE. Each game developer or publisher owns the Google Cloud project, consent screen, OAuth desktop client, quota, verification process, privacy policy, support channel, and incident response for the game they ship. Redot Tuber does not provide a shared production client ID.

## Google Cloud setup

1. Create or select a Google Cloud project and enable YouTube Data API v3.
2. Configure the OAuth consent screen, publisher/contact details, privacy policy, and test users as required for the scopes and publication state.
3. Create an OAuth client of type **Desktop app**. Copy its client ID. Do not distribute or configure a client secret; installed apps cannot keep one confidential and Redot Tuber has no client-secret field.
4. Start with the narrowest Redot Tuber capability set your game needs. Review [the capability matrix](capability-matrix.md). Adding write, moderation, broadcast, or stream-management capabilities changes the requested Google scope and may change verification requirements.
5. Test with a dedicated channel and unlisted/private broadcasts before requesting production verification.

## Typed GDScript setup

```gdscript
var youtube := YouTubeLiveClient.new()
add_child(youtube)

var oauth := YouTubeOAuthConfig.new()
oauth.client_id = runtime_client_id
oauth.publisher_id = "your-stable-publisher-id"
oauth.application_id = "com.example.your-game"

var error := youtube.configure_oauth(
	oauth,
	PackedStringArray(["channel.read", "chat.read", "chat.write"]),
	"primary-channel"
)
if error == null:
	var restored := await youtube.restore_account()
	if not restored.is_success() and restored.error.category == "not_found":
		var connected := await youtube.connect_account()
```

The game opens the system browser. Redot Tuber creates a high-entropy state value and PKCE-S256 verifier/challenge, listens on an ephemeral `127.0.0.1` port, accepts only `/oauth2/callback`, validates state before releasing the authorization code, and exchanges the code without a client secret. If browser launch fails, `authorization_url_ready` still exposes the URL for a game-provided copy/paste recovery control; ordinary diagnostics do not log it.

## Persistent login

After authorization, the access token remains only in the `YouTubeAuthManager` associated with that `YouTubeLiveClient`. The refresh token is sent through standard input to the versioned credential helper and stored as:

- Windows x86-64: a generic credential in Windows Credential Manager.
- Linux x86-64: an item in the default Secret Service collection through libsecret.

`user://redot-tuber/sessions/<slot>.json` stores only a schema version, credential-record target, granted capability/scope summary, and minimal channel identity. It never contains an access token, refresh token, authorization code, PKCE verifier, OAuth state, API key, or client secret. If the helper or OS vault is absent, locked, denied, corrupt, or protocol-incompatible, connection/restore fails with a typed status; there is no plaintext fallback.

Each live `YouTubeLiveClient` leases one qualified session slot. Two clients may connect different slots/accounts, while duplicate use of the same publisher/application/slot is rejected until its owner disconnects or is freed.

## Disconnect and user data

`await youtube.disconnect_account(true)` attempts Google token revocation, then deletes the matching OS-vault record and non-secret descriptor even if remote revocation fails. `await youtube.disconnect_account(false)` performs local clear-data without claiming that the Google grant was revoked. Both clear access-token/channel/capability memory and affect only that client's slot.

`await youtube.clear_local_data(true)` adds removal of Redot Tuber's discovery and optional remote-media caches. It cannot remove data that the integrating game copied to its own saves, telemetry, servers, moderation records, or logs.

## Current certification boundary

The Windows x86-64 helper is built and has passed real Credential Manager store/read/replace/delete tests. The Linux x86-64 helper is built with strict warnings, is an amd64 ELF, and returns the typed `UNAVAILABLE` response when run without a desktop Secret Service. A real Linux desktop/keyring test and a live Google OAuth verification matrix still require their respective external environments before a public stable release.
