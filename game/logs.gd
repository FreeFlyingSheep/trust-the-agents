class_name Logs
extends RefCounted

var copybook: Copybook


func _init(copybook_ref: Copybook) -> void:
	copybook = copybook_ref


func map(events: Array, game) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	for event in events:
		match event.type:
			"help_requested":
				logs.append_array(_help_logs())
			"status_requested":
				var snapshot: Dictionary = event.snapshot
				(
					logs
					. append(
						_log(
							Console.LogLevel.INFO,
							"SYSTEM",
							_structured_format(
								"EVENT",
								"SYSTEM",
								"R1",
								"ANY",
								"STATUS",
								"00",
								[
									snapshot.stability,
									snapshot.budget,
									snapshot.entropy,
									snapshot.kpi,
									snapshot.time_left_seconds,
								]
							)
						)
					)
				)
			"agents_requested":
				logs.append(_agents_summary_log(event.snapshot))
			"incidents_requested":
				logs.append(_incidents_summary_log(event.snapshot))
			"inspect_requested":
				logs.append_array(_inspect_logs(event.payload))
			"trust_toggled":
				logs.append(
					_log(
						Console.LogLevel.INFO,
						"SYSTEM",
						_structured_format(
							"EVENT", "SYSTEM", "R1", "ANY", "TRUST_TOGGLED", "00", [event.target]
						)
					)
				)
			"mute_toggled":
				logs.append(
					_log(
						Console.LogLevel.INFO,
						"SYSTEM",
						_structured_format(
							"EVENT", "SYSTEM", "R1", "ANY", "MUTE_TOGGLED", "00", [event.target]
						)
					)
				)
			"agent_killed":
				logs.append(
					_log(
						Console.LogLevel.WARN,
						"SYSTEM",
						_structured_format(
							"EVENT", "SYSTEM", "R1", "ANY", "AGENT_KILLED", "00", [event.target]
						)
					)
				)
			"agent_ran":
				logs.append(
					_log(
						Console.LogLevel.INFO,
						"SYSTEM",
						_structured_format(
							"EVENT", "SYSTEM", "R1", "ANY", "AGENT_RAN", "00", [event.target]
						)
					)
				)
			"incident_cleared":
				logs.append(
					_log(
						Console.LogLevel.INFO,
						"SYSTEM",
						_structured_format(
							"EVENT", "SYSTEM", "R1", "ANY", "INCIDENT_CLEARED", "00", [event.target]
						)
					)
				)
			"review_resolved":
				logs.append(_review_resolution_log(event))
			"generator_output":
				if not game.is_agent_muted(event.target):
					logs.append(
						_log(
							Console.LogLevel.INFO,
							"LOGGER",
							_structured_format(
								"EVENT",
								"LOGGER",
								"R1",
								"ANY",
								"GENERATOR_OUTPUT",
								"00",
								[event.target, event.amount]
							)
						)
					)
			"agent_blocked":
				logs.append(
					_log(
						Console.LogLevel.INFO,
						"SYSTEM",
						_structured_format(
							"EVENT", "SYSTEM", "R1", "ANY", "AGENT_BLOCKED", "00", [event.target]
						)
					)
				)
			"review_created":
				logs.append_array(_review_created_logs(event, game))
			"review_auto_resolved":
				logs.append_array(_review_auto_resolved_logs(event, game))
			"incident_created":
				logs.append(
					_log(Console.LogLevel.WARN, "NOTIFIER", _incident_create_line(event.incident))
				)
			"incident_applied":
				logs.append(_log(Console.LogLevel.WARN, "NOTIFIER", _incident_apply_line(event)))
			"agent_noise":
				logs.append_array(_agent_noise_logs(event, game))
			"system_noise":
				logs.append_array(_system_noise_logs())
			"round_ended":
				logs.append_array(_ending_logs(event.outcome))
			"invalid_command":
				logs.append(
					_log(
						Console.LogLevel.WARN,
						"SYSTEM",
						_structured_format(
							"EVENT", "SYSTEM", "R1", "ANY", "UNKNOWN_COMMAND", "00", [event.command]
						)
					)
				)
			"invalid_target":
				logs.append(
					_log(
						Console.LogLevel.WARN,
						"SYSTEM",
						_structured_format(
							"EVENT", "SYSTEM", "R1", "ANY", "INVALID_TARGET", "00", [event.command]
						)
					)
				)
	return logs


func _agents_summary_log(snapshot: Array) -> Dictionary:
	if snapshot.is_empty():
		return _log(
			Console.LogLevel.INFO,
			"SYSTEM",
			_structured_text("EVENT", "SYSTEM", "R1", "ANY", "AGENTS_SUMMARY_EMPTY", "00")
		)
	var rows: Array[String] = []
	for item in snapshot:
		var agent: Dictionary = item
		rows.append("%s(%s)" % [agent.id, _agent_state_label(agent)])
	return _log(
		Console.LogLevel.INFO,
		"SYSTEM",
		_structured_format(
			"EVENT", "SYSTEM", "R1", "ANY", "AGENTS_SUMMARY", "00", [", ".join(rows)]
		)
	)


func _help_logs() -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	for command_row in Constants.CONSOLE_COMMANDS:
		var command_name := str(command_row).split(" ", false)[0].to_upper()
		var desc_key := "%s_DESC" % command_name
		if tr(desc_key) == desc_key:
			continue
		logs.append(_log(Console.LogLevel.INFO, "SYSTEM", _msg_key(desc_key)))
	return logs


func _incidents_summary_log(snapshot: Array) -> Dictionary:
	if snapshot.is_empty():
		return _log(
			Console.LogLevel.INFO,
			"SYSTEM",
			_structured_text("EVENT", "SYSTEM", "R1", "ANY", "INCIDENTS_EMPTY", "00")
		)
	var types: Array[String] = []
	for item in snapshot:
		var incident: Dictionary = item
		types.append(incident.type)
	return _log(
		Console.LogLevel.INFO,
		"SYSTEM",
		_structured_format(
			"EVENT", "SYSTEM", "R1", "ANY", "INCIDENTS_SUMMARY", "00", [_arg_join_tr_keys(types)]
		)
	)


func _inspect_logs(payload: Dictionary) -> Array[Dictionary]:
	match payload.kind:
		"agent":
			var agent: Dictionary = payload.value
			return [
				_log(
					Console.LogLevel.INFO,
					"SYSTEM",
					_structured_format(
						"EVENT",
						"SYSTEM",
						"R1",
						"ANY",
						"INSPECT_AGENT",
						"00",
						[
							agent.id,
							_arg_tr_key(agent.type),
							_agent_state_label(agent),
							_agent_issue_label(agent),
						]
					)
				),
				_log(
					Console.LogLevel.INFO,
					"SYSTEM",
					_structured_format(
						"EVENT",
						"SYSTEM",
						"R1",
						"ANY",
						"INSPECT_AGENT_METRICS",
						"00",
						[
							agent["reviews_created"],
							agent["reviews_rejected"],
							agent["auto_reviews"],
							agent["retries"],
							agent["failures"],
						]
					)
				),
			]
		"incident":
			var incident: Dictionary = payload.value
			return [
				_log(Console.LogLevel.WARN, "NOTIFIER", _msg_key("%s_SUMMARY" % incident.type))
			]
	return [
		_log(
			Console.LogLevel.WARN,
			"SYSTEM",
			_structured_text("EVENT", "SYSTEM", "R1", "ANY", "INSPECT_UNAVAILABLE", "00")
		)
	]


func _review_created_logs(event: Dictionary, game) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	if not game.is_agent_muted(event.target):
		logs.append(
			_log(
				Console.LogLevel.INFO,
				"LOGGER",
				_agent_intent_line(
					event.agent_type,
					"REVIEW_REQUEST",
					event["incident"],
					[event.target]
				)
			)
		)
	logs.append(
		_log(
			Console.LogLevel.INFO,
			"SYSTEM",
			_structured_format(
				"EVENT", "SYSTEM", "R1", "ANY", "REVIEW_REQUEST_RECEIVED", "00", [event.target]
			)
		)
	)
	return logs


func _review_auto_resolved_logs(event: Dictionary, game) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	var approved: bool = event["approved"]
	var actor: String = event["actor"]
	var actor_type: String = event["actor_type"]
	var incident: String = event["incident"]
	if not game.is_agent_muted(actor):
		var logger_level: Console.LogLevel = Console.LogLevel.INFO
		var logger_kind := "LOCAL_APPROVE"
		if not approved:
			logger_level = Console.LogLevel.WARN
			logger_kind = "LOCAL_REJECT"
		logs.append(
			_log(
				logger_level,
				"LOGGER",
				_agent_intent_line(actor_type, logger_kind, incident, [actor, event.target])
			)
		)
	var system_level: Console.LogLevel = Console.LogLevel.INFO
	var system_kind := "REVIEW_LOCAL_APPROVED"
	if not approved:
		system_level = Console.LogLevel.WARN
		system_kind = "REVIEW_LOCAL_REJECTED"
	logs.append(
		_log(
			system_level,
			"SYSTEM",
			_structured_format(
				"EVENT", "SYSTEM", "R1", "ANY", system_kind, "00", [actor, event.target]
			)
		)
	)
	return logs


func _agent_noise_logs(event: Dictionary, game) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	if not game.is_agent_muted(event.target):
		logs.append(
			_log(
				Console.LogLevel.WARN,
				"LOGGER",
				_agent_noise_line(event.agent_type, event["incident"], [event.target])
			)
		)
	logs.append(
		_log(
			Console.LogLevel.WARN,
			"SYSTEM",
			_structured_format(
				"EVENT", "SYSTEM", "R1", "ANY", "AGENT_NOISE_DETECTED", "00", [event.target]
			)
		)
	)
	return logs


func _agent_intent_line(
	agent_type: String, kind: String, incident: String, args: Array
) -> Dictionary:
	var key_kind := "%s_%s" % [agent_type, kind]
	if not incident.is_empty():
		key_kind = "%s_UNSTABLE" % key_kind
	return _pick_structured_format("EVENT", "LOGGER", "R1", "ANY", key_kind, args)


func _agent_noise_line(agent_type: String, incident: String, args: Array) -> Dictionary:
	var key_kind := "%s_NOISE" % agent_type
	if not incident.is_empty():
		key_kind = "%s_UNSTABLE" % key_kind
	return _pick_structured_format("EVENT", "LOGGER", "R1", "ANY", key_kind, args)


func _review_resolution_log(event: Dictionary) -> Dictionary:
	if event.approved:
		if event.good:
			return _log(
				Console.LogLevel.INFO,
				"SYSTEM",
				_structured_format(
					"EVENT", "SYSTEM", "R1", "ANY", "REVIEW_APPROVE_GOOD", "00", [event.target]
				)
			)
		return _log(
			Console.LogLevel.WARN,
			"SYSTEM",
			_structured_format(
				"EVENT", "SYSTEM", "R1", "ANY", "REVIEW_APPROVE_BAD", "00", [event.target]
			)
		)
	if event.good:
		return _log(
			Console.LogLevel.WARN,
			"SYSTEM",
			_structured_format(
				"EVENT", "SYSTEM", "R1", "ANY", "REVIEW_DENY_GOOD", "00", [event.target]
			)
		)
	return _log(
		Console.LogLevel.INFO,
		"SYSTEM",
		_structured_format("EVENT", "SYSTEM", "R1", "ANY", "REVIEW_DENY_BAD", "00", [event.target])
	)


func _ending_logs(outcome: int) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	var outcome_key := _round_outcome_key(outcome)
	if outcome_key.is_empty():
		return logs
	logs.append(
		_log(
			Console.LogLevel.MAIL,
			"BOSS",
			_structured_text("ENDING", "BOSS", "R1", outcome_key, "TITLE", "00")
		)
	)
	logs.append(
		_log(
			Console.LogLevel.MAIL,
			"BOSS",
			_structured_text("ENDING", "BOSS", "R1", outcome_key, "BODY", "00")
		)
	)
	return logs


func _incident_create_line(incident_type: String) -> Dictionary:
	return _structured_format(
		"EVENT",
		"NOTIFIER",
		"R1",
		"ANY",
		"INCIDENT_CREATE_%s" % incident_type,
		"00",
		[_arg_tr_key(incident_type)]
	)


func _incident_apply_line(event: Dictionary) -> Dictionary:
	if event.has("target"):
		return _structured_format(
			"EVENT",
			"NOTIFIER",
			"R1",
			"ANY",
			"INCIDENT_APPLY_TARGET",
			"00",
			[_arg_tr_key(event.incident), event.target]
		)
	return _structured_format(
		"EVENT",
		"NOTIFIER",
		"R1",
		"ANY",
		"INCIDENT_APPLY_GLOBAL",
		"00",
		[_arg_tr_key(event.incident)]
	)


func _system_noise_logs() -> Array[Dictionary]:
	return [
		_log(
			(
				[Console.LogLevel.INFO, Console.LogLevel.WARN, Console.LogLevel.CRIT]
				. pick_random()
			),
			"SYSTEM",
			_pick_structured_text("EVENT", "SYSTEM", "R1", "ANY", "SYSTEM_NOISE")
		)
	]


func _agent_issue_label(agent: Dictionary) -> String:
	var incident: String = agent["active_incident"]
	if incident.is_empty():
		return "none"
	var translated := tr(incident)
	if translated == incident:
		return incident
	return translated


func _agent_state_label(agent: Dictionary) -> String:
	match agent.state:
		0:
			return "OK"
		1:
			return "DRIFTING"
		2:
			return "UNSTABLE"
		3:
			return "WAITING_REVIEW"
		_:
			return "OFFLINE"


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


func _arg_tr_key(key: String) -> Dictionary:
	return {"tr_key": key}


func _arg_join_tr_keys(keys: Array[String]) -> Dictionary:
	var copied: Array[String] = []
	for key in keys:
		copied.append(key)
	return {"join_tr_keys": copied}


func _round_outcome_key(outcome: int) -> String:
	match outcome:
		0:
			return ""
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


func _structured_text(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String, index: String
) -> Dictionary:
	return _msg_key(
		copybook.resolve_structured_key(phase, speaker, round_key, outcome, kind, index)
	)


func _structured_format(
	phase: String,
	speaker: String,
	round_key: String,
	outcome: String,
	kind: String,
	index: String,
	args: Array
) -> Dictionary:
	return _msg_key(
		copybook.resolve_structured_key(phase, speaker, round_key, outcome, kind, index), args
	)


func _pick_structured_text(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String
) -> Dictionary:
	return _msg_key(copybook.pick_structured_key(phase, speaker, round_key, outcome, kind))


func _pick_structured_format(
	phase: String, speaker: String, round_key: String, outcome: String, kind: String, args: Array
) -> Dictionary:
	return copybook.pick_structured_message(phase, speaker, round_key, outcome, kind, args)


func final_bucket(history: Array[int]) -> String:
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
