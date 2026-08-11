class_name YouTubeMediaResult
extends RefCounted

var url_hash: String = ""
var mime_type: String = ""
var bytes: PackedByteArray = PackedByteArray()
var texture: Texture2D = null
var from_cache: bool = false
var error: YouTubeApiError = null


func is_success() -> bool:
	return error == null and not bytes.is_empty()


func clear_bytes() -> void:
	bytes.clear()
