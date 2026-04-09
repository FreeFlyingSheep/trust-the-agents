class_name Copybook
extends RefCounted

const EN_TRANSLATION_PATH := "res://game/transcripts.en.translation"

var _keys_by_prefix: Dictionary = {}


func _init() -> void:
	_load_transcript_index()
	assert(not _keys_by_prefix.is_empty())


func resolve_structured_key(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String, index: String
) -> String:
	var candidates := _candidate_keys(phase, speaker, round_key, outcome, kind, index)
	for key in candidates:
		if _key_exists(key):
			return key
	assert(false, "Missing structured key: %s" % candidates[0])
	return ""


func pick_structured_key(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String
) -> String:
	for prefix in _candidate_prefixes(phase, speaker, round_key, outcome, kind):
		var keys: Array[String] = _keys_for_prefix(prefix)
		if not keys.is_empty():
			return keys.pick_random()
	assert(
		false, "Missing structured variant: %s" % _prefix(phase, speaker, round_key, outcome, kind)
	)
	return ""


func pick_structured_message(
	phase: String,
	speaker: String,
	round_key: String,
	outcome: String,
	kind: String,
	args: Array = []
) -> Dictionary:
	return {"key": pick_structured_key(phase, speaker, round_key, outcome, kind), "args": args}


func list_structured_messages(
	phase: String,
	speaker: String,
	round_key: String,
	outcome: String,
	kind: String,
	args: Array = []
) -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	for key in list_structured_keys(phase, speaker, round_key, outcome, kind):
		messages.append({"key": key, "args": args})
	return messages


func list_structured_keys(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String
) -> Array[String]:
	for prefix in _candidate_prefixes(phase, speaker, round_key, outcome, kind):
		var keys: Array[String] = _keys_for_prefix(prefix)
		if not keys.is_empty():
			return keys
	assert(
		false,
		"Missing structured key family: %s" % _prefix(phase, speaker, round_key, outcome, kind)
	)
	return []


func has_structured_variant(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String
) -> bool:
	for prefix in _candidate_prefixes(phase, speaker, round_key, outcome, kind):
		if not _keys_for_prefix(prefix).is_empty():
			return true
	return false


func _load_transcript_index() -> void:
	_keys_by_prefix.clear()
	var translation := load(EN_TRANSLATION_PATH) as Translation
	assert(translation != null, "Missing translation resource: %s" % EN_TRANSLATION_PATH)
	var keys: PackedStringArray = translation.get_message_list()
	assert(not keys.is_empty(), "Translation has no message keys: %s" % EN_TRANSLATION_PATH)
	for raw_key in keys:
		if raw_key.is_empty():
			continue
		_register_key(raw_key)


func _register_key(key: String) -> void:
	var parts := key.split("__", false)
	if parts.size() != 6:
		return
	var prefix := "%s__%s__%s__%s__%s" % [parts[0], parts[1], parts[2], parts[3], parts[4]]
	if not _keys_by_prefix.has(prefix):
		_keys_by_prefix[prefix] = []
	var keys: Array = _keys_by_prefix[prefix]
	keys.append(key)
	keys.sort()
	_keys_by_prefix[prefix] = keys


func _candidate_keys(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String, index: String
) -> Array[String]:
	assert(not index.is_empty())
	var keys: Array[String] = []
	for prefix in _candidate_prefixes(phase, speaker, round_key, outcome, kind):
		keys.append("%s__%s" % [prefix, index])
	return keys


func _candidate_prefixes(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String
) -> Array[String]:
	assert(not phase.is_empty())
	assert(not speaker.is_empty())
	assert(not round_key.is_empty())
	assert(not outcome.is_empty())
	assert(not kind.is_empty())
	return [
		_prefix(phase, speaker, round_key, outcome, kind),
		_prefix(phase, speaker, round_key, "ANY", kind),
		_prefix(phase, speaker, "R1", outcome, kind),
		_prefix(phase, speaker, "R1", "ANY", kind),
	]


func _prefix(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String
) -> String:
	assert(not phase.is_empty())
	assert(not speaker.is_empty())
	assert(not round_key.is_empty())
	assert(not outcome.is_empty())
	assert(not kind.is_empty())
	return "%s__%s__%s__%s__%s" % [phase, speaker, round_key, outcome, kind]


func _keys_for_prefix(prefix: String) -> Array[String]:
	assert(not prefix.is_empty())
	if not _keys_by_prefix.has(prefix):
		return []
	var keys: Array[String] = []
	for key in _keys_by_prefix[prefix]:
		keys.append(key)
	return keys


func _key_exists(key: String) -> bool:
	var parts := key.rsplit("__", false, 1)
	assert(parts.size() == 2)
	return _keys_by_prefix.has(parts[0]) and key in _keys_by_prefix[parts[0]]
