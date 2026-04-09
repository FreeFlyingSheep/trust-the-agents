extends Node2D

enum LoginPhase { WAITING_LOGIN, READY }

var ui_root: Control
var title_label: Label
var hotkey_hint_label: Label
var time_label: Label
var round_label: Label
var status_title_label: Label
var agents_title_label: Label
var reviews_title_label: Label
var mail_title_label: Label
var agents_list_container: Control
var task_slots_container: VBoxContainer
var review_slots_container: VBoxContainer
var log_view: RichTextLabel
var mail_list: ItemList
var mail_detail_view: RichTextLabel

var status_name_labels: Dictionary = {}
var status_value_labels: Dictionary = {}
var last_agent_board_signature: String = ""
var last_review_signature: String = ""
var login_phase: int = LoginPhase.WAITING_LOGIN
var pending_review_items: Array[Dictionary] = []
var system_focus_text: String = ""
var agent_activity_text: Dictionary = {}
var startup_sequence_pending := false
var feed: Feed
var board: Board

var game: Game
var console: Console


func _t(key: String) -> String:
	var translated := tr(key)
	assert(translated != key, "Missing translation key: %s" % key)
	return translated


func _tf(key: String, args: Array = []) -> String:
	var template := _t(key)
	if args.is_empty():
		assert(template.find("%") == -1, "Unexpected format pattern in key: %s" % key)
		return template
	assert(template.find("%") != -1, "Missing format pattern in key: %s" % key)
	return template % args


func _reason_text(reason: String) -> String:
	var key := "REASON_%s" % reason.to_upper()
	return _t(key)


func _ready() -> void:
	var system_language := OS.get_locale_language().to_lower()
	if system_language.begins_with("zh"):
		TranslationServer.set_locale("zh")
	else:
		TranslationServer.set_locale("en")
	game = Game.new()
	console = Console.new()
	feed = Feed.new()
	board = Board.new()
	_build_ui()
	login_phase = LoginPhase.WAITING_LOGIN
	system_focus_text = ""
	_start_round_intro_sequence()
	_refresh_chrome()


func _build_ui() -> void:
	var ui := Ui.new().build(self, "", console.status_items(game))
	ui_root = ui["ui_root"]
	title_label = ui["title_label"]
	hotkey_hint_label = ui["hotkey_hint_label"]
	time_label = ui["time_label"]
	round_label = ui["round_label"]
	status_title_label = ui["status_title_label"]
	agents_title_label = ui["agents_title_label"]
	reviews_title_label = ui["reviews_title_label"]
	mail_title_label = ui["mail_title_label"]
	status_name_labels = ui["status_name_labels"]
	status_value_labels = ui["status_value_labels"]
	agents_list_container = ui["agents_list_container"]
	task_slots_container = ui["task_slots_container"]
	review_slots_container = ui["review_slots_container"]
	log_view = ui["log_view"]
	mail_list = ui["mail_list"]
	mail_detail_view = ui["mail_detail_view"]
	feed.bind_views(log_view, mail_list, mail_detail_view)
	_wire_action_handlers()
	_refresh_locale_ui()


func _wire_action_handlers() -> void:
	assert(mail_list != null)
	mail_list.item_selected.connect(_on_mail_selected)


func _emit_events(events: Array[Dictionary]) -> void:
	_apply_event_feedback(events)
	_append_event_logs(events)
	_handle_round_transition_if_needed()
	_refresh_chrome()


func _process(delta: float) -> void:
	var delayed_mail_events := game.advance_delayed_mail(delta)
	if not delayed_mail_events.is_empty():
		_emit_events(delayed_mail_events)
	if game.run_state == Game.RunState.RUNNING and login_phase == LoginPhase.READY:
		var tick_events := game.advance_time(delta)
		if not tick_events.is_empty():
			_emit_events(tick_events)
	feed.flush(delta)
	_complete_round_intro_if_ready()
	_handle_round_transition_if_needed()
	_refresh_chrome()


func _apply_event_feedback(events: Array[Dictionary]) -> void:
	for event in events:
		assert(event.has("type"))
		match event["type"]:
			"task_planned":
				assert(event.has("target"))
				assert(event.has("task_id"))
				agent_activity_text[event["target"]] = _tf(
					"ACTIVITY_TASK_PLANNED", [event["task_id"]]
				)
				system_focus_text = _tf("FOCUS_TASK_PLANNED", [event["target"], event["task_id"]])
			"task_step_started":
				assert(event.has("target"))
				assert(event.has("task_id"))
				assert(event.has("step"))
				agent_activity_text[event["target"]] = _tf(
					"ACTIVITY_TASK_STEP_STARTED", [event["step"], event["task_id"]]
				)
				system_focus_text = _tf("FOCUS_TASK_STEP_STARTED", [event["target"], event["step"]])
			"tool_completed":
				assert(event.has("target"))
				assert(event.has("tool"))
				agent_activity_text[event["target"]] = _tf(
					"ACTIVITY_TOOL_COMPLETED", [event["tool"]]
				)
				system_focus_text = _tf("FOCUS_TOOL_COMPLETED", [event["target"], event["tool"]])
			"review_requested":
				assert(event.has("target"))
				agent_activity_text[event["target"]] = _t("ACTIVITY_REVIEW_REQUESTED")
				system_focus_text = _tf("FOCUS_REVIEW_REQUESTED", [event["target"]])
			"review_resolved":
				assert(event.has("target"))
				assert(event.has("approved"))
				if event["approved"]:
					agent_activity_text[event["target"]] = _t("ACTIVITY_REVIEW_APPROVED")
					system_focus_text = _tf("FOCUS_REVIEW_APPROVED", [event["target"]])
				else:
					agent_activity_text[event["target"]] = _t("ACTIVITY_REVIEW_DENIED")
					system_focus_text = _tf("FOCUS_REVIEW_DENIED", [event["target"]])
			"task_applied":
				assert(event.has("target"))
				assert(event.has("task_id"))
				agent_activity_text[event["target"]] = _tf(
					"ACTIVITY_TASK_APPLIED", [event["task_id"]]
				)
				system_focus_text = _tf("FOCUS_TASK_APPLIED", [event["target"], event["task_id"]])
			"task_canceled":
				assert(event.has("target"))
				assert(event.has("reason"))
				var reason_text := _reason_text(event["reason"])
				agent_activity_text[event["target"]] = _tf("ACTIVITY_TASK_CANCELED", [reason_text])
				system_focus_text = _tf("FOCUS_TASK_CANCELED", [event["target"], reason_text])
			"task_replanned":
				assert(event.has("target"))
				assert(event.has("task_id"))
				agent_activity_text[event["target"]] = _tf(
					"ACTIVITY_TASK_REPLANNED", [event["task_id"]]
				)
				system_focus_text = _tf("FOCUS_TASK_REPLANNED", [event["target"], event["task_id"]])
			"replan_skipped":
				assert(event.has("reason"))
				system_focus_text = _tf("FOCUS_REPLAN_SKIPPED", [_reason_text(event["reason"])])
			"incident_created":
				assert(event.has("target"))
				assert(event.has("incident"))
				agent_activity_text[event["target"]] = _tf(
					"ACTIVITY_INCIDENT_CREATED", [tr(event["incident"])]
				)
				system_focus_text = _tf(
					"FOCUS_INCIDENT_CREATED", [event["target"], tr(event["incident"])]
				)
			"incident_applied":
				assert(event.has("target"))
				assert(event.has("incident"))
				agent_activity_text[event["target"]] = _tf(
					"ACTIVITY_INCIDENT_APPLIED", [tr(event["incident"])]
				)
				system_focus_text = _tf(
					"FOCUS_INCIDENT_APPLIED", [event["target"], tr(event["incident"])]
				)
			"incident_patched":
				assert(event.has("target"))
				assert(event.has("incident"))
				agent_activity_text[event["target"]] = _tf(
					"ACTIVITY_INCIDENT_PATCHED", [tr(event["incident"])]
				)
				system_focus_text = _tf(
					"FOCUS_INCIDENT_PATCHED", [tr(event["incident"]), event["target"]]
				)
			"agent_killed":
				assert(event.has("target"))
				agent_activity_text[event["target"]] = _t("ACTIVITY_AGENT_OFFLINE")
				system_focus_text = _tf("FOCUS_AGENT_OFFLINE", [event["target"]])
			"agent_ran":
				assert(event.has("target"))
				agent_activity_text[event["target"]] = _t("ACTIVITY_AGENT_ONLINE")
				system_focus_text = _tf("FOCUS_AGENT_ONLINE", [event["target"]])
			"trust_toggled":
				assert(event.has("target"))
				system_focus_text = _tf("FOCUS_TRUST_TOGGLED", [event["target"]])
			"mute_toggled":
				assert(event.has("target"))
				system_focus_text = _tf("FOCUS_MUTE_TOGGLED", [event["target"]])
			"round_ended":
				system_focus_text = _t("FOCUS_ROUND_ENDED")
			"mail_delivered":
				pass
			_:
				assert(false, "Unknown event type in _apply_event_feedback")


func _handle_round_transition_if_needed() -> void:
	if game.run_state != Game.RunState.ENDING:
		return
	if game.has_more_rounds():
		game.begin_next_round()
		login_phase = LoginPhase.WAITING_LOGIN
		system_focus_text = _t("FOCUS_NEXT_ROUND")
		last_agent_board_signature = ""
		last_review_signature = ""
		agent_activity_text.clear()
		_start_round_intro_sequence()
		return
	var final_logs := console.build_round_transition_logs(game)
	feed.append_immediate_logs(final_logs)
	login_phase = LoginPhase.READY
	system_focus_text = _t("FOCUS_SIMULATION_COMPLETED")


func _refresh_chrome() -> void:
	var logged_in := game.run_state == Game.RunState.RUNNING and login_phase == LoginPhase.READY
	time_label.text = console.time_text(game)
	round_label.text = console.round_text(game)
	_refresh_status_values()
	_refresh_task_slots(logged_in)
	_refresh_review_targets()
	_refresh_review_slots(logged_in)
	_refresh_agent_board(logged_in)


func _refresh_task_slots(logged_in: bool) -> void:
	board.refresh_task_slots(task_slots_container, logged_in, _goal_phase_tasks())


func _goal_phase_tasks() -> Array[Dictionary]:
	var goal: Dictionary = game.get_goal_snapshot()
	var status: Dictionary = game.get_status_snapshot()
	assert(goal.has("kpi_target"))
	assert(goal.has("status"))
	assert(status.has("kpi"))
	var target: float = goal["kpi_target"]
	var current: float = status["kpi"]
	assert(Constants.GOAL_PHASE_TASK_COUNT >= 1)
	assert(Constants.GOAL_PHASE_TASK_KEYS.size() == Constants.GOAL_PHASE_TASK_COUNT)
	var rows: Array[Dictionary] = []
	var all_previous_done := true
	for index in range(Constants.GOAL_PHASE_TASK_COUNT):
		var stage_target := target * float(index + 1) / float(Constants.GOAL_PHASE_TASK_COUNT)
		var stage_status := "WAITING"
		if current >= stage_target:
			stage_status = "DONE"
		elif all_previous_done and goal["status"] == Constants.GOAL_STATUS_ACTIVE:
			stage_status = "ACTIVE"
		elif goal["status"] in [Constants.GOAL_STATUS_FAILED, Constants.GOAL_STATUS_CANCELED]:
			stage_status = "FAILED"
		(
			rows
			. append(
				{
					"id": "phase-%d" % (index + 1),
					"content": _t(Constants.GOAL_PHASE_TASK_KEYS[index]),
					"status": stage_status,
				}
			)
		)
		if stage_status != "DONE":
			all_previous_done = false
	return rows


func _refresh_review_targets() -> void:
	pending_review_items.clear()
	for agent in game.get_agent_snapshot():
		assert(agent.has("id"))
		assert(agent.has("has_pending_review"))
		if not agent["has_pending_review"]:
			continue
		assert(agent.has("pending_review_id"))
		var ticket_id: String = agent["pending_review_id"]
		assert(not ticket_id.is_empty())
		assert(game.review_tickets.has(ticket_id))
		var ticket: Dictionary = game.review_tickets[ticket_id]
		assert(ticket.has("task_id"))
		assert(ticket.has("content_quality"))
		assert(
			(
				ticket["content_quality"]
				in [Constants.REVIEW_CONTENT_GOOD, Constants.REVIEW_CONTENT_BAD]
			)
		)
		var task_id: String = ticket["task_id"]
		assert(game.tasks.has(task_id))
		var task: Dictionary = game.tasks[task_id]
		assert(task.has("current_step"))
		assert(task.has("steps"))
		assert(task["current_step"] >= 0)
		assert(task["current_step"] < task["steps"].size())
		var review_item := {
			"ticket_id": ticket_id,
			"task_id": task_id,
			"agent_id": agent["id"],
			"step": task["steps"][task["current_step"]],
			"content_quality": ticket["content_quality"],
		}
		pending_review_items.append(review_item)


func _refresh_review_slots(logged_in: bool) -> void:
	var signature_parts: Array[String] = []
	for item in pending_review_items:
		assert(item.has("ticket_id"))
		assert(item.has("task_id"))
		assert(item.has("agent_id"))
		assert(item.has("step"))
		assert(item.has("content_quality"))
		signature_parts.append(
			(
				"%s|%s|%s|%s|%s"
				% [
					item["ticket_id"],
					item["task_id"],
					item["agent_id"],
					item["step"],
					item["content_quality"]
				]
			)
		)
	var signature := "%s|%s" % [logged_in, ";".join(signature_parts)]
	if signature == last_review_signature:
		return
	last_review_signature = signature
	board.refresh_review_slots(
		review_slots_container,
		logged_in,
		pending_review_items,
		_on_review_slot_approve_pressed,
		_on_review_slot_deny_pressed
	)


func _append_event_logs(events: Array[Dictionary]) -> void:
	var immediate_events: Array[Dictionary] = []
	var queued_events: Array[Dictionary] = []
	for event in events:
		assert(event.has("type"))
		if event["type"] == "mail_delivered":
			immediate_events.append(event)
			continue
		queued_events.append(event)
	if not immediate_events.is_empty():
		feed.append_immediate_logs(console.map_tick_events(immediate_events, game))
	if not queued_events.is_empty():
		feed.queue_mapped_logs(console.map_tick_events(queued_events, game))


func _on_mail_selected(index: int) -> void:
	feed.on_mail_selected(index)


func _refresh_locale_ui() -> void:
	title_label.text = tr("TITLE")
	hotkey_hint_label.text = tr("HOTKEY_HINT")
	status_title_label.text = tr("STATUS")
	agents_title_label.text = tr("AGENTS")
	reviews_title_label.text = tr("REVIEWS")
	mail_title_label.text = tr("MAIL")
	for key in status_name_labels.keys():
		var label: Label = status_name_labels[key]
		assert(label != null)
		label.text = tr(key)
	feed.rerender_views()
	last_agent_board_signature = ""
	last_review_signature = ""


func _refresh_agent_board(logged_in: bool) -> void:
	var snapshot: Array[Dictionary] = []
	if logged_in:
		for agent in game.get_agent_snapshot():
			assert(agent.has("online"))
			if not agent["online"]:
				continue
			snapshot.append(agent)
	last_agent_board_signature = (
		board
		. refresh_agent_board(
			agents_list_container,
			snapshot,
			{
				"logged_in": logged_in,
				"login_phase": login_phase,
				"game": game,
				"agent_activity_text": agent_activity_text,
				"last_signature": last_agent_board_signature,
				"on_trust": _on_agent_trust_pressed,
				"on_mute": _on_agent_mute_pressed,
				"on_patch": _on_agent_patch_pressed,
				"on_kill": _on_agent_kill_pressed,
				"on_add": _on_agent_add_pressed,
			}
		)
	)


func _resolve_review_for_ticket(ticket_id: String, approved: bool) -> void:
	assert(not ticket_id.is_empty())
	assert(game.run_state == Game.RunState.RUNNING)
	assert(game.review_tickets.has(ticket_id))
	assert(game.review_tickets[ticket_id]["status"] == Constants.REVIEW_STATUS_PENDING)
	var events: Array[Dictionary] = []
	var resolved: Dictionary = game.flow._resolve_review_ticket(
		game, ticket_id, approved, "human-reviewer", "HUMAN"
	)
	assert(not resolved.is_empty())
	events.append(resolved)
	if not approved:
		assert(game.tasks.has(resolved["task_id"]))
		var rejected_task: Dictionary = game.tasks[resolved["task_id"]]
		var replanned: Dictionary = game.flow._replan_for_canceled_task(
			game, rejected_task, "review_denied_manual"
		)
		if replanned["ok"]:
			var replacement: Dictionary = replanned["task"]
			(
				events
				. append(
					{
						"type": "task_replanned",
						"from_task_id": rejected_task["id"],
						"task_id": replacement["id"],
						"target": replacement["agent_id"],
					}
				)
			)
		else:
			(
				events
				. append(
					{
						"type": "replan_skipped",
						"task_id": rejected_task["id"],
						"reason": replanned["reason"],
					}
				)
			)
	_emit_events(events)


func _start_round_intro_sequence() -> void:
	assert(login_phase == LoginPhase.WAITING_LOGIN)
	assert(game.run_state == Game.RunState.BOOTING)
	var intro_logs: Array[Dictionary] = []
	intro_logs.append_array(console.build_boot_logs())
	var login_logs := console.finish_boot_and_build_login_logs(game)
	assert(not login_logs.is_empty())
	var delayed_boss_first_logs: Array[Dictionary] = []
	var delayed_colleague_logs: Array[Dictionary] = []
	var boss_first_delayed := false
	for item in login_logs:
		assert(item.has("event_key"))
		var event_key: String = item["event_key"]
		if event_key == "BOSS" and not boss_first_delayed:
			delayed_boss_first_logs.append(item)
			boss_first_delayed = true
			continue
		if (
			event_key in Constants.USER_KEYS_BY_ROUND
			or event_key == Constants.PREVIOUS_USER_KEY_DEFAULT
		):
			delayed_colleague_logs.append(item)
			continue
		intro_logs.append(item)
	feed.queue_mapped_logs(intro_logs)
	game.queue_delayed_mail_logs(delayed_boss_first_logs, Constants.BOSS_FIRST_MAIL_DELAY_SECONDS)
	game.queue_delayed_mail_logs(delayed_colleague_logs, Constants.COLLEAGUE_MAIL_DELAY_SECONDS)
	startup_sequence_pending = true


func _complete_round_intro_if_ready() -> void:
	if not startup_sequence_pending:
		return
	if not feed.is_idle():
		return
	assert(game.run_state == Game.RunState.BOOTING)
	game.finish_boot()
	startup_sequence_pending = false
	login_phase = LoginPhase.READY
	system_focus_text = _t("FOCUS_ROUND_STARTED")


func _on_review_slot_approve_pressed(ticket_id: String) -> void:
	assert(game.run_state == Game.RunState.RUNNING)
	assert(_has_pending_review_ticket(ticket_id))
	_resolve_review_for_ticket(ticket_id, true)


func _on_review_slot_deny_pressed(ticket_id: String) -> void:
	assert(game.run_state == Game.RunState.RUNNING)
	assert(_has_pending_review_ticket(ticket_id))
	_resolve_review_for_ticket(ticket_id, false)


func _has_pending_review_ticket(ticket_id: String) -> bool:
	for item in pending_review_items:
		if item["ticket_id"] == ticket_id:
			return true
	return false


func _on_agent_trust_pressed(agent_id: String) -> void:
	assert(game.run_state == Game.RunState.RUNNING)
	var trust_result := game.toggle_agent_flag(agent_id, "trusted")
	assert(trust_result["ok"])
	_emit_events([{"type": "trust_toggled", "target": trust_result["target"]}])


func _on_agent_mute_pressed(agent_id: String) -> void:
	assert(game.run_state == Game.RunState.RUNNING)
	var mute_result := game.toggle_agent_flag(agent_id, "muted")
	assert(mute_result["ok"])
	_emit_events([{"type": "mute_toggled", "target": mute_result["target"]}])


func _on_agent_kill_pressed(agent_id: String) -> void:
	assert(game.run_state == Game.RunState.RUNNING)
	var kill_result := game.kill_agent(agent_id)
	assert(kill_result["ok"])
	var events: Array[Dictionary] = []
	for event in kill_result["events"]:
		events.append(event)
	_emit_events(events)


func _on_agent_patch_pressed(agent_id: String) -> void:
	assert(game.run_state == Game.RunState.RUNNING)
	var patch_result := game.start_patch_for_agent(agent_id)
	assert(patch_result["ok"])
	assert(patch_result.has("duration_ticks"))
	var target_id: String = patch_result["target"]
	agent_activity_text[target_id] = _tf("ACTIVITY_PATCHING", [patch_result["duration_ticks"]])
	if patch_result["patched_incident_present"]:
		system_focus_text = _tf("FOCUS_PATCH_STARTED", [target_id, tr(patch_result["incident"])])
	else:
		system_focus_text = _tf("FOCUS_PATCH_PREVENTIVE", [target_id])
	_refresh_chrome()


func _on_agent_add_pressed(role: String) -> void:
	assert(game.run_state == Game.RunState.RUNNING)
	assert(role in Constants.AGENT_TYPES)
	var run_target := game.run_agent(role)
	assert(not run_target.is_empty())
	_emit_events([{"type": "agent_ran", "target": run_target}])


func _toggle_language() -> void:
	if TranslationServer.get_locale().begins_with("zh"):
		TranslationServer.set_locale("en")
	else:
		TranslationServer.set_locale("zh")
	_refresh_locale_ui()
	_refresh_chrome()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _input(event: InputEvent) -> void:
	var handled := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
			handled = true
		elif event.keycode == KEY_F1:
			_toggle_language()
			handled = true
		elif event.keycode == KEY_F2:
			_toggle_fullscreen()
			handled = true
	if handled:
		get_viewport().set_input_as_handled()


func _refresh_status_values() -> void:
	var snapshot := game.get_status_snapshot()
	_set_status_value("STABILITY", snapshot["stability"])
	_set_status_value("BUDGET", snapshot["budget"])
	_set_status_value("ENTROPY", snapshot["entropy"])
	_set_status_value("KPI", snapshot["kpi"])


func _set_status_value(key: String, value: float) -> void:
	assert(status_value_labels.has(key))
	var label: Label = status_value_labels[key]
	label.text = "%.1f/100" % value
