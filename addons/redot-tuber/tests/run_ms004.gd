extends SceneTree

const ADDON_ROOT: String = "res://addons/redot-tuber"

var _checks: int = 0
var _failures: PackedStringArray = []


class FakeApiClient extends RefCounted:
	var responses: Array = []
	var requests: Array[Dictionary] = []

	func enqueue(response: YouTubeHttpResponse) -> void:
		responses.append(response)

	func request_json(
		method_id: String,
		http_method: int,
		path: String,
		query: Dictionary = {},
		body: Dictionary = {},
		_cancellation: Variant = null
	) -> Variant:
		requests.append({
			"method_id": method_id,
			"http_method": http_method,
			"path": path,
			"query": query.duplicate(true),
			"body": body.duplicate(true),
		})
		if responses.is_empty():
			var missing: YouTubeHttpResponse = YouTubeHttpResponse.new()
			missing.status_code = 500
			missing.error = YouTubeApiError.custom("fixture", "No fake response was queued")
			return missing
		return responses.pop_front()


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	_test_contract_and_capabilities()
	_test_typed_events()
	_test_resource_models()
	await _test_channel_discovery()
	await _test_discovery()
	await _test_chat_actions()
	await _test_moderation_actions()
	await _test_broadcast_actions()
	await _test_stream_actions()
	await _test_monetization()
	await _test_media_policy()
	_finish()


func _test_contract_and_capabilities() -> void:
	var contract: Dictionary = _load_json(ADDON_ROOT + "/contracts/youtube_api_contract.json")
	var endpoints: Array = contract.get("endpoints", [])
	_check(contract.get("schema_version") == 2, "runtime API contract is schema v2")
	_check(endpoints.size() == YouTubeCapabilityRegistry.all_method_info().size(), "capability matrix covers every runtime endpoint")
	var endpoint_ids: Dictionary = {}
	for endpoint: Variant in endpoints:
		if endpoint is Dictionary:
			endpoint_ids[String(endpoint.get("id", ""))] = true
	for info: YouTubeCapabilityInfo in YouTubeCapabilityRegistry.all_method_info():
		_check(endpoint_ids.has(info.method_id), "capability method is contracted: %s" % info.method_id)
	var search_info: YouTubeCapabilityInfo = YouTubeCapabilityRegistry.method_info("search.list")
	_check(search_info.quota_bucket == "search_queries" and search_info.quota_units == 1, "search uses the separate documented quota bucket")
	var ledger: YouTubeQuotaLedger = YouTubeQuotaLedger.new(endpoints, 100, {"search_queries": 2})
	_check(ledger.record_request("search.list", 1).is_empty(), "first search request records")
	_check(ledger.bucket_units("search_queries") == 1 and ledger.total_units() == 1, "search units are bucket-aware")
	_check(ledger.remaining_units() == 100, "search does not consume the YouTube Data unit budget")
	_check(ledger.record_request("search.list", 2).is_empty(), "second search request records")
	_check(not ledger.record_request("search.list", 3).is_empty(), "search bucket stops a request beyond its local budget")
	var scope_registry: YouTubeScopeRegistry = YouTubeScopeRegistry.new()
	var write_scopes: PackedStringArray = scope_registry.scopes_for(PackedStringArray(["broadcast.manage", "stream.manage", "chat.read"]))
	_check(write_scopes == PackedStringArray([YouTubeScopeRegistry.SCOPE_FORCE_SSL]), "broadcast and stream writes use the least-privilege force-ssl scope")
	var gate: YouTubeCapabilityGate = YouTubeCapabilityGate.new()
	gate.configure(PackedStringArray(["chat.write", "moderation.ban"]), false)
	_check(gate.require_method("liveChatMessages.insert").category == "authorization", "OAuth-only action rejects a public configuration")
	gate.configure(PackedStringArray(["chat.write", "moderation.ban"]), true)
	_check(gate.require_method("liveChatMessages.insert") == null, "authorized write capability passes")
	_check(gate.require_method("liveChatBans.insert").category == "confirmation_required", "destructive action requires explicit confirmation")
	_check(gate.require_method("liveChatBans.insert", true) == null, "confirmed destructive action passes")


func _test_typed_events() -> void:
	var fixture: Dictionary = _load_json(ADDON_ROOT + "/tests/fixtures/live_chat_events.json")
	var normalizer: YouTubeLiveEventNormalizer = YouTubeLiveEventNormalizer.new()
	var by_type: Dictionary = {}
	for raw: Variant in fixture.get("items", []):
		var event: YouTubeLiveEvent = normalizer.normalize(raw)
		_check(event != null, "event fixture normalizes")
		if event != null:
			by_type[event.source_type] = event
	_check(by_type.size() == 16, "all official and forward-compatible event fixtures normalize")
	var text_event: YouTubeLiveEvent = by_type.get("textMessageEvent")
	_check(text_event.text_details != null and text_event.text_details.message_text.contains("Hello"), "text event exposes typed text details")
	_check(text_event.author != null and text_event.author.channel_id == "channel-viewer", "event exposes typed author identity")
	var super_chat: YouTubeLiveEvent = by_type.get("superChatEvent")
	_check(super_chat.monetization_details != null and super_chat.monetization_details.amount_micros == 5000000, "Super Chat exposes typed money details")
	var super_sticker: YouTubeLiveEvent = by_type.get("superStickerEvent")
	_check(super_sticker.monetization_details.sticker_alt_text == "Celebration", "Super Sticker exposes typed metadata without inventing an unavailable image URL")
	var membership: YouTubeLiveEvent = by_type.get("memberMilestoneChatEvent")
	_check(membership.membership_details.member_month == 12, "member milestone exposes typed membership details")
	var gifting: YouTubeLiveEvent = by_type.get("membershipGiftingEvent")
	_check(gifting.membership_details.gift_memberships_count == 5, "membership gifting count is typed")
	var poll: YouTubeLiveEvent = by_type.get("pollEvent")
	_check(poll.poll_details.question_text == "Choose a route" and poll.poll_details.options.size() == 2, "poll metadata and options are typed")
	var moderation: YouTubeLiveEvent = by_type.get("userBannedEvent")
	_check(moderation.moderation_details.ban_duration_seconds == 300, "moderation event exposes typed ban duration")
	var gift: YouTubeLiveEvent = by_type.get("giftEvent")
	_check(gift.gift_details.gift_name == "Star" and gift.gift_details.combo_count == 1, "gift event exposes typed gift and combo data")
	var unknown: YouTubeLiveEvent = by_type.get("futureEventType")
	_check(unknown.is_unknown and unknown.kind == "unknown", "future event remains available through the unknown path")
	var deduplicator: YouTubeEventDeduplicator = YouTubeEventDeduplicator.new()
	_check(deduplicator.classify(gift) == "new", "first gift combo event is new")
	var updated_raw: Dictionary = gift.raw_payload.duplicate(true)
	updated_raw.snippet.giftEventDetails.giftMetadata.comboCount = 2
	var updated_gift: YouTubeLiveEvent = normalizer.normalize(updated_raw)
	_check(deduplicator.classify(updated_gift) == "update", "same gift ID with a new combo count is an update")


func _test_resource_models() -> void:
	var broadcast: YouTubeLiveBroadcast = YouTubeLiveBroadcast.from_api({
		"id": "broadcast-1",
		"snippet": {"title": "Fixture Live", "description": "Demo", "channelId": "owner", "scheduledStartTime": "2026-08-11T12:00:00Z", "liveChatId": "chat-1", "thumbnails": {"high": {"url": "https://example.invalid/thumb.jpg"}}},
		"status": {"lifeCycleStatus": "ready", "privacyStatus": "unlisted", "selfDeclaredMadeForKids": false},
		"contentDetails": {"boundStreamId": "stream-1", "enableDvr": true},
		"monetizationDetails": {"adsMonetizationStatus": "enabled"},
		"statistics": {"totalChatCount": "42"},
	})
	_check(broadcast.id == "broadcast-1" and broadcast.live_chat_id == "chat-1", "broadcast identity and chat selection parse")
	_check(broadcast.bound_stream_id == "stream-1" and broadcast.total_chat_count == 42, "broadcast binding and statistics parse")
	var update_body: Dictionary = broadcast.to_update_body(PackedStringArray(["snippet", "contentDetails"]))
	_check(update_body.has("id") and update_body.has("snippet") and update_body.has("contentDetails") and not update_body.has("status"), "broadcast update serializes only requested parts")
	var stream: YouTubeLiveStream = YouTubeLiveStream.from_api({
		"id": "stream-1",
		"snippet": {"title": "Encoder", "description": "Fixture"},
		"cdn": {"ingestionType": "rtmp", "resolution": "1080p", "frameRate": "60fps", "ingestionInfo": {"streamName": "fixture-stream-secret", "ingestionAddress": "rtmp://example.invalid/live"}},
		"status": {"streamStatus": "active", "healthStatus": {"status": "good", "configurationIssues": []}},
		"contentDetails": {"isReusable": true},
	})
	_check(stream.stream_status == "active" and stream.health_status == "good" and stream.is_reusable, "stream status and reuse fields parse")
	_check(stream.stream_name == "fixture-stream-secret", "stream ingestion name is available in memory")
	stream.clear_sensitive()
	_check(stream.stream_name.is_empty() and String((stream.cdn_details.ingestionInfo as Dictionary).streamName).is_empty(), "stream ingestion name can be explicitly cleared")
	var redactor: YouTubeRedactor = YouTubeRedactor.new()
	var redacted: Dictionary = redactor.redact_dictionary({"streamName": "fixture-stream-secret", "safe": "visible"})
	_check(redacted.streamName == YouTubeRedactor.REDACTED and redacted.safe == "visible", "diagnostics redact stream ingestion names")
	var search_item: YouTubeDiscoveryItem = YouTubeDiscoveryItem.from_api({"id": {"kind": "youtube#video", "videoId": "video-1"}, "snippet": {"title": "Live", "liveBroadcastContent": "live"}})
	_check(search_item.resource_type == "video" and search_item.id == "video-1", "search result exposes typed resource identity")


func _test_channel_discovery() -> void:
	var fake: FakeApiClient = FakeApiClient.new()
	var gate: YouTubeCapabilityGate = _gate(PackedStringArray(["channel.read"]), false)
	var service: YouTubeChannelService = YouTubeChannelService.new(fake, gate)
	fake.enqueue(_response({"items": [{"id": "channel-1", "snippet": {"title": "One"}}, {"id": "channel-2", "snippet": {"title": "Two"}}]}))
	var by_ids: YouTubeApiPage = await service.list_by_ids(PackedStringArray(["channel-1", "channel-2"]))
	_check(by_ids.is_success() and by_ids.items.size() == 2, "public channel ID discovery returns typed channels")
	_check(fake.requests[0].query.id == "channel-1,channel-2", "channel ID discovery serializes the requested IDs")
	fake.enqueue(_response({"items": [{"id": "channel-handle", "snippet": {"title": "Handle", "customUrl": "@fixture"}}]}))
	var by_handle: YouTubeChannelResult = await service.get_by_handle("@fixture")
	_check(by_handle.is_success() and by_handle.channel.id == "channel-handle", "public channel handle discovery returns typed identity")
	_check(fake.requests[1].query.forHandle == "@fixture", "channel handle discovery uses the official forHandle filter")
	var public_mine: YouTubeChannelResult = await service.get_mine()
	_check(public_mine.error != null and public_mine.error.category == "authorization" and fake.requests.size() == 2, "mine=true is rejected locally without an OAuth account")
	gate.configure(PackedStringArray(["channel.read"]), true)
	fake.enqueue(_response({"items": [{"id": "channel-mine", "snippet": {"title": "Mine"}}]}))
	var mine: YouTubeChannelResult = await service.get_mine()
	_check(mine.is_success() and mine.channel.id == "channel-mine" and fake.requests[2].query.mine == "true", "authorized current-channel discovery succeeds")


func _test_discovery() -> void:
	var fake: FakeApiClient = FakeApiClient.new()
	fake.enqueue(_response({"nextPageToken": "next", "pageInfo": {"totalResults": 1, "resultsPerPage": 1}, "items": [{"id": {"kind": "youtube#video", "videoId": "live-video"}, "snippet": {"title": "Fixture Live", "channelId": "channel-1", "liveBroadcastContent": "live"}}]}))
	var gate: YouTubeCapabilityGate = _gate(PackedStringArray(["discovery.read"]), false)
	var service: YouTubeDiscoveryService = YouTubeDiscoveryService.new(fake, gate)
	service.minimum_search_interval_msec = 30000
	service.cache_ttl_msec = 60000
	var first: YouTubeApiPage = await service.search_live_videos("fixture")
	_check(first.is_success() and first.items.size() == 1 and (first.items[0] as YouTubeDiscoveryItem).id == "live-video", "manual live search returns typed results")
	_check(fake.requests.size() == 1 and fake.requests[0].method_id == "search.list", "live search uses the official search endpoint")
	var cached: YouTubeApiPage = await service.search_live_videos("fixture")
	_check(cached.from_cache and fake.requests.size() == 1, "repeated discovery uses the bounded cache")
	var throttled: YouTubeApiPage = await service.search_live_videos("fixture", "live", "", "", 25, true)
	_check(throttled.error != null and throttled.error.category == "discovery_throttled", "forced tight search is rejected")
	service.clear_cache()
	_check(service.cached_query_count() == 0, "discovery cache clears deterministically")


func _test_chat_actions() -> void:
	var fake: FakeApiClient = FakeApiClient.new()
	var gate: YouTubeCapabilityGate = _gate(PackedStringArray(["chat.write", "poll.manage"]), true)
	var service: YouTubeLiveChatService = YouTubeLiveChatService.new(fake, gate)
	fake.enqueue(_response({"id": "message-1", "snippet": {"type": "textMessageEvent", "liveChatId": "chat-1", "textMessageDetails": {"messageText": "Hello"}}}))
	var sent: YouTubeOperationResult = await service.send_text("chat-1", "Hello")
	_check(sent.is_success() and (sent.value as YouTubeLiveEvent).text_details.message_text == "Hello", "chat send returns a typed message")
	_check(fake.requests[0].body.snippet.type == "textMessageEvent", "chat send emits the official text body")
	fake.enqueue(_response({"id": "poll-1", "snippet": {"type": "pollEvent", "liveChatId": "chat-1", "pollDetails": {"metadata": {"questionText": "Route?", "status": "active", "options": [{"optionText": "A"}, {"optionText": "B"}]}}}}))
	var created: YouTubeOperationResult = await service.create_poll("chat-1", "Route?", PackedStringArray(["A", "B"]))
	_check(created.is_success() and (created.value as YouTubeLiveEvent).poll_details.options.size() == 2, "poll creation returns typed poll data")
	_check((fake.requests[1].body.snippet.pollDetails.metadata.options as Array).size() == 2, "poll creation emits two ordered option objects")
	var denied_close: YouTubeOperationResult = await service.close_poll("poll-1", false)
	_check(denied_close.error.category == "confirmation_required" and fake.requests.size() == 2, "poll close requires confirmation before HTTP")
	fake.enqueue(_response({"id": "poll-1", "snippet": {"type": "pollEvent", "pollDetails": {"metadata": {"questionText": "Route?", "status": "closed", "options": []}}}}))
	var closed: YouTubeOperationResult = await service.close_poll("poll-1", true)
	_check(closed.is_success() and fake.requests[2].query.status == "closed", "confirmed poll close uses transition status closed")


func _test_moderation_actions() -> void:
	var fake: FakeApiClient = FakeApiClient.new()
	var gate: YouTubeCapabilityGate = _gate(PackedStringArray(["moderation.ban", "moderation.unban", "moderation.read", "moderation.manage", "moderation.delete_message"]), true)
	var service: YouTubeModerationService = YouTubeModerationService.new(fake, gate)
	var denied: YouTubeOperationResult = await service.ban_user("chat-1", "target", "temporary", 300, false)
	_check(denied.error.category == "confirmation_required" and fake.requests.is_empty(), "ban requires confirmation before HTTP")
	fake.enqueue(_response({"id": "ban-1", "snippet": {"liveChatId": "chat-1", "type": "temporary", "banDurationSeconds": "300", "bannedUserDetails": {"channelId": "target"}}}))
	var banned: YouTubeOperationResult = await service.ban_user("chat-1", "target", "temporary", 300, true)
	_check(banned.is_success() and (banned.value as YouTubeLiveChatBan).duration_seconds == 300, "temporary ban returns a typed resource")
	_check(fake.requests[0].body.snippet.banDurationSeconds == 300, "temporary ban sends its duration")
	fake.enqueue(_response({"items": [{"id": "moderator-1", "snippet": {"liveChatId": "chat-1", "moderatorDetails": {"channelId": "mod", "displayName": "Moderator"}}}], "pageInfo": {"totalResults": 1, "resultsPerPage": 1}}))
	var moderators: YouTubeApiPage = await service.list_moderators("chat-1")
	_check(moderators.is_success() and (moderators.items[0] as YouTubeLiveChatModerator).channel_id == "mod", "moderator listing is typed")
	fake.enqueue(_response({"id": "moderator-2", "snippet": {"liveChatId": "chat-1", "moderatorDetails": {"channelId": "new-mod", "displayName": "New Moderator"}}}))
	var added: YouTubeOperationResult = await service.add_moderator("chat-1", "new-mod", true)
	_check(added.is_success() and (added.value as YouTubeLiveChatModerator).channel_id == "new-mod", "confirmed moderator addition returns a typed resource")
	_check(fake.requests[2].body.snippet.moderatorDetails.channelId == "new-mod", "moderator addition sends the target channel")
	fake.enqueue(_response(null, 204))
	var removed: YouTubeOperationResult = await service.remove_moderator("moderator-2", true)
	_check(removed.is_success() and removed.value == true and fake.requests[3].http_method == HTTPClient.METHOD_DELETE, "confirmed moderator removal accepts an empty response")
	fake.enqueue(_response(null, 204))
	var deleted: YouTubeOperationResult = await service.delete_message("message-1", true)
	_check(deleted.is_success() and fake.requests[4].query.id == "message-1", "confirmed message deletion reaches the official resource ID")
	fake.enqueue(_response(null, 204))
	var unbanned: YouTubeOperationResult = await service.unban_user("ban-1", true)
	_check(unbanned.is_success() and fake.requests[5].query.id == "ban-1", "confirmed unban reaches the ban resource")


func _test_broadcast_actions() -> void:
	var fake: FakeApiClient = FakeApiClient.new()
	var gate: YouTubeCapabilityGate = _gate(PackedStringArray(["broadcast.read", "broadcast.manage", "broadcast.bind", "broadcast.transition", "broadcast.cuepoint"]), true)
	var service: YouTubeBroadcastService = YouTubeBroadcastService.new(fake, gate)
	fake.enqueue(_response({"items": [{"id": "broadcast-1", "snippet": {"title": "Fixture", "liveChatId": "chat-1"}, "status": {"lifeCycleStatus": "ready"}, "contentDetails": {"boundStreamId": "stream-1"}}], "pageInfo": {"totalResults": 1, "resultsPerPage": 1}}))
	var page: YouTubeApiPage = await service.list_broadcasts()
	_check(page.is_success() and (page.items[0] as YouTubeLiveBroadcast).bound_stream_id == "stream-1", "broadcast discovery returns typed bindings")
	var broadcast: YouTubeLiveBroadcast = YouTubeLiveBroadcast.new()
	broadcast.title = "New Fixture"
	broadcast.scheduled_start_time = "2026-08-11T12:00:00Z"
	broadcast.privacy_status = "unlisted"
	fake.enqueue(_response({"id": "broadcast-new", "snippet": {"title": broadcast.title, "scheduledStartTime": broadcast.scheduled_start_time}, "status": {"privacyStatus": "unlisted"}}))
	var created: YouTubeOperationResult = await service.create_broadcast(broadcast)
	_check(created.is_success() and (created.value as YouTubeLiveBroadcast).id == "broadcast-new", "broadcast creation returns typed resource")
	_check(fake.requests[1].body.status.privacyStatus == "unlisted", "broadcast creation sends explicit privacy")
	broadcast.id = "broadcast-new"
	broadcast.title = "Updated Fixture"
	fake.enqueue(_response({"id": "broadcast-new", "snippet": {"title": broadcast.title, "scheduledStartTime": broadcast.scheduled_start_time}, "status": {"privacyStatus": "unlisted"}}))
	var updated: YouTubeOperationResult = await service.update_broadcast(broadcast, PackedStringArray(["snippet"]))
	_check(updated.is_success() and (updated.value as YouTubeLiveBroadcast).title == "Updated Fixture", "broadcast metadata update returns a typed resource")
	_check(fake.requests[2].http_method == HTTPClient.METHOD_PUT and fake.requests[2].body.id == "broadcast-new", "broadcast update uses PUT and includes its ID")
	var invalid_transition: YouTubeOperationResult = await service.transition_broadcast("broadcast-1", "complete", "ready", true)
	_check(invalid_transition.error.category == "invalid_state" and fake.requests.size() == 3, "invalid broadcast transition is blocked locally")
	fake.enqueue(_response({"id": "broadcast-1", "snippet": {"title": "Fixture"}, "status": {"lifeCycleStatus": "live"}}))
	var live_result: YouTubeOperationResult = await service.transition_broadcast("broadcast-1", "live", "ready", true)
	_check(live_result.is_success() and fake.requests[3].query.broadcastStatus == "live", "valid confirmed transition reaches the official endpoint")
	fake.enqueue(_response({"id": "broadcast-new", "snippet": {"title": "Updated Fixture"}, "status": {"lifeCycleStatus": "ready"}, "contentDetails": {"boundStreamId": "stream-1"}}))
	var bound: YouTubeOperationResult = await service.bind_stream("broadcast-new", "stream-1", true)
	_check(bound.is_success() and (bound.value as YouTubeLiveBroadcast).bound_stream_id == "stream-1", "confirmed stream binding returns the updated broadcast")
	_check(fake.requests[4].query.streamId == "stream-1", "stream binding sends the selected stream ID")
	fake.enqueue(_response({"id": "broadcast-new", "snippet": {"title": "Updated Fixture"}, "status": {"lifeCycleStatus": "ready"}, "contentDetails": {}}))
	var unbound: YouTubeOperationResult = await service.bind_stream("broadcast-new", "", true)
	_check(unbound.is_success() and (unbound.value as YouTubeLiveBroadcast).bound_stream_id.is_empty(), "empty stream ID supports the official unbind operation")
	var invalid_cuepoint: YouTubeOperationResult = await service.insert_cuepoint("broadcast-new", true, 30, 0, 1000)
	_check(invalid_cuepoint.error.category == "invalid_request" and fake.requests.size() == 6, "cuepoint rejects conflicting offset and wall-time fields locally")
	fake.enqueue(_response({"id": "cue-1", "cueType": "cueTypeAd", "durationSecs": 45, "insertionOffsetTimeMs": 0}))
	var cuepoint: YouTubeOperationResult = await service.insert_cuepoint("broadcast-new", true, 45, 0)
	_check(cuepoint.is_success() and (cuepoint.value as Dictionary).id == "cue-1", "confirmed cuepoint returns the inserted resource")
	_check(fake.requests[6].body.cueType == "cueTypeAd" and fake.requests[6].body.durationSecs == 45 and fake.requests[6].body.insertionOffsetTimeMs == 0, "cuepoint sends the current official top-level resource body")
	var unconfirmed_delete: YouTubeOperationResult = await service.delete_broadcast("broadcast-1", false)
	_check(unconfirmed_delete.error.category == "confirmation_required" and fake.requests.size() == 7, "broadcast deletion requires confirmation")
	fake.enqueue(_response(null, 204))
	var deleted: YouTubeOperationResult = await service.delete_broadcast("broadcast-new", true)
	_check(deleted.is_success() and deleted.value == true and fake.requests[7].http_method == HTTPClient.METHOD_DELETE, "confirmed broadcast deletion accepts an empty response")


func _test_stream_actions() -> void:
	var fake: FakeApiClient = FakeApiClient.new()
	var gate: YouTubeCapabilityGate = _gate(PackedStringArray(["stream.read", "stream.manage"]), true)
	var service: YouTubeStreamService = YouTubeStreamService.new(fake, gate)
	fake.enqueue(_response({"items": [{"id": "stream-existing", "snippet": {"title": "Existing"}, "cdn": {"ingestionType": "rtmp", "resolution": "1080p", "frameRate": "60fps"}}], "pageInfo": {"totalResults": 1, "resultsPerPage": 1}}))
	var listed: YouTubeApiPage = await service.list_streams()
	_check(listed.is_success() and (listed.items[0] as YouTubeLiveStream).id == "stream-existing", "stream discovery returns typed resources")
	var stream: YouTubeLiveStream = YouTubeLiveStream.new()
	stream.title = "Encoder"
	stream.ingestion_type = "rtmp"
	stream.resolution = "1080p"
	stream.frame_rate = "60fps"
	fake.enqueue(_response({"id": "stream-new", "snippet": {"title": "Encoder"}, "cdn": {"ingestionType": "rtmp", "resolution": "1080p", "frameRate": "60fps", "ingestionInfo": {"streamName": "fixture-stream-secret"}}}))
	var created: YouTubeOperationResult = await service.create_stream(stream)
	_check(created.is_success() and (created.value as YouTubeLiveStream).stream_name == "fixture-stream-secret", "stream creation exposes the in-memory ingestion name")
	_check(not (fake.requests[1].body.cdn as Dictionary).has("ingestionInfo"), "stream create never echoes server ingestion credentials")
	stream.id = "stream-new"
	stream.cdn_details = {"ingestionInfo": {"streamName": "must-not-send"}}
	fake.enqueue(_response({"id": "stream-new", "snippet": {"title": "Encoder"}, "cdn": {"ingestionType": "rtmp", "resolution": "1080p", "frameRate": "60fps", "ingestionInfo": {"streamName": "rotated-fixture-secret"}}}))
	var updated: YouTubeOperationResult = await service.update_stream(stream, PackedStringArray(["cdn"]))
	_check(updated.is_success() and (updated.value as YouTubeLiveStream).stream_name == "rotated-fixture-secret", "stream configuration update returns typed ingestion data")
	_check(fake.requests[2].http_method == HTTPClient.METHOD_PUT and not (fake.requests[2].body.cdn as Dictionary).has("ingestionInfo"), "stream update strips ingestion credentials from its request")
	var denied_delete: YouTubeOperationResult = await service.delete_stream("stream-new", false)
	_check(denied_delete.error.category == "confirmation_required" and fake.requests.size() == 3, "stream deletion requires confirmation")
	fake.enqueue(_response(null, 204))
	var deleted: YouTubeOperationResult = await service.delete_stream("stream-new", true)
	_check(deleted.is_success() and deleted.value == true and fake.requests[3].http_method == HTTPClient.METHOD_DELETE, "confirmed stream deletion accepts an empty 204 response")


func _test_monetization() -> void:
	var fake: FakeApiClient = FakeApiClient.new()
	fake.enqueue(_response({"items": [{"id": "super-1", "snippet": {"channelId": "owner", "supporterDetails": {"channelId": "supporter", "displayName": "Supporter"}, "amountMicros": "1000000", "currency": "USD", "displayString": "$1.00", "messageType": 1}}]}))
	var service: YouTubeMonetizationService = YouTubeMonetizationService.new(fake, _gate(PackedStringArray(["monetization.read"]), true))
	var page: YouTubeApiPage = await service.list_super_chat_events()
	_check(page.is_success() and page.items.size() == 1, "Super Chat history listing succeeds")
	var event: YouTubeSuperChatEvent = page.items[0]
	_check(event.amount_micros == 1000000 and event.supporter_channel_id == "supporter", "Super Chat history is typed")


func _test_media_policy() -> void:
	var cache: YouTubeMediaCache = YouTubeMediaCache.new()
	var insecure: YouTubeMediaResult = await cache.fetch_texture("http://example.com/avatar.png")
	_check(insecure.error != null and insecure.error.category == "invalid_request", "media cache rejects non-loopback plaintext HTTP")
	cache.cache_directory = "user://outside-redot-tuber"
	_check(cache.clear_data() != null, "media clear refuses a directory outside its bounded namespace")
	cache.free()


func _gate(capabilities: PackedStringArray, authenticated: bool) -> YouTubeCapabilityGate:
	var gate: YouTubeCapabilityGate = YouTubeCapabilityGate.new()
	gate.configure(capabilities, authenticated)
	return gate


func _response(payload: Variant, status_code: int = 200) -> YouTubeHttpResponse:
	var response: YouTubeHttpResponse = YouTubeHttpResponse.new()
	response.status_code = status_code
	response.parsed_json = payload
	return response


func _load_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	_check(file != null, "fixture opens: %s" % path)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(parsed is Dictionary, "fixture is an object: %s" % path)
	return parsed if parsed is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("MS-004/MS-005 SERVICE PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-004/MS-005 SERVICE FAIL: %s" % failure)
	print("MS-004/MS-005 SERVICE FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
