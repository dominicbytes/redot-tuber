# MS-001 transport, quota, and data contract

This contract was checked against official Google/YouTube documentation on 2026-08-10. The executable runtime contract is `res://addons/redot-tuber/contracts/youtube_api_contract.json`.

## Transport decision

- Historical fixture assumption (not a verified service protocol): `liveChatMessages.streamList` was represented as a sequence of JSON response objects. The offline framer accepts arbitrary byte boundaries, multiple responses per chunk, whitespace between responses, UTF-8 content, cancellation, and a fixed maximum buffered-byte limit. Passing this fixture does not prove compatibility with Google's documented streaming RPC; the production streaming transport remains blocked.
- `nextPageToken` is the resume cursor. A reconnect starts from the last completely parsed response; partial response bytes are never treated as a new cursor.
- This proves the parser and state contract only. It does not certify Redot's live HTTP wire behavior against Google. Until that live gate passes, the public client must be able to use `liveChatMessages.list`.
- Polling stores the returned `nextPageToken` and never permits the next call before `pollingIntervalMillis`. `offlineAt` and `chatEndedEvent` are terminal.
- Replayed message IDs are suppressed. The documented `giftEvent` ID reuse is classified as an update when its payload changes.

## Event compatibility

All message types listed by the current resource page have explicit dispositions. Both `pollEvent` and the page's `pollDetails` spelling are accepted because the official page currently uses both names in different sections. Unknown future message types emit a generic unknown event and do not stop the connection.

## Quota behavior

The current quota page states that every request costs at least one unit and that Live Streaming methods consume YouTube Data API quota, but its rendered table does not expose individual Live Streaming rows. The fixture therefore marks video/channel read costs that have method-page evidence as `official` and marks Live method values as estimates requiring Cloud Console verification. Runtime accounting rejects unclassified methods rather than silently treating them as free.

## Data lifecycle

Refresh tokens are OS-vault-only. Access tokens, PKCE verifiers, OAuth state, authorization codes, chat messages, stream ingestion names, and ordinary diagnostics are not written to disk. The only persistent non-secret auth record is a minimal versioned session descriptor and approved channel identity. Optional remote-media persistence is disabled by default and, when enabled, is restricted to the bounded/clearable policy in `docs/data-lifecycle.md`.

## Primary sources

- https://developers.google.com/youtube/v3/live/docs/liveChatMessages
- https://developers.google.com/youtube/v3/live/docs/liveChatMessages/streamList
- https://developers.google.com/youtube/v3/live/docs/liveChatMessages/list
- https://developers.google.com/youtube/v3/live/docs
- https://developers.google.com/youtube/v3/determine_quota_cost
- https://developers.google.com/identity/protocols/oauth2/native-app
- https://developers.google.com/youtube/terms/developer-policies
