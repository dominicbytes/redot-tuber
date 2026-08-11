class_name YouTubeJsonStreamFramer
extends RefCounted

## Incrementally frames JSON objects from arbitrary HTTP byte chunks.
## The buffer holds at most one partial response and is always bounded.

const BYTE_TAB: int = 9
const BYTE_LINE_FEED: int = 10
const BYTE_CARRIAGE_RETURN: int = 13
const BYTE_SPACE: int = 32
const BYTE_QUOTE: int = 34
const BYTE_BACKSLASH: int = 92
const BYTE_ARRAY_OPEN: int = 91
const BYTE_ARRAY_CLOSE: int = 93
const BYTE_OBJECT_OPEN: int = 123
const BYTE_OBJECT_CLOSE: int = 125

var _max_buffer_bytes: int
var _buffer: PackedByteArray = PackedByteArray()
var _scan_index: int = 0
var _frame_started: bool = false
var _in_string: bool = false
var _escaping: bool = false
var _delimiter_stack: Array[int] = []
var _last_error: String = ""


func _init(max_buffer_bytes: int = 1024 * 1024) -> void:
	_max_buffer_bytes = maxi(64, max_buffer_bytes)


func push_chunk(chunk: PackedByteArray) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	if chunk.is_empty():
		return frames
	_last_error = ""
	_buffer.append_array(chunk)

	while _scan_index < _buffer.size():
		var byte: int = _buffer[_scan_index]
		if not _frame_started:
			if _is_whitespace(byte):
				_scan_index += 1
				continue
			if byte != BYTE_OBJECT_OPEN:
				_fail("stream contains data outside a JSON object")
				return frames
			if _scan_index > 0:
				_buffer = _buffer.slice(_scan_index)
				_scan_index = 0
				byte = _buffer[0]
			_frame_started = true

		if _in_string:
			if _escaping:
				_escaping = false
			elif byte == BYTE_BACKSLASH:
				_escaping = true
			elif byte == BYTE_QUOTE:
				_in_string = false
		else:
			if byte == BYTE_QUOTE:
				_in_string = true
			elif byte == BYTE_OBJECT_OPEN or byte == BYTE_ARRAY_OPEN:
				_delimiter_stack.append(byte)
			elif byte == BYTE_OBJECT_CLOSE or byte == BYTE_ARRAY_CLOSE:
				if _delimiter_stack.is_empty() or not _delimiter_matches(_delimiter_stack.back(), byte):
					_fail("stream contains mismatched JSON delimiters")
					return frames
				_delimiter_stack.pop_back()
				if _delimiter_stack.is_empty():
					var frame_end: int = _scan_index + 1
					var parsed: Variant = JSON.parse_string(_buffer.slice(0, frame_end).get_string_from_utf8())
					if not parsed is Dictionary:
						_fail("complete stream frame is not a JSON object")
						return frames
					frames.append(parsed)
					_buffer = _buffer.slice(frame_end)
					_reset_scan_state()
					continue
		_scan_index += 1

	if not _frame_started and _scan_index == _buffer.size():
		_buffer.clear()
		_scan_index = 0
	if _buffer.size() > _max_buffer_bytes:
		_fail("partial JSON frame exceeded %d buffered bytes" % _max_buffer_bytes)
	return frames


func reset() -> void:
	_buffer.clear()
	_last_error = ""
	_reset_scan_state()


func buffered_byte_count() -> int:
	return _buffer.size()


func max_buffer_bytes() -> int:
	return _max_buffer_bytes


func last_error() -> String:
	return _last_error


func _fail(message: String) -> void:
	_last_error = message
	_buffer.clear()
	_reset_scan_state()


func _reset_scan_state() -> void:
	_scan_index = 0
	_frame_started = false
	_in_string = false
	_escaping = false
	_delimiter_stack.clear()


func _is_whitespace(byte: int) -> bool:
	return byte == BYTE_SPACE or byte == BYTE_TAB or byte == BYTE_LINE_FEED or byte == BYTE_CARRIAGE_RETURN


func _delimiter_matches(opening: int, closing: int) -> bool:
	return (opening == BYTE_OBJECT_OPEN and closing == BYTE_OBJECT_CLOSE) or (opening == BYTE_ARRAY_OPEN and closing == BYTE_ARRAY_CLOSE)
