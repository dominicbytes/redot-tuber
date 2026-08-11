class_name YouTubeLiveChatPage
extends RefCounted

var events: Array[YouTubeLiveEvent] = []
var next_page_token: String = ""
var polling_interval_msec: int = 5000
var offline_at: String = ""
var error: YouTubeApiError = null


func is_terminal() -> bool:
	return not offline_at.is_empty()
