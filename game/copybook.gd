class_name Copybook
extends RefCounted

const TRANSCRIPTS_PATH := "res://game/transcripts.csv"

var _keys_by_prefix: Dictionary = {}


func _init() -> void:
	_load_transcript_index()


func resolve_structured_key(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String, index: String
) -> String:
	var candidates := _candidate_keys(phase, speaker, round_key, outcome, kind, index)
	for key in candidates:
		if _key_exists(key):
			return key
	return candidates[0]


func pick_structured_key(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String
) -> String:
	for prefix in _candidate_prefixes(phase, speaker, round_key, outcome, kind):
		var keys: Array[String] = _keys_for_prefix(prefix)
		if not keys.is_empty():
			return keys.pick_random()
	return "%s__00" % _candidate_prefixes(phase, speaker, round_key, outcome, kind)[0]


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
	return ["%s__00" % _candidate_prefixes(phase, speaker, round_key, outcome, kind)[0]]


func has_structured_variant(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String
) -> bool:
	for prefix in _candidate_prefixes(phase, speaker, round_key, outcome, kind):
		if not _keys_for_prefix(prefix).is_empty():
			return true
	return false


func _load_transcript_index() -> void:
	_keys_by_prefix.clear()
	var file := FileAccess.open(TRANSCRIPTS_PATH, FileAccess.READ)
	if file == null:
		return

	var is_header := true
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty():
			continue
		var raw_key := str(row[0]).strip_edges()
		if raw_key.is_empty():
			continue
		if is_header:
			is_header = false
			if raw_key == "keys":
				continue
		_register_key(raw_key)


func _register_key(key: String) -> void:
	var parts := key.split("__", false)
	if parts.size() != 6:
		return
	var prefix := (
		"%s__%s__%s__%s__%s"
		% [
			parts[0],
			parts[1],
			parts[2],
			parts[3],
			parts[4],
		]
	)
	if not _keys_by_prefix.has(prefix):
		_keys_by_prefix[prefix] = []
	var keys: Array = _keys_by_prefix[prefix]
	keys.append(key)
	keys.sort()
	_keys_by_prefix[prefix] = keys


func _candidate_keys(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String, index: String
) -> Array[String]:
	var keys: Array[String] = []
	for prefix in _candidate_prefixes(phase, speaker, round_key, outcome, kind):
		keys.append("%s__%s" % [prefix, index])
	return keys


func _candidate_prefixes(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String
) -> Array[String]:
	return [
		_prefix(phase, speaker, round_key, outcome, kind),
		_prefix(phase, speaker, round_key, "ANY", kind),
		_prefix(phase, speaker, "R1", outcome, kind),
		_prefix(phase, speaker, "R1", "ANY", kind),
	]


func _prefix(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String
) -> String:
	return "%s__%s__%s__%s__%s" % [phase, speaker, round_key, outcome, kind]


func _keys_for_prefix(prefix: String) -> Array[String]:
	if not _keys_by_prefix.has(prefix):
		return []
	var keys: Array[String] = []
	for key in _keys_by_prefix[prefix]:
		keys.append(str(key))
	return keys


func _key_exists(key: String) -> bool:
	var parts := key.rsplit("__", false, 1)
	if parts.size() != 2:
		return false
	return _keys_by_prefix.has(parts[0]) and key in _keys_by_prefix[parts[0]]
