class_name Logs
extends RefCounted

var copybook: Copybook
var text
var review_level_override_remaining := 0
var review_level_override_target := Console.LogLevel.INFO


func _init(copybook_ref: Copybook) -> void:
	assert(copybook_ref != null)
	copybook = copybook_ref
	text = preload("res://game/text.gd").new(copybook_ref)


func map(events: Array, game) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	for event in events:
		assert(event.has("type"))
		var mapped_entries: Array[Dictionary] = []
		match event["type"]:
			"status_requested":
				mapped_entries.append(_status_log(event["snapshot"]))
			"agents_requested":
				mapped_entries.append(_agents_summary_log(event["snapshot"]))
			"incidents_requested":
				mapped_entries.append(_incidents_summary_log(event["snapshot"]))
			"inspect_requested":
				mapped_entries.append_array(_inspect_logs(event["payload"]))
			"trust_toggled":
				mapped_entries.append(text.simple_system_log("TRUST_TOGGLED", [event["target"]]))
			"mute_toggled":
				mapped_entries.append(text.simple_system_log("MUTE_TOGGLED", [event["target"]]))
			"agent_killed":
				mapped_entries.append(
					text.entry(
						Console.LogLevel.WARN,
						"SYSTEM",
						text.structured_format(
							"EVENT", "SYSTEM", "R1", "ANY", "AGENT_KILLED", "00", [event["target"]]
						)
					)
				)
			"agent_ran":
				mapped_entries.append(text.simple_system_log("AGENT_RAN", [event["target"]]))
			"incident_patched":
				mapped_entries.append(
					text.simple_system_log("INCIDENT_PATCHED", [event["incident"], event["target"]])
				)
			"review_resolved":
				mapped_entries.append(_review_resolved_log(event))
			"task_planned":
				mapped_entries.append(_task_planned_log(event, game))
			"task_step_started":
				mapped_entries.append(_task_step_log(event))
			"tool_completed":
				mapped_entries.append(_tool_completed_log(event, game))
			"review_requested":
				mapped_entries.append(_review_requested_log(event))
			"task_applied":
				mapped_entries.append(_task_applied_log(event, game))
			"task_canceled":
				mapped_entries.append(_task_canceled_log(event))
			"task_replanned":
				mapped_entries.append(_task_replanned_log(event))
			"replan_skipped":
				mapped_entries.append(_replan_skipped_log(event))
			"incident_created":
				mapped_entries.append(_incident_created_log(event))
			"incident_applied":
				mapped_entries.append(_incident_applied_log(event))
			"round_ended":
				mapped_entries.append_array(_ending_logs(event["outcome"]))
			"mail_delivered":
				assert(event.has("log"))
				mapped_entries.append(event["log"])
			_:
				assert(false, "Unknown event type in Logs.map")
		for entry in mapped_entries:
			logs.append(_apply_review_level_override(entry))
		if event["type"] == "review_resolved":
			_update_review_level_override_from_review_event(event)
	return logs


func map_tick(events: Array, game) -> Array[Dictionary]:
	return map(events, game)


func _apply_review_level_override(entry: Dictionary) -> Dictionary:
	assert(entry.has("level"))
	if review_level_override_remaining <= 0:
		return entry
	if int(entry["level"]) != Console.LogLevel.INFO:
		return entry
	var adjusted := entry.duplicate(true)
	adjusted["level"] = review_level_override_target
	review_level_override_remaining -= 1
	return adjusted


func _update_review_level_override_from_review_event(event: Dictionary) -> void:
	assert(event.has("approved"))
	assert(event.has("content_quality"))
	var content_quality: String = str(event["content_quality"])
	assert(content_quality in [Constants.REVIEW_CONTENT_GOOD, Constants.REVIEW_CONTENT_BAD])
	if event["approved"] and content_quality == Constants.REVIEW_CONTENT_BAD:
		review_level_override_target = Console.LogLevel.CRIT
		review_level_override_remaining = Constants.REVIEW_DECISION_IMPACT_LOG_COUNT
		return
	if (not event["approved"]) and content_quality == Constants.REVIEW_CONTENT_GOOD:
		review_level_override_target = Console.LogLevel.WARN
		review_level_override_remaining = Constants.REVIEW_DECISION_IMPACT_LOG_COUNT
		return
	review_level_override_remaining = 0


func _status_log(snapshot: Dictionary) -> Dictionary:
	assert(snapshot.has("stability"))
	assert(snapshot.has("budget"))
	assert(snapshot.has("entropy"))
	assert(snapshot.has("kpi"))
	assert(snapshot.has("time_left_seconds"))
	return (
		text
		. entry(
			Console.LogLevel.INFO,
			"SYSTEM",
			(
				text
				. structured_format(
					"EVENT",
					"SYSTEM",
					"R1",
					"ANY",
					"STATUS",
					"00",
					[
						snapshot["stability"],
						snapshot["budget"],
						snapshot["entropy"],
						snapshot["kpi"],
						snapshot["time_left_seconds"],
					]
				)
			)
		)
	)


func _agents_summary_log(snapshot: Array) -> Dictionary:
	if snapshot.is_empty():
		return text.entry(
			Console.LogLevel.INFO,
			"SYSTEM",
			text.structured_text("EVENT", "SYSTEM", "R1", "ANY", "AGENTS_SUMMARY_EMPTY", "00")
		)
	var rows: Array[String] = []
	for item in snapshot:
		assert(item.has("id"))
		assert(item.has("state"))
		rows.append("%s(%s)" % [item["id"], text.agent_state_label(item)])
	return text.entry(
		Console.LogLevel.INFO,
		"SYSTEM",
		text.structured_format(
			"EVENT", "SYSTEM", "R1", "ANY", "AGENTS_SUMMARY", "00", [", ".join(rows)]
		)
	)


func _incidents_summary_log(snapshot: Array) -> Dictionary:
	if snapshot.is_empty():
		return text.entry(
			Console.LogLevel.INFO,
			"SYSTEM",
			text.structured_text("EVENT", "SYSTEM", "R1", "ANY", "INCIDENTS_EMPTY", "00")
		)
	var tokens: Array[String] = []
	for item in snapshot:
		assert(item.has("type"))
		tokens.append(item["type"])
	return text.entry(
		Console.LogLevel.INFO,
		"SYSTEM",
		text.structured_format(
			"EVENT",
			"SYSTEM",
			"R1",
			"ANY",
			"INCIDENTS_SUMMARY",
			"00",
			[text.arg_join_tr_keys(tokens)]
		)
	)


func _inspect_logs(payload: Dictionary) -> Array[Dictionary]:
	assert(payload.has("kind"))
	assert(payload.has("value"))
	match payload["kind"]:
		"agent":
			var agent: Dictionary = payload["value"]
			var incident_label: Variant = text.arg_tr_key("NONE_LABEL")
			if not agent["active_incidents"].is_empty():
				incident_label = text.arg_join_tr_keys(agent["active_incidents"])
			return [
				(
					text
					. entry(
						Console.LogLevel.INFO,
						"SYSTEM",
						(
							text
							. structured_format(
								"EVENT",
								"SYSTEM",
								"R1",
								"ANY",
								"INSPECT_AGENT",
								"00",
								[
									agent["id"],
									text.arg_tr_key(agent["type"]),
									text.agent_state_label(agent),
									incident_label,
								]
							)
						)
					)
				),
			]
		"incident":
			var incident: Dictionary = payload["value"]
			return [
				text.entry(
					Console.LogLevel.WARN,
					"NOTIFIER",
					text.structured_format(
						"EVENT",
						"SYSTEM",
						"R1",
						"ANY",
						"INSPECT_INCIDENT",
						"00",
						[incident["id"], text.arg_tr_key(incident["type"]), incident["agent_id"]]
					)
				),
			]
		"goal":
			var goal_payload: Dictionary = payload["value"]
			return [
				(
					text
					. entry(
						Console.LogLevel.INFO,
						"SYSTEM",
						(
							text
							. structured_format(
								"EVENT",
								"SYSTEM",
								"R1",
								"ANY",
								"INSPECT_GOAL",
								"00",
								[
									goal_payload["id"],
									text.arg_tr_key("GOAL_STATUS_%s" % goal_payload["status"]),
									goal_payload["kpi_baseline"],
									goal_payload["kpi_target"],
								]
							)
						)
					)
				),
			]
		"task":
			var task: Dictionary = payload["value"]
			return [
				(
					text
					. entry(
						Console.LogLevel.INFO,
						"SYSTEM",
						(
							text
							. structured_format(
								"EVENT",
								"SYSTEM",
								"R1",
								"ANY",
								"INSPECT_TASK",
								"00",
								[
									task["id"],
									text.arg_tr_key(task["role"]),
									text.arg_tr_key("TASK_STATUS_%s" % task["status"]),
									task["current_step"],
								]
							)
						)
					)
				),
			]
		_:
			assert(false, "Unsupported inspect payload kind")
	return []


func _task_planned_log(event: Dictionary, game) -> Dictionary:
	assert(event.has("task_id"))
	assert(event.has("target"))
	assert(event.has("planned_by"))
	var level := Console.LogLevel.INFO
	if not game.flow._is_agent_muted(game, event["target"]):
		level = Console.LogLevel.INFO
	return text.entry(
		level,
		"LOGGER",
		text.structured_format(
			"EVENT",
			"LOGGER",
			"R1",
			"ANY",
			"TASK_PLANNED",
			"00",
			[event["task_id"], event["target"], event["planned_by"]]
		)
	)


func _task_step_log(event: Dictionary) -> Dictionary:
	return text.entry(
		Console.LogLevel.INFO,
		"SYSTEM",
		text.structured_format(
			"EVENT",
			"SYSTEM",
			"R1",
			"ANY",
			"TASK_STEP_STARTED",
			"00",
			[event["task_id"], event["target"], event["step"]]
		)
	)


func _tool_completed_log(event: Dictionary, game) -> Dictionary:
	var event_key := "LOGGER"
	if game.flow._is_agent_muted(game, event["target"]):
		event_key = "SYSTEM"
	return text.entry(
		Console.LogLevel.INFO,
		event_key,
		text.structured_format(
			"EVENT",
			event_key,
			"R1",
			"ANY",
			"TOOL_COMPLETED",
			"00",
			[event["task_id"], event["target"], event["tool"]]
		)
	)


func _review_requested_log(event: Dictionary) -> Dictionary:
	return text.entry(
		Console.LogLevel.INFO,
		"SYSTEM",
		text.structured_format(
			"EVENT",
			"SYSTEM",
			"R1",
			"ANY",
			"REVIEW_REQUESTED",
			"00",
			[event["ticket_id"], event["task_id"], event["target"]]
		)
	)


func _review_resolved_log(event: Dictionary) -> Dictionary:
	var kind := "REVIEW_RESOLVED_APPROVED"
	var level := Console.LogLevel.INFO
	if not event["approved"]:
		kind = "REVIEW_RESOLVED_DENIED"
		level = Console.LogLevel.WARN
	return text.entry(
		level,
		"SYSTEM",
		text.structured_format(
			"EVENT",
			"SYSTEM",
			"R1",
			"ANY",
			kind,
			"00",
			[event["task_id"], event["target"], event["actor"]]
		)
	)


func _task_applied_log(event: Dictionary, game) -> Dictionary:
	var event_key := "LOGGER"
	if game.flow._is_agent_muted(game, event["target"]):
		event_key = "SYSTEM"
	return (
		text
		. entry(
			Console.LogLevel.INFO,
			event_key,
			(
				text
				. structured_format(
					"EVENT",
					event_key,
					"R1",
					"ANY",
					"TASK_APPLIED",
					"00",
					[
						event["task_id"],
						event["target"],
						event["kpi_delta"],
						event["stability_delta"],
						event["entropy_delta"],
					]
				)
			)
		)
	)


func _task_canceled_log(event: Dictionary) -> Dictionary:
	return text.entry(
		Console.LogLevel.WARN,
		"SYSTEM",
		text.structured_format(
			"EVENT",
			"SYSTEM",
			"R1",
			"ANY",
			"TASK_CANCELED",
			"00",
			[event["task_id"], event["target"], event["reason"]]
		)
	)


func _task_replanned_log(event: Dictionary) -> Dictionary:
	return text.entry(
		Console.LogLevel.INFO,
		"SYSTEM",
		text.structured_format(
			"EVENT",
			"SYSTEM",
			"R1",
			"ANY",
			"TASK_REPLANNED",
			"00",
			[event["from_task_id"], event["task_id"], event["target"]]
		)
	)


func _replan_skipped_log(event: Dictionary) -> Dictionary:
	return text.entry(
		Console.LogLevel.WARN,
		"SYSTEM",
		text.structured_format(
			"EVENT",
			"SYSTEM",
			"R1",
			"ANY",
			"REPLAN_SKIPPED",
			"00",
			[event["task_id"], event["reason"]]
		)
	)


func _incident_created_log(event: Dictionary) -> Dictionary:
	return text.entry(
		Console.LogLevel.WARN,
		"NOTIFIER",
		text.structured_format(
			"EVENT",
			"NOTIFIER",
			"R1",
			"ANY",
			"INCIDENT_CREATED",
			"00",
			[event["incident_id"], text.arg_tr_key(event["incident"]), event["target"]]
		)
	)


func _incident_applied_log(event: Dictionary) -> Dictionary:
	return text.entry(
		Console.LogLevel.WARN,
		"NOTIFIER",
		text.structured_format(
			"EVENT",
			"NOTIFIER",
			"R1",
			"ANY",
			"INCIDENT_APPLIED",
			"00",
			[event["incident_id"], text.arg_tr_key(event["incident"]), event["target"]]
		)
	)


func _ending_logs(outcome: int) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	var outcome_key: String = text.round_outcome_key(outcome)
	if outcome_key.is_empty():
		return logs
	logs.append(
		text.entry(
			Console.LogLevel.INFO,
			"BOSS",
			text.structured_text("ENDING", "BOSS", "R1", outcome_key, "TITLE", "00")
		)
	)
	logs.append(
		text.entry(
			Console.LogLevel.INFO,
			"BOSS",
			text.structured_text("ENDING", "BOSS", "R1", outcome_key, "BODY", "00")
		)
	)
	return logs
