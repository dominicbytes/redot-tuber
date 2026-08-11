class_name YouTubeOAuthPkce
extends RefCounted

var _crypto: Crypto = Crypto.new()


func generate_verifier() -> String:
	return _base64url(_crypto.generate_random_bytes(64))


func generate_state() -> String:
	return _base64url(_crypto.generate_random_bytes(32))


func challenge_for(verifier: String) -> String:
	var hashing: HashingContext = HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(verifier.to_utf8_buffer()) != OK:
		return ""
	return _base64url(hashing.finish())


func _base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")
