# Native YouTube `streamList` helper

This standalone Go executable implements Google's documented server-streaming gRPC `V3DataLiveChatMessageService.StreamList` RPC. It is separate from the OS-vault credential helper. Production calls use TLS with certificate and `youtube.googleapis.com` hostname verification against `youtube.googleapis.com:443`; they do not accept an arbitrary destination. The proto2 schema in `stream_list.proto` is adapted from [Google's official guide](https://developers.google.com/youtube/v3/live/streaming-live-chat) under Apache-2.0; see `../../THIRD_PARTY_NOTICES.md` and `licenses/`.

## Reproducible build

Use Go **1.27.1**, the checked-in `go.mod`/`go.sum`, and `CGO_ENABLED=0`. No Go runtime is needed on players' machines. From this directory:

```sh
go mod verify
go test -count=1 ./...
go vet ./...
CGO_ENABLED=0 GOAMD64=v1 GOOS=windows GOARCH=amd64 go build -trimpath -buildvcs=false -ldflags='-s -w' -o ../../addons/redot-tuber/bin/windows/x86_64/redot-tuber-stream-helper.exe .
CGO_ENABLED=0 GOAMD64=v1 GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=false -ldflags='-s -w' -o ../../addons/redot-tuber/bin/linux/x86_64/redot-tuber-stream-helper .
```

On PowerShell, set `CGO_ENABLED`, `GOAMD64`, `GOOS`, and `GOARCH` with `$env:` and invoke the local `go.exe`. The source `.gitattributes` pins LF for the embedded proto and Go files. The final binary checksums are in `addons/redot-tuber/bin/manifest.json`; changing source, toolchain, dependencies, or embedded bytes invalidates them. A Linux-native test/build and exact exported-game test remain separate release gates.

## Private process protocol (`RTSL/1`)

Redot starts the helper with no credential-bearing arguments. One JSON line (maximum 16 KiB) is sent over its private stdin. The request fields are `protocol`, `auth_kind` (`oauth` or `api_key`), `credential`, `live_chat_id`, optional opaque `page_token`, and `idle_timeout_ms`. The helper emits bounded newline-delimited JSON frames (maximum 1 MiB each) on stdout: `page` (REST-shaped chat page), `error` (allowlisted code and optional allowlisted precondition reason), `eof`, or `terminal`. It never echoes the credential or raw gRPC error/trailer text, and intentionally writes no diagnostics to stderr. Redot drains stdout with a per-frame budget, stops its owned PID on cancel/node teardown, and refreshes OAuth/checks quota before each newly launched RPC.

Each protobuf response may contain multiple messages, an independent `activePollItem`, and an opaque `nextPageToken`; the helper maps protobuf enum names and oneof details into Tuber's REST-shaped normalizer input without floating-point conversion of protobuf `uint64`. `offlineAt` and `chatEndedEvent` are terminal; gRPC failures are not synthetic terminal events. Failed precondition reasons expose only the recognized `LIVE_CHAT_DISABLED` or `LIVE_CHAT_ENDED` marker when present in the server detail; arbitrary detail is never emitted. Unknown event types remain generic. The legacy signed `amount_micros`/`ban_duration_seconds` typed fields are retained for in-range values; `amount_micros_exact` and `ban_duration_seconds_exact` preserve the full decimal uint64 range. Gift duration seconds/nanos preserve the protobuf range without narrowing to a nanosecond-based integer.

The default idle watchdog cancels an RPC after 90 seconds without a response. Redot retries up to three times; any valid page resets that counter. Persistent silence then causes configured polling fallback, or an explicit transport error when fallback is disabled. This is a bounded-liveness policy, not a claim that quiet chats are ended or that YouTube promises heartbeats. Each owned helper process also has a 24-hour lifetime cap.

For deterministic tests only, `--test-loopback` permits `endpoint` on `127.0.0.1` or `localhost` with an explicit port and no TLS. Redot sets this only from an editor-only test property; exported games reject it. There is no command-line credential, environment credential, file credential, or production endpoint override.

The Go tests start a real local server-streaming gRPC fixture and cover multiple responses in one RPC, a subprocess, OAuth/API-key metadata, cursor resume, enum/oneof and 64-bit mapping, status sanitization, endpoint/input limits, and process cancellation. The Redot integration harness `addons/redot-tuber/tests/run_native_stream_integration.gd` also requires a separately running local fixture and its non-secret `RTSL_FIXTURE_ENDPOINT`; ordinary Redot suites do not need that environment variable. For a manual run, build a test executable with `go test -c -o <temporary-executable> .`, launch it with `RTSL_FIXTURE_SERVER=1` and `-test.run=TestFixtureServer -test.v`, read its printed `RTSL_ENDPOINT=127.0.0.1:<port>`, set `RTSL_FIXTURE_ENDPOINT`, then run Redot 26.3 with `--headless --path <repo-root> --script res://addons/redot-tuber/tests/run_native_stream_integration.gd --quit-after 10000` under a 20-second wall timeout and isolated profile. Stop the owned fixture process afterward. Never use a production credential with the loopback fixture.

For `run_native_stream_pipe_boundary.gd`, build the same test executable and set both `RTSL_FRAME_FIXTURE_BINARY` to its absolute path and `RTSL_FRAME_EMITTER=1` in Redot's environment. That script starts its own emitter process and tests an exact 1 MiB JSON frame plus LF and a second response through the real OS pipe. Use the same bounded runner and isolated profile, then clear the fixture variables. Test executables and toolchain caches are not shipped.
