# Credential helper protocol (`RTCH/1`)

The helper receives exactly one four-line request on standard input and returns exactly one four-line response on standard output. No secret is passed in process arguments, environment variables, files, or logs.

Request:

```text
RTCH/1
ping|store|read|delete
BASE64_UTF8_TARGET
BASE64_UTF8_SECRET_OR_EMPTY
```

Response:

```text
RTCH/1
OK|NOT_FOUND|UNAVAILABLE|LOCKED|DENIED|PROTOCOL_ERROR
BASE64_UTF8_SECRET_OR_EMPTY
SAFE_NON_SECRET_DETAIL_OR_EMPTY
```

Limits are 512 target bytes and 4096 secret bytes. Each invocation handles one operation and exits. `store` replaces the target atomically according to the operating-system store. `read` returns a secret only on `OK`; all other statuses have an empty payload. Games must delete the corresponding descriptor and vault entry during clear-data/disconnect.

Windows stores a generic credential named `RedotTuber:<publisher>/<application>/<slot>` through `CredWriteW`, `CredReadW`, and `CredDeleteW`. Linux uses the default Secret Service collection through libsecret with the same target attribute. Neither implementation has a plaintext fallback.
