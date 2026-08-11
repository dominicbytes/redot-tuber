class_name YouTubeLiveChatResolution
extends RefCounted

const STATUS_ACTIVE: String = "active"
const STATUS_NOT_FOUND: String = "not_found"
const STATUS_CHAT_DISABLED: String = "chat_disabled"
const STATUS_ENDED: String = "ended"
const STATUS_DENIED: String = "denied"
const STATUS_ERROR: String = "error"

var status: String = STATUS_ERROR
var video_id: String = ""
var live_chat_id: String = ""
var title: String = ""
var actual_start_time: String = ""
var actual_end_time: String = ""
var scheduled_start_time: String = ""
var error: YouTubeApiError = null


func is_active() -> bool:
	return status == STATUS_ACTIVE and not live_chat_id.is_empty()
