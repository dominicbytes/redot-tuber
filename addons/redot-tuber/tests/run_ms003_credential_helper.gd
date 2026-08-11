extends SceneTree

const ClientClass = preload("res://addons/redot-tuber/auth/youtube_credential_helper_client.gd")
const TARGET: String = "redot-tuber-tests/ms003/windows-x86_64"

var _checks: int = 0
var _failures: PackedStringArray = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var client: Variant = ClientClass.new()
	_check(FileAccess.file_exists(client.resolved_helper_path()), "platform helper binary is packaged")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://addons/redot-tuber/bin/manifest.json"))
	var declared_hash: String = String(manifest.get("helpers", {}).get("windows-x86_64", {}).get("sha256", "")) if manifest is Dictionary else ""
	_check(not declared_hash.is_empty() and FileAccess.get_sha256(client.resolved_helper_path()) == declared_hash, "packaged helper matches its SHA-256 manifest")
	var ping: Variant = await client.ping()
	_check(ping.is_success(), "Windows Credential Manager helper responds to RTCH/1 ping")

	# Always begin and end with deletion so interrupted prior runs are recoverable.
	await client.delete(TARGET)
	var missing: Variant = await client.read(TARGET)
	_check(missing.status == "not_found" and missing.secret.is_empty(), "missing credential is typed")

	var first_value: String = "fixture" + "-vault-value-a"
	var stored: Variant = await client.store(TARGET, first_value)
	_check(stored.is_success(), "refresh-token-shaped value stores in Windows Credential Manager")
	var read_first: Variant = await client.read(TARGET)
	_check(read_first.is_success() and read_first.secret == first_value, "stored value reads back through the pipe")
	read_first.clear_secret()
	first_value = ""

	var replacement: String = "fixture" + "-vault-value-b"
	var replaced: Variant = await client.store(TARGET, replacement)
	_check(replaced.is_success(), "credential replacement succeeds")
	var read_replacement: Variant = await client.read(TARGET)
	_check(read_replacement.is_success() and read_replacement.secret == replacement, "replacement value wins")
	read_replacement.clear_secret()
	replacement = ""

	var deleted: Variant = await client.delete(TARGET)
	_check(deleted.is_success(), "credential deletion succeeds")
	var after_delete: Variant = await client.read(TARGET)
	_check(after_delete.status == "not_found" and after_delete.secret.is_empty(), "deleted credential cannot be recovered")

	var unavailable_client: Variant = ClientClass.new()
	unavailable_client.helper_path_override = "res://addons/redot-tuber/bin/missing-helper"
	var unavailable: Variant = await unavailable_client.ping()
	_check(unavailable.status == "unavailable", "missing helper has typed unavailable state")
	_finish()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-003 CREDENTIAL HELPER PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-003 CREDENTIAL HELPER FAIL: %s" % failure)
	print("MS-003 CREDENTIAL HELPER FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
