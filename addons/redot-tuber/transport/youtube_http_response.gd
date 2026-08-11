class_name YouTubeHttpResponse
extends RefCounted

var request_result: int = HTTPRequest.RESULT_SUCCESS
var status_code: int = 0
var headers: PackedStringArray = PackedStringArray()
var body: PackedByteArray = PackedByteArray()
var parsed_json: Variant = null
var error: YouTubeApiError = null
var attempt_count: int = 0
var elapsed_msec: int = 0


func is_success() -> bool:
	return request_result == HTTPRequest.RESULT_SUCCESS and status_code >= 200 and status_code < 300 and error == null


func body_text() -> String:
	return body.get_string_from_utf8()
