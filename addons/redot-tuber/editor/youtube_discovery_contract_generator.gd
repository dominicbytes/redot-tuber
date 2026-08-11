@tool
class_name YouTubeDiscoveryContractGenerator
extends RefCounted

## Converts the public Google Discovery document shape into a small,
## deterministic method contract. Runtime code uses checked-in reviewed
## contracts; this tool is for maintainers, never for live game startup.


func extract_methods(discovery: Dictionary) -> Array[Dictionary]:
	var methods: Array[Dictionary] = []
	var resources_value: Variant = discovery.get("resources", {})
	if resources_value is Dictionary:
		_walk_resources("", resources_value, methods)
	methods.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left.id) < String(right.id))
	return methods


func render_contract_json(discovery: Dictionary) -> String:
	var contract: Dictionary = {
		"discovery_revision": String(discovery.get("revision", "")),
		"discovery_root_url": String(discovery.get("rootUrl", "")),
		"discovery_service_path": String(discovery.get("servicePath", "")),
		"methods": extract_methods(discovery),
	}
	return JSON.stringify(contract, "  ", false, true) + "\n"


func _walk_resources(prefix: String, resources: Dictionary, output: Array[Dictionary]) -> void:
	var resource_names: Array = resources.keys()
	resource_names.sort()
	for resource_name_value: Variant in resource_names:
		var resource_name: String = String(resource_name_value)
		var resource_value: Variant = resources[resource_name_value]
		if not resource_value is Dictionary:
			continue
		var resource: Dictionary = resource_value
		var qualified: String = resource_name if prefix.is_empty() else prefix + "." + resource_name
		var method_values: Variant = resource.get("methods", {})
		if method_values is Dictionary:
			var method_names: Array = method_values.keys()
			method_names.sort()
			for method_name_value: Variant in method_names:
				var method_value: Variant = method_values[method_name_value]
				if method_value is Dictionary:
					output.append(_extract_method(qualified + "." + String(method_name_value), method_value))
		var nested_value: Variant = resource.get("resources", {})
		if nested_value is Dictionary:
			_walk_resources(qualified, nested_value, output)


func _extract_method(method_id: String, source: Dictionary) -> Dictionary:
	var scopes: PackedStringArray = PackedStringArray()
	var scopes_value: Variant = source.get("scopes", [])
	if scopes_value is Array:
		for scope: Variant in scopes_value:
			scopes.append(String(scope))
	scopes.sort()
	var required_parameters: PackedStringArray = PackedStringArray()
	var parameters_value: Variant = source.get("parameters", {})
	if parameters_value is Dictionary:
		for parameter_name: Variant in parameters_value:
			var definition: Variant = parameters_value[parameter_name]
			if definition is Dictionary and bool(definition.get("required", false)):
				required_parameters.append(String(parameter_name))
	required_parameters.sort()
	return {
		"id": method_id,
		"http_method": String(source.get("httpMethod", "GET")),
		"path": String(source.get("path", "")),
		"required_parameters": required_parameters,
		"scopes": scopes,
	}
