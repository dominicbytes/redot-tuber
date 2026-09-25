class_name YouTubeLiveChatPage
extends RefCounted

var events: Array[YouTubeLiveEvent] = []
var active_poll_event: YouTubeLiveEvent = null
var next_page_token: String = ""
var polling_interval_msec: int = 5000
var offline_at: String = ""
var error: YouTubeApiError = null


func is_terminal() -> bool:
	if not offline_at.is_empty():
		return true
	for event: YouTubeLiveEvent in events:
		if event.is_terminal:
			return true
	return false
