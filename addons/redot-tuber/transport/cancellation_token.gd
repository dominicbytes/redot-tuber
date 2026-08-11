class_name YouTubeCancellationToken
extends RefCounted

## Emitted once. The reason is diagnostic metadata and must never contain a secret.
signal cancelled(reason: String)

var _is_cancelled: bool = false
var _reason: String = ""


func cancel(cancel_reason: String = "cancelled") -> void:
	if _is_cancelled:
		return
	_is_cancelled = true
	_reason = cancel_reason
	cancelled.emit(_reason)


func is_cancelled() -> bool:
	return _is_cancelled


func reason() -> String:
	return _reason

func wait_until_cancelled() -> String:
	if not _is_cancelled:
		await cancelled
	return _reason
