class_name YouTubeApiPage
extends RefCounted

var items: Array = []
var next_page_token: String = ""
var previous_page_token: String = ""
var total_results: int = 0
var results_per_page: int = 0
var from_cache: bool = false
var error: YouTubeApiError = null


func is_success() -> bool:
	return error == null
