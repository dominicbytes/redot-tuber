# Redot Tuber

Redot Tuber is a standalone, typed-GDScript YouTube Live addon for Redot. It lets a game use a developer-owned YouTube Data API application, ask a consenting channel owner to connect their account at runtime, receive typed live events, and perform capability-gated YouTube Live actions.

The MS-001 through MS-005 implementation is complete on Redot `26.2.stable.official.4f5b14aba`. It includes:

- public API-key discovery and live-chat reads;
- Google installed-app OAuth with PKCE, state validation, and an IPv4 loopback callback;
- persistent per-game/per-account sessions backed by Windows Credential Manager or Linux Secret Service, with no plaintext token fallback;
- preferred incremental `streamList` delivery with compliant `list` polling fallback;
- typed messages, Super Chats/Stickers, memberships, gifts, polls, moderation, system, and unknown events;
- chat and poll writes, moderation and moderator management, broadcast/stream CRUD, binding, transitions, cuepoints, and recent Super Chat history;
- capability/scope checks, explicit destructive-action confirmation, quota budgets, redacted diagnostics, and a bounded optional media cache;
- a full integration-lab scene covering public and authorized workflows.

This is currently a development build, not a certified stable release. Real Google consent/account-side testing and Linux desktop Secret Service certification remain MS-006 gates. Windows and Linux x86-64 are the initial targets; macOS and ARM64 follow later.

## Try the integration lab

1. Open this folder in Redot 26.2 and enable **Redot Tuber** in plugin settings.
2. Run the project. The main scene is the integration lab at `examples/read_only_demo.tscn` (the filename is retained for compatibility).
3. For public reads, enter a restricted developer-owned YouTube Data API key.
4. For account features, create a Google **Desktop app** OAuth client and follow [OAuth setup](docs/oauth-setup.md).
5. Select only the capabilities your game actually needs. Destructive actions also require the lab's confirmation control.

Never place API keys, OAuth tokens, client secrets, or stream ingestion names in source, scenes, resources, export presets, or `project.godot`.

## Documentation

- [Read-only quickstart](docs/read-only-quickstart.md)
- [OAuth setup and persistent login](docs/oauth-setup.md)
- [API reference](docs/api-reference.md)
- [Capability matrix](docs/capability-matrix.md)
- [Data lifecycle](docs/data-lifecycle.md)
- [Development release readiness](docs/release-readiness.md)
- [Implementation plan and status](docs/gamedev/implementation-plan.md)
- [Twitcher reuse manifest](docs/lineage/twitcher-reuse.md)
- `docs/gamedev/source-of-truth.xlsx`

## Lineage and license

Redot Tuber is an independent project inspired by and selectively adapted from generic foundations in [dominicbytes/twitcher](https://github.com/dominicbytes/twitcher), whose original project is [Kani's Twitcher](https://github.com/kanimaru/twitcher). It is a standalone YouTube/Redot addon, has no Twitcher runtime dependency, and is not intended to be merged back into either Twitcher repository.

Redot Tuber is MIT licensed. Original attribution and the pinned donor commit are preserved in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the [reuse manifest](docs/lineage/twitcher-reuse.md).
