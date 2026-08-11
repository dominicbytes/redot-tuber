class_name YouTubeLiveChatPollScheduler
extends RefCounted

var _next_allowed_msec: int = 0
var _next_page_token: String = ""
var _terminal: bool = false
var _terminal_reason: String = ""


func accept_response(response: Dictionary, received_at_msec: int) -> String:
	if _terminal:
		return "scheduler is terminal"
	if not response.has("pollingIntervalMillis"):
		return "response is missing pollingIntervalMillis"
	var polling_interval_msec: int = int(response["pollingIntervalMillis"])
	if polling_interval_msec < 0:
		return "pollingIntervalMillis cannot be negative"
	_next_page_token = String(response.get("nextPageToken", ""))
	_next_allowed_msec = received_at_msec + polling_interval_msec
	if not String(response.get("offlineAt", "")).is_empty():
		mark_terminal("offline")
	return ""


func can_poll(now_msec: int) -> bool:
	return not _terminal and now_msec >= _next_allowed_msec


func remaining_msec(now_msec: int) -> int:
	if _terminal:
		return 0
	return maxi(0, _next_allowed_msec - now_msec)


func next_page_token() -> String:
	return _next_page_token


func next_allowed_msec() -> int:
	return _next_allowed_msec


func mark_terminal(reason: String) -> void:
	_terminal = true
	_terminal_reason = reason


func is_terminal() -> bool:
	return _terminal


func terminal_reason() -> String:
	return _terminal_reason


func reset() -> void:
	_next_allowed_msec = 0
	_next_page_token = ""
	_terminal = false
	_terminal_reason = ""
