class_name YouTubeCapabilityRegistry
extends RefCounted

const READONLY_SCOPE: String = "https://www.googleapis.com/auth/youtube.readonly"
const FORCE_SSL_SCOPE: String = "https://www.googleapis.com/auth/youtube.force-ssl"

const METHOD_DEFINITIONS: Dictionary = {
	"channels.list": {"capability":"channel.read", "scope":READONLY_SCOPE, "quota_units":1},
	"videos.list": {"capability":"discovery.read", "scope":READONLY_SCOPE, "quota_units":1},
	"search.list": {"capability":"discovery.read", "scope":READONLY_SCOPE, "quota_units":1, "quota_bucket":"search_queries"},
	"liveChatMessages.list": {"capability":"chat.read", "scope":READONLY_SCOPE, "quota_units":1},
	"liveChatMessages.streamList": {"capability":"chat.read", "scope":READONLY_SCOPE, "quota_units":1, "availability":"Windows/Linux x86-64 native helper; other platforms use list polling"},
	"liveChatMessages.insert": {"capability":"chat.write", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true},
	"liveChatMessages.transition": {"capability":"poll.manage", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true},
	"liveChatMessages.delete": {"capability":"moderation.delete_message", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true},
	"liveChatBans.insert": {"capability":"moderation.ban", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true},
	"liveChatBans.delete": {"capability":"moderation.unban", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true},
	"liveChatModerators.list": {"capability":"moderation.read", "scope":FORCE_SSL_SCOPE, "quota_units":1, "oauth":true},
	"liveChatModerators.insert": {"capability":"moderation.manage", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true},
	"liveChatModerators.delete": {"capability":"moderation.manage", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true},
	"liveBroadcasts.list": {"capability":"broadcast.read", "scope":READONLY_SCOPE, "quota_units":1, "oauth":true, "availability":"channel must be enabled for live streaming"},
	"liveBroadcasts.insert": {"capability":"broadcast.manage", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "availability":"channel must be enabled for live streaming"},
	"liveBroadcasts.update": {"capability":"broadcast.manage", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true},
	"liveBroadcasts.delete": {"capability":"broadcast.manage", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true},
	"liveBroadcasts.bind": {"capability":"broadcast.bind", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true},
	"liveBroadcasts.transition": {"capability":"broadcast.transition", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true},
	"liveBroadcasts.cuepoint": {"capability":"broadcast.cuepoint", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true, "availability":"broadcast must be actively streaming; ad eligibility is account dependent"},
	"liveStreams.list": {"capability":"stream.read", "scope":READONLY_SCOPE, "quota_units":1, "oauth":true, "availability":"channel must be enabled for live streaming"},
	"liveStreams.insert": {"capability":"stream.manage", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "availability":"channel must be enabled for live streaming"},
	"liveStreams.update": {"capability":"stream.manage", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true},
	"liveStreams.delete": {"capability":"stream.manage", "scope":FORCE_SSL_SCOPE, "quota_units":50, "oauth":true, "write":true, "confirm":true},
	"superChatEvents.list": {"capability":"monetization.read", "scope":READONLY_SCOPE, "quota_units":1, "oauth":true, "availability":"returns eligible Super Chat and Super Sticker purchases from the previous 30 days"},
}


static func method_info(method_id: String) -> YouTubeCapabilityInfo:
	var source: Variant = METHOD_DEFINITIONS.get(method_id, {})
	if not source is Dictionary or source.is_empty():
		return null
	return YouTubeCapabilityInfo.from_definition(method_id, source)


static func all_method_info() -> Array[YouTubeCapabilityInfo]:
	var ids: Array = METHOD_DEFINITIONS.keys()
	ids.sort()
	var result: Array[YouTubeCapabilityInfo] = []
	for id_value: Variant in ids:
		result.append(method_info(String(id_value)))
	return result
