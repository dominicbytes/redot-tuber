# Redot Tuber credential helper

This standalone native executable is intentionally not a GDExtension. It isolates persistent OAuth refresh tokens behind Windows Credential Manager or Linux Secret Service while keeping the addon itself in typed GDScript.

## Build

Windows x86-64 requires the MSVC C++ build tools:

```powershell
cmake -S . -B build/windows-x86_64 -A x64
cmake --build build/windows-x86_64 --config Release
```

Linux x86-64 requires a C11 compiler, CMake, pkg-config, and the libsecret development package:

```bash
cmake -S . -B build/linux-x86_64 -DCMAKE_BUILD_TYPE=Release
cmake --build build/linux-x86_64
```

Copy the resulting binary into the matching `addons/redot-tuber/bin/<platform>/x86_64/` directory and update the checksum manifest. ARM64 and macOS are deliberately post-initial-release targets.
