class_name YouTubePollDetails
extends RefCounted

var question_text: String = ""
var status: String = "unknown"
var options: Array[Dictionary] = []


static func from_api(source: Dictionary) -> YouTubePollDetails:
	var value: YouTubePollDetails = YouTubePollDetails.new()
	var metadata: Dictionary = source.get("metadata", {}) if source.get("metadata", {}) is Dictionary else {}
	value.question_text = String(metadata.get("questionText", ""))
	value.status = String(metadata.get("status", "unknown"))
	var option_values: Variant = metadata.get("options", [])
	if option_values is Dictionary:
		option_values = [option_values]
	if option_values is Array:
		for option: Variant in option_values:
			if option is Dictionary:
				value.options.append({
					"option_text": String(option.get("optionText", "")),
					"tally": String(option.get("tally", "")),
				})
	return value
