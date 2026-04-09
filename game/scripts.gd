class_name Scripts
extends RefCounted

var copybook: Copybook
var ending_rules


func _init(copybook_ref: Copybook) -> void:
	assert(copybook_ref != null)
	copybook = copybook_ref
	ending_rules = preload("res://game/ending_rules.gd").new()


func build_boot_logs() -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	logs.append(_log(Console.LogLevel.NONE, "TITLE", Constants.VERSION))
	logs.append_array(
		_sequential_structured_logs(
			Console.LogLevel.NONE, "BOOT", "BOOTING", "BOOT", "R1", "ANY", "BOOT"
		)
	)
	logs.append_array(_logger_boot_logs_without_mail_channel())
	logs.append_array(
		_sequential_structured_logs(
			Console.LogLevel.INFO, "SYSTEM", "BOOTING", "SYSTEM", "R1", "ANY", "SLOTS"
		)
	)
	return logs


func _logger_boot_logs_without_mail_channel() -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	var messages: Array[Dictionary] = copybook.list_structured_messages(
		"BOOTING", "LOGGER", "R1", "ANY", "LOGGER"
	)
	assert(messages.size() >= 3)
	logs.append(_log(Console.LogLevel.INFO, "LOGGER", messages[0]))
	logs.append(_log(Console.LogLevel.WARN, "LOGGER", messages[1]))
	logs.append(_log(Console.LogLevel.CRIT, "LOGGER", messages[2]))
	return logs


func finish_boot_and_build_login_logs(game: Game) -> Array[Dictionary]:
	var login_logs: Array[Dictionary] = []
	login_logs.append_array(_post_login_boot_logs(game))
	return login_logs


func build_round_transition_logs(game: Game) -> Array[Dictionary]:
	if game.has_more_rounds():
		game.begin_next_round()
		return build_boot_logs()
	return build_final_summary_logs(game)


func build_final_summary_logs(game: Game) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	var bucket: String = ending_rules.final_bucket(game.outcome_history)
	logs.append(
		_log(
			Console.LogLevel.INFO,
			"BOSS",
			_structured_text("ENDING", "BOSS", "R3", bucket, "TAG", "00")
		)
	)
	logs.append(
		_log(
			Console.LogLevel.INFO,
			"BOSS",
			_structured_text("ENDING", "BOSS", "R3", bucket, "BODY", "00")
		)
	)
	return logs


func _post_login_boot_logs(game: Game) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	logs.append(
		_log(
			Console.LogLevel.INFO,
			"BOSS",
			copybook.pick_structured_message("BOOTING", "BOSS", "R1", "ANY", "KPI")
		)
	)
	var previous_user: String = game.previous_user_key()
	var round_key := "R%d" % game.round_index
	var outcome_key: String = ending_rules.round_outcome_key(game.last_outcome)
	if outcome_key.is_empty():
		outcome_key = "ANY"
	logs.append(
		_log(
			Console.LogLevel.INFO,
			previous_user,
			copybook.pick_structured_message(
				"HANDOFF", previous_user, round_key, outcome_key, "CORE"
			)
		)
	)
	return logs


func _log(level: int, event_key: String, message: Variant) -> Dictionary:
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


func _msg_key(key: String, args: Array = []) -> Dictionary:
	assert(not key.is_empty())
	return {"key": key, "args": args}


func _structured_text(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String, index: String
) -> Dictionary:
	return _msg_key(
		copybook.resolve_structured_key(phase, speaker, round_key, outcome, kind, index)
	)


func _sequential_structured_logs(
	level: int,
	event_key: String,
	phase: String,
	speaker: String,
	round_key: String,
	outcome: String,
	kind: String
) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	for message in copybook.list_structured_messages(phase, speaker, round_key, outcome, kind):
		logs.append(_log(level, event_key, message))
	return logs


func _sequential_structured_logs_by_level(
	levels_list: Array[int],
	event_key: String,
	phase: String,
	speaker: String,
	round_key: String,
	outcome: String,
	kind: String
) -> Array[Dictionary]:
	assert(not levels_list.is_empty())
	var logs: Array[Dictionary] = []
	var messages: Array[Dictionary] = copybook.list_structured_messages(
		phase, speaker, round_key, outcome, kind
	)
	for index in range(messages.size()):
		var level_index := mini(index, levels_list.size() - 1)
		logs.append(_log(levels_list[level_index], event_key, messages[index]))
	return logs
