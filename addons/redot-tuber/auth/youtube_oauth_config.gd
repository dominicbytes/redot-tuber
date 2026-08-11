class_name YouTubeOAuthConfig
extends RefCounted

const DEFAULT_AUTHORIZATION_ENDPOINT: String = "https://accounts.google.com/o/oauth2/v2/auth"
const DEFAULT_TOKEN_ENDPOINT: String = "https://oauth2.googleapis.com/token"
const DEFAULT_REVOCATION_ENDPOINT: String = "https://oauth2.googleapis.com/revoke"

var client_id: String = ""
var application_id: String = ""
var publisher_id: String = ""
var authorization_endpoint: String = DEFAULT_AUTHORIZATION_ENDPOINT
var token_endpoint: String = DEFAULT_TOKEN_ENDPOINT
var revocation_endpoint: String = DEFAULT_REVOCATION_ENDPOINT
var youtube_api_base_url: String = YouTubeApiClient.DEFAULT_BASE_URL
var callback_timeout_msec: int = 180000
var helper_path_override: String = ""


func validate() -> YouTubeApiError:
	if client_id.strip_edges().is_empty():
		return YouTubeApiError.invalid("A developer-owned Google Desktop OAuth client ID is required")
	if application_id.strip_edges().is_empty():
		return YouTubeApiError.invalid("A stable application ID is required for credential isolation")
	if publisher_id.strip_edges().is_empty():
		return YouTubeApiError.invalid("A stable publisher ID is required for credential isolation")
	for endpoint: String in [authorization_endpoint, token_endpoint, revocation_endpoint, youtube_api_base_url]:
		if not _is_secure_endpoint(endpoint):
			return YouTubeApiError.invalid("OAuth endpoints must use HTTPS outside local tests")
	if callback_timeout_msec < 1000 or callback_timeout_msec > 900000:
		return YouTubeApiError.invalid("OAuth callback timeout must be between 1 second and 15 minutes")
	if not _is_safe_identifier(application_id) or not _is_safe_identifier(publisher_id):
		return YouTubeApiError.invalid("Publisher and application IDs may contain only letters, digits, dot, underscore, and hyphen")
	return null


func credential_target(session_slot: String) -> String:
	return "%s/%s/%s" % [publisher_id, application_id, session_slot]


func _is_secure_endpoint(endpoint: String) -> bool:
	return endpoint.begins_with("https://") or endpoint.begins_with("http://127.0.0.1:") or endpoint.begins_with("http://localhost:")


func _is_safe_identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	var allowed: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
	for character: String in value:
		if not allowed.contains(character):
			return false
	return true
