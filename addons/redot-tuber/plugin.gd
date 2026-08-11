@tool
extends EditorPlugin

const SetupDialogClass = preload("res://addons/redot-tuber/editor/youtube_setup_dialog.gd")
const MENU_LABEL: String = "Redot Tuber Setup"

var _setup_dialog: AcceptDialog = null


func _enter_tree() -> void:
	add_tool_menu_item(MENU_LABEL, _show_setup)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_LABEL)
	if is_instance_valid(_setup_dialog):
		_setup_dialog.queue_free()
	_setup_dialog = null


func _show_setup() -> void:
	if not is_instance_valid(_setup_dialog):
		_setup_dialog = SetupDialogClass.new()
		get_editor_interface().get_base_control().add_child(_setup_dialog)
	_setup_dialog.show_setup()
