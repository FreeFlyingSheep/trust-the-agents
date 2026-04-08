class_name TextOps
extends RefCounted

var copybook: Copybook
var ending_rules


func _init(copybook_ref: Copybook) -> void:
	assert(copybook_ref != null)
	copybook = copybook_ref
	ending_rules = preload("res://game/ending_rules.gd").new()


func simple_system_log(kind: String, args: Array) -> Dictionary:
	return entry(
		Console.LogLevel.INFO,
		"SYSTEM",
		structured_format("EVENT", "SYSTEM", "R1", "ANY", kind, "00", args)
	)


func agent_state_label(agent: Dictionary) -> String:
	assert(agent.has("state"))
	match agent["state"]:
		0:
			return tr("AGENT_STATE_OK")
		1:
			return tr("AGENT_STATE_DRIFTING")
		2:
			return tr("AGENT_STATE_UNSTABLE")
		3:
			return tr("AGENT_STATE_WAITING_REVIEW")
		4:
			return tr("AGENT_STATE_OFFLINE")
		_:
			assert(false, "Unknown agent state label")
	return ""


func entry(level: int, event_key: String, message: Variant) -> Dictionary:
	var entry := {
		"level": level,
		"event_key": event_key,
	}
	if message is Dictionary and message.has("key"):
		entry["message_key"] = message["key"]
		entry["message_args"] = message["args"]
		entry["message"] = ""
	else:
		entry["message"] = message
	return entry


func msg_key(key: String, args: Array = []) -> Dictionary:
	assert(not key.is_empty())
	return {"key": key, "args": args}


func arg_tr_key(key: String) -> Dictionary:
	assert(not key.is_empty())
	return {"tr_key": key}


func arg_join_tr_keys(keys: Array[String]) -> Dictionary:
	assert(not keys.is_empty())
	var copied: Array[String] = []
	for key in keys:
		copied.append(key)
	return {"join_tr_keys": copied}


func round_outcome_key(outcome: int) -> String:
	return ending_rules.round_outcome_key(outcome)


func structured_text(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String, index: String
) -> Dictionary:
	return msg_key(copybook.resolve_structured_key(phase, speaker, round_key, outcome, kind, index))


func structured_format(
	phase: String,
	speaker: String,
	round_key: String,
	outcome: String,
	kind: String,
	index: String,
	args: Array
) -> Dictionary:
	return msg_key(
		copybook.resolve_structured_key(phase, speaker, round_key, outcome, kind, index), args
	)
