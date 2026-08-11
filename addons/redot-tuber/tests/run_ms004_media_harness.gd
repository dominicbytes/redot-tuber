extends SceneTree

const TransportClass = preload("res://addons/redot-tuber/transport/youtube_http_transport.gd")
const CacheClass = preload("res://addons/redot-tuber/media/youtube_media_cache.gd")
const PNG_BASE64: String = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
const CACHE_DIRECTORY: String = "user://redot-tuber/tests/ms004-media"

var _checks: int = 0
var _failures: PackedStringArray = []
var _pending_media: YouTubeMediaResult = null


class MediaServer extends Node:
	var server: TCPServer = TCPServer.new()
	var peers: Array[Dictionary] = []
	var counts: Dictionary = {}
	var png: PackedByteArray = PackedByteArray()
	var release_hold: bool = false

	func start(payload: PackedByteArray) -> Error:
		png = payload
		var error: Error = server.listen(0, "127.0.0.1")
		set_process(error == OK)
		return error

	func port() -> int:
		return server.get_local_port()

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			peers.append({"peer": server.take_connection(), "request": "", "responded": false})
		for item: Dictionary in peers:
			if bool(item.responded):
				continue
			var peer: StreamPeerTCP = item.peer
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				item.responded = true
				continue
			var available: int = peer.get_available_bytes()
			if available > 0:
				item.request = String(item.request) + peer.get_utf8_string(available)
			if not String(item.request).contains("\r\n\r\n"):
				continue
			var first_line: String = String(item.request).split("\r\n", false)[0]
			var parts: PackedStringArray = first_line.split(" ", false)
			var path: String = parts[1].split("?", false)[0] if parts.size() >= 2 else "/invalid"
			if path == "/hold" and not release_hold:
				continue
			counts[path] = int(counts.get(path, 0)) + 1
			match path:
				"/bad-type":
					_send(peer, "text/plain", "not an image".to_utf8_buffer())
				"/oversized":
					var oversized: PackedByteArray = PackedByteArray()
					oversized.resize(4096)
					oversized.fill(65)
					_send(peer, "image/png", oversized)
				_:
					_send(peer, "image/png", png)
			item.responded = true

	func _send(peer: StreamPeerTCP, mime_type: String, body: PackedByteArray) -> void:
		var header: String = (
			"HTTP/1.1 200 OK\r\n" +
			"Content-Type: %s\r\n" % mime_type +
			"Content-Length: %d\r\n" % body.size() +
			"Connection: close\r\n\r\n"
		)
		peer.put_data(header.to_utf8_buffer())
		peer.put_data(body)
		peer.disconnect_from_host()

	func stop() -> void:
		set_process(false)
		for item: Dictionary in peers:
			var peer: StreamPeerTCP = item.peer
			if peer != null:
				peer.disconnect_from_host()
		peers.clear()
		server.stop()


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var server: MediaServer = MediaServer.new()
	root.add_child(server)
	var png: PackedByteArray = Marshalls.base64_to_raw(PNG_BASE64)
	_check(server.start(png) == OK, "media harness binds IPv4 loopback")
	if server.port() <= 0:
		server.free()
		_finish()
		return
	var transport: YouTubeHttpTransport = TransportClass.new()
	transport.max_retries = 0
	transport.response_body_limit_bytes = 8192
	root.add_child(transport)
	var cache: YouTubeMediaCache = CacheClass.new(transport)
	cache.max_items = 1
	cache.max_item_bytes = 1024
	cache.max_total_bytes = 1024
	cache.max_concurrent_fetches = 1
	cache.cache_directory = CACHE_DIRECTORY
	root.add_child(cache)
	cache.clear_data()

	var first_url: String = _url(server, "/one")
	var first: YouTubeMediaResult = await cache.fetch_texture(first_url)
	_check(first.is_success() and first.mime_type == "image/png", "bounded cache downloads an allowed image")
	_check(first.texture != null, "PNG media decodes to a Redot texture")
	_check(not first.from_cache and int(server.counts.get("/one", 0)) == 1, "first media request reaches the server once")
	var cached: YouTubeMediaResult = await cache.fetch_texture(first_url)
	_check(cached.is_success() and cached.from_cache, "second media request is served from memory")
	_check(int(server.counts.get("/one", 0)) == 1, "memory hit sends no second HTTP request")
	var second: YouTubeMediaResult = await cache.fetch_texture(_url(server, "/two"))
	_check(second.is_success() and cache.item_count() == 1, "LRU item bound evicts the older image")
	_check(cache.total_bytes() <= cache.max_total_bytes, "memory byte bound remains enforced")
	var bad_type: YouTubeMediaResult = await cache.fetch_texture(_url(server, "/bad-type"))
	_check(bad_type.error != null and bad_type.error.category == "media_type", "unexpected content type is rejected")
	cache.max_item_bytes = 512
	var oversized: YouTubeMediaResult = await cache.fetch_texture(_url(server, "/oversized"))
	_check(oversized.error != null, "oversized media is rejected")
	cache.max_item_bytes = 1024

	_launch_fetch(cache, _url(server, "/hold"))
	for _frame: int in 20:
		if cache.active_fetch_count() == 1:
			break
		await process_frame
	_check(cache.active_fetch_count() == 1, "media concurrency harness holds one active fetch")
	var busy: YouTubeMediaResult = await cache.fetch_texture(_url(server, "/while-busy"))
	_check(busy.error != null and busy.error.category == "media_busy", "media concurrency bound rejects overflow deterministically")
	server.release_hold = true
	for _frame: int in 300:
		if _pending_media != null:
			break
		await process_frame
	_check(_pending_media != null and _pending_media.is_success(), "held media request completes after release")

	cache.clear_data()
	cache.persist_to_disk = true
	cache.max_items = 4
	var signed_url: String = _url(server, "/persist") + "?signature=do-not-persist"
	var persisted: YouTubeMediaResult = await cache.fetch_texture(signed_url)
	_check(persisted.is_success(), "opt-in persistent cache stores bounded media")
	var key: String = signed_url.sha256_text()
	var metadata_path: String = CACHE_DIRECTORY.path_join(key + ".json")
	var metadata: String = _read_text(metadata_path)
	_check(not metadata.contains("signature") and not metadata.contains("do-not-persist"), "persistent metadata stores a hash instead of the remote URL")
	var request_count: int = int(server.counts.get("/persist", 0))
	cache.queue_free()
	await process_frame

	var disk_cache: YouTubeMediaCache = CacheClass.new(transport)
	disk_cache.persist_to_disk = true
	disk_cache.cache_directory = CACHE_DIRECTORY
	disk_cache.max_item_bytes = 1024
	disk_cache.max_items = 4
	root.add_child(disk_cache)
	var disk_hit: YouTubeMediaResult = await disk_cache.fetch_texture(signed_url)
	_check(disk_hit.is_success() and disk_hit.from_cache, "opt-in media survives a cache-node restart")
	_check(int(server.counts.get("/persist", 0)) == request_count, "disk hit performs no network request")
	disk_cache.queue_free()
	await process_frame

	var corrupt_file: FileAccess = FileAccess.open(CACHE_DIRECTORY.path_join(key + ".bin"), FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_buffer(PackedByteArray([1, 2, 3]))
		corrupt_file.flush()
	corrupt_file = null
	var recovery_cache: YouTubeMediaCache = CacheClass.new(transport)
	recovery_cache.persist_to_disk = true
	recovery_cache.cache_directory = CACHE_DIRECTORY
	recovery_cache.max_item_bytes = 1024
	recovery_cache.max_items = 4
	root.add_child(recovery_cache)
	var recovered: YouTubeMediaResult = await recovery_cache.fetch_texture(signed_url)
	_check(recovered.is_success() and not recovered.from_cache, "corrupt disk media is discarded and refetched")
	_check(int(server.counts.get("/persist", 0)) == request_count + 1, "corruption recovery performs exactly one refetch")
	var clear_error: YouTubeApiError = recovery_cache.clear_data()
	_check(clear_error == null, "media clear-data succeeds%s" % ["" if clear_error == null else ": " + clear_error.message])
	_check(not FileAccess.file_exists(metadata_path), "media clear-data removes persistent metadata")

	for result: YouTubeMediaResult in [first, cached, second, bad_type, oversized, busy, persisted, disk_hit, recovered, _pending_media]:
		if result != null:
			result.texture = null
			result.clear_bytes()
	_pending_media = null
	recovery_cache.queue_free()
	transport.queue_free()
	server.stop()
	server.queue_free()
	await process_frame
	await process_frame
	_finish()


func _launch_fetch(cache: YouTubeMediaCache, url: String) -> void:
	_pending_media = await cache.fetch_texture(url)


func _url(server: MediaServer, path: String) -> String:
	return "http://127.0.0.1:%d%s" % [server.port(), path]


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-004 MEDIA HARNESS PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-004 MEDIA HARNESS FAIL: %s" % failure)
	print("MS-004 MEDIA HARNESS FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
