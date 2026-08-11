class_name YouTubeSessionDescriptorStore
extends RefCounted

const DEFAULT_DIRECTORY: String = "user://redot-tuber/sessions"

var _base_directory: String


func _init(base_directory: String = DEFAULT_DIRECTORY) -> void:
	_base_directory = base_directory.trim_suffix("/")


func path_for_slot(session_slot: String) -> String:
	if not _is_valid_slot(session_slot):
		return ""
	return "%s/%s.json" % [_base_directory, session_slot]


func save(descriptor: YouTubeSessionDescriptor) -> YouTubeApiError:
	if descriptor == null:
		return YouTubeApiError.invalid("Session descriptor is required")
	var path: String = path_for_slot(descriptor.session_slot)
	if path.is_empty():
		return YouTubeApiError.invalid("Invalid session slot")
	if descriptor.credential_target.is_empty():
		return YouTubeApiError.invalid("Credential target is required")
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_base_directory))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return YouTubeApiError.from_transport(directory_error, "Unable to create the session descriptor directory")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return YouTubeApiError.from_transport(FileAccess.get_open_error(), "Unable to write the non-secret session descriptor")
	file.store_string(JSON.stringify(descriptor.to_dictionary(), "  ") + "\n")
	file.close()
	return null


func load_descriptor(session_slot: String) -> YouTubeSessionDescriptorLoadResult:
	var result: YouTubeSessionDescriptorLoadResult = YouTubeSessionDescriptorLoadResult.new()
	var path: String = path_for_slot(session_slot)
	if path.is_empty():
		result.error = YouTubeApiError.invalid("Invalid session slot")
		return result
	if not FileAccess.file_exists(path):
		result.error = YouTubeApiError.from_transport(ERR_FILE_NOT_FOUND, "No saved YouTube session exists for this slot")
		result.error.category = "not_found"
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		result.error = YouTubeApiError.from_transport(ERR_PARSE_ERROR, "Saved YouTube session descriptor is corrupt")
		return result
	result.descriptor = YouTubeSessionDescriptor.from_dictionary(parsed)
	if result.descriptor == null or result.descriptor.session_slot != session_slot:
		result.descriptor = null
		result.error = YouTubeApiError.from_transport(ERR_INVALID_DATA, "Saved YouTube session descriptor has an unsupported schema or slot")
	return result


func delete_descriptor(session_slot: String) -> YouTubeApiError:
	var path: String = path_for_slot(session_slot)
	if path.is_empty():
		return YouTubeApiError.invalid("Invalid session slot")
	if not FileAccess.file_exists(path):
		return null
	var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if remove_error != OK:
		return YouTubeApiError.from_transport(remove_error, "Unable to delete the session descriptor")
	return null


func _is_valid_slot(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	var allowed: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
	for character: String in value:
		if not allowed.contains(character):
			return false
	return true
