extends SceneTree

const ROOTS: PackedStringArray = [
	"res://addons/redot-tuber",
	"res://examples",
]

var _checked: int = 0
var _failures: PackedStringArray = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	for root_path: String in ROOTS:
		_scan(root_path)
	if _failures.is_empty():
		print("REDOT TUBER PROJECT CHECK PASS: %d scripts" % _checked)
		quit(0)
		return
	for failure: String in _failures:
		push_error("REDOT TUBER PROJECT CHECK FAIL: %s" % failure)
	print("REDOT TUBER PROJECT CHECK FAILED: %d of %d scripts" % [_failures.size(), _checked])
	quit(1)


func _scan(directory_path: String) -> void:
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		_failures.append("cannot open directory: %s" % directory_path)
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var path: String = directory_path.path_join(entry)
			if directory.current_is_dir():
				_scan(path)
			elif entry.ends_with(".gd"):
				_checked += 1
				var script: Script = load(path)
				if script == null or not script.can_instantiate():
					_failures.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
