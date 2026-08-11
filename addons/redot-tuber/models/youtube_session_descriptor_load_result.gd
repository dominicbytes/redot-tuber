class_name YouTubeSessionDescriptorLoadResult
extends RefCounted

var descriptor: YouTubeSessionDescriptor = null
var error: YouTubeApiError = null


func is_success() -> bool:
	return descriptor != null and error == null
