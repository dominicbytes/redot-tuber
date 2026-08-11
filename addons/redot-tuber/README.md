# Redot Tuber addon

Install this directory as `res://addons/redot-tuber/`, then enable **Redot Tuber** in Redot's plugin settings. The plugin adds a reversible setup menu only; it does not add an autoload or persist credentials in project content.

`YouTubeLiveClient` is the public runtime facade. It supports developer-owned API-key reads, developer-owned Desktop OAuth clients, persistent channel-owner sessions, typed live events, and capability-gated YouTube Live services. See the repository's `docs/api-reference.md`, `docs/capability-matrix.md`, and `docs/oauth-setup.md` before shipping.

The bundled credential helpers target Windows and Linux x86-64. Windows Credential Manager is tested locally; a real Linux desktop Secret Service and live Google project still require release certification. Tokens never fall back to a plaintext file.

This standalone addon is MIT licensed. See `LICENSE` and the repository's `THIRD_PARTY_NOTICES.md` for Kani/Twitcher lineage and attribution.
