class_name Scripts
extends RefCounted

var copybook: Copybook


func _init(copybook_ref: Copybook) -> void:
	copybook = copybook_ref


func build_boot_logs() -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	logs.append(_log(Console.LogLevel.NONE, "TITLE", Constants.VERSION))
	logs.append_array(
		_sequential_structured_logs(
			Console.LogLevel.NONE, "BOOT", "BOOTING", "BOOT", "R1", "ANY", "BOOT"
		)
	)
	logs.append_array(
		_sequential_structured_logs_by_level(
			[
				Console.LogLevel.INFO,
				Console.LogLevel.WARN,
				Console.LogLevel.CRIT,
				Console.LogLevel.MAIL
			],
			"LOGGER",
			"BOOTING",
			"LOGGER",
			"R1",
			"ANY",
			"LOGGER"
		)
	)
	logs.append_array(
		_sequential_structured_logs(
			Console.LogLevel.INFO, "SYSTEM", "BOOTING", "SYSTEM", "R1", "ANY", "SLOTS"
		)
	)
	logs.append(
		_log(
			Console.LogLevel.INFO,
			"SYSTEM",
			_structured_text("EVENT", "SYSTEM", "R1", "ANY", "LOGIN", "00")
		)
	)
	return logs


func finish_boot_and_build_login_logs(game) -> Array[Dictionary]:
	game.finish_boot()
	var login_logs: Array[Dictionary] = [
		_log(
			Console.LogLevel.INFO,
			"SYSTEM",
			_structured_text("EVENT", "SYSTEM", "R1", "ANY", "LOGIN_OK", "00")
		)
	]
	login_logs.append_array(_post_login_boot_logs(game))
	return login_logs


func build_round_transition_logs(game) -> Array[Dictionary]:
	if game.has_more_rounds():
		game.begin_next_round()
		return build_boot_logs()
	return build_final_summary_logs(game)


func build_final_summary_logs(game) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	var bucket := _final_bucket(game.outcome_history)
	logs.append(
		_log(
			Console.LogLevel.MAIL,
			"BOSS",
			_structured_text("ENDING", "BOSS", "R3", bucket, "TAG", "00")
		)
	)
	logs.append(
		_log(
			Console.LogLevel.MAIL,
			"BOSS",
			_structured_text("ENDING", "BOSS", "R3", bucket, "BODY", "00")
		)
	)
	return logs


func _post_login_boot_logs(game) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	logs.append_array(
		_sequential_structured_logs(
			Console.LogLevel.MAIL, "BOSS", "BOOTING", "BOSS", "R1", "ANY", "KPI"
		)
	)
	var previous_user: String = game.previous_user_key()
	var round_key := "R%d" % game.round_index
	var outcome_key := _round_outcome_key(game.last_outcome)
	for message in copybook.list_structured_messages(
		"HANDOFF", previous_user, round_key, outcome_key, "CORE"
	):
		logs.append(_log(Console.LogLevel.MAIL, previous_user, message))
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
	var logs: Array[Dictionary] = []
	var messages: Array[Dictionary] = copybook.list_structured_messages(
		phase, speaker, round_key, outcome, kind
	)
	for index in range(messages.size()):
		var level_index := mini(index, levels_list.size() - 1)
		logs.append(_log(levels_list[level_index], event_key, messages[index]))
	return logs


func _round_outcome_key(outcome: int) -> String:
	match outcome:
		1:
			return "TIMEOUT"
		2:
			return "BUDGET"
		3:
			return "COLLAPSE"
		4:
			return "KPI"
		_:
			return ""


func _final_bucket(history: Array[int]) -> String:
	var budget_count := 0
	var collapse_count := 0
	var timeout_count := 0
	var kpi_count := 0
	var bucket: String = Constants.CONSOLE_FINAL_BUCKET_REORG
	for outcome in history:
		match outcome:
			2:
				budget_count += 1
			3:
				collapse_count += 1
			1:
				timeout_count += 1
			4:
				kpi_count += 1

	if budget_count >= Constants.CONSOLE_FINAL_BUCKET_DOMINANT_THRESHOLD:
		bucket = Constants.CONSOLE_FINAL_BUCKET_SHUTDOWN
	elif collapse_count >= Constants.CONSOLE_FINAL_BUCKET_DOMINANT_THRESHOLD:
		bucket = Constants.CONSOLE_FINAL_BUCKET_LIQUIDATION
	elif timeout_count >= Constants.CONSOLE_FINAL_BUCKET_DOMINANT_THRESHOLD:
		bucket = Constants.CONSOLE_FINAL_BUCKET_PIVOT
	elif kpi_count >= Constants.CONSOLE_FINAL_BUCKET_DOMINANT_THRESHOLD:
		bucket = Constants.CONSOLE_FINAL_BUCKET_REDUNDANCY
	elif budget_count == 0:
		bucket = Constants.CONSOLE_FINAL_BUCKET_EXIT
	elif collapse_count == 0:
		bucket = Constants.CONSOLE_FINAL_BUCKET_ACQUISITION
	elif timeout_count == 0:
		bucket = Constants.CONSOLE_FINAL_BUCKET_SPINOFF
	elif kpi_count == 0:
		bucket = Constants.CONSOLE_FINAL_BUCKET_REORG
	return bucket
