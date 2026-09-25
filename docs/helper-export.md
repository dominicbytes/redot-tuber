# Native helpers in exported games

Enable the addon before exporting. Its export hook registers both Windows/Linux x86-64 helpers as external sidecars, not as files embedded in the PCK. Keep the `redot-tuber/` directory beside the exported game executable:

```text
game.exe (or game on Linux)
game.pck (if not embedded)
redot-tuber/
  redot-tuber-credential-helper.exe (Windows)
  redot-tuber-credential-helper     (Linux)
  redot-tuber-stream-helper.exe     (Windows)
  redot-tuber-stream-helper         (Linux)
```

Ship only the target platform's helpers. Moving the whole game directory preserves runtime resolution, including paths with spaces and Unicode. Editor/source runs continue to use the addon's `bin/<platform>/x86_64/` path. Unsupported architectures return an unavailable helper rather than accidentally executing the x86-64 binary. Explicit helper path overrides remain available to integrators.

Linux packages must preserve mode 0755 for both helpers. The hook applies it on native Linux exports; when cross-exporting from Windows, set/preserve it during Linux package assembly before making the install directory read-only. Do not rely on a game changing permissions at startup. Linux also needs a functioning Secret Service desktop session, as documented in OAuth setup. A missing or non-executable credential helper fails explicitly; there is no plaintext credential fallback. A missing stream helper fails explicitly and may use interval-respecting polling when enabled.

Validation status: path/architecture selection and required API availability tested on Redot 26.3. These checks are not a clean exported-game test. Exact 26.3 export templates, successful editor/export completion, and clean Windows/Linux runtime certification are still required before release. No export preset, signing configuration, or user credential has been changed.
