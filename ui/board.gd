class_name Board
extends RefCounted


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


func _tf_random_variant(key_prefix: String, args: Array = []) -> String:
	var variant_keys: Array[String] = []
	for index in range(10):
		var candidate := "%s__%02d" % [key_prefix, index]
		if tr(candidate) == candidate:
			break
		variant_keys.append(candidate)
	if variant_keys.is_empty():
		return _tf(key_prefix, args)
	return _tf(variant_keys.pick_random(), args)


func refresh_review_slots(
	container: VBoxContainer,
	logged_in: bool,
	pending_items: Array[Dictionary],
	approve_cb: Callable,
	deny_cb: Callable
) -> void:
	assert(container != null)
	_clear_children(container)
	if not logged_in:
		return
	if pending_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = _t("REVIEWS_EMPTY")
		empty_label.add_theme_font_override("font", Ui.FONT_REGULAR)
		empty_label.add_theme_color_override("font_color", Ui.TEXT_DIM)
		empty_label.add_theme_font_size_override("font_size", Ui.scaled_font_size(13))
		container.add_child(empty_label)
		return
	for item in pending_items:
		container.add_child(_build_review_slot(item, approve_cb, deny_cb))


func refresh_task_slots(
	task_slots_container: VBoxContainer, logged_in: bool, tasks: Array[Dictionary]
) -> void:
	assert(task_slots_container != null)
	_clear_children(task_slots_container)
	if not logged_in:
		return
	if tasks.is_empty():
		var empty_label := Label.new()
		empty_label.text = _t("TASKS_EMPTY")
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_font_override("font", Ui.FONT_REGULAR)
		empty_label.add_theme_color_override("font_color", Ui.TEXT_DIM)
		empty_label.add_theme_font_size_override("font_size", Ui.scaled_font_size(13))
		task_slots_container.add_child(empty_label)
		return
	for index in range(tasks.size()):
		var task: Dictionary = tasks[index]
		assert(task.has("content"))
		assert(task.has("status"))
		task_slots_container.add_child(_build_task_slot(index + 1, task["content"], task["status"]))


func _build_task_slot(index: int, content_text: String, status: String) -> PanelContainer:
	assert(index >= 1)
	assert(not content_text.is_empty())
	var slot := PanelContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_theme_stylebox_override("panel", _task_slot_style(status))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	slot.add_child(margin)

	var line := Label.new()
	line.text = "%d. %s" % [index, content_text]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_override("font", Ui.FONT_REGULAR)
	line.add_theme_font_size_override("font_size", Ui.scaled_font_size(12))
	line.add_theme_color_override("font_color", Ui.TEXT)
	margin.add_child(line)

	return slot


func refresh_agent_board(
	container: Control, snapshot: Array[Dictionary], ctx: Dictionary
) -> String:
	assert(container != null)
	assert(ctx.has("logged_in"))
	assert(ctx.has("login_phase"))
	assert(ctx.has("game"))
	assert(ctx.has("agent_activity_text"))
	assert(ctx.has("last_signature"))
	assert(ctx.has("on_trust"))
	assert(ctx.has("on_mute"))
	assert(ctx.has("on_patch"))
	assert(ctx.has("on_kill"))
	assert(ctx.has("on_add"))
	var logged_in: bool = ctx["logged_in"]
	var login_phase: int = ctx["login_phase"]
	var game: Game = ctx["game"]
	var agent_activity_text: Dictionary = ctx["agent_activity_text"]
	var last_signature: String = ctx["last_signature"]
	var on_trust: Callable = ctx["on_trust"]
	var on_mute: Callable = ctx["on_mute"]
	var on_patch: Callable = ctx["on_patch"]
	var on_kill: Callable = ctx["on_kill"]
	var on_add: Callable = ctx["on_add"]
	var signature_parts: Array[String] = []
	for agent in snapshot:
		assert(agent.has("id"))
		assert(agent.has("type"))
		assert(agent.has("online"))
		assert(agent.has("state"))
		assert(agent.has("trusted"))
		assert(agent.has("muted"))
		assert(agent.has("has_pending_review"))
		assert(agent.has("is_patching"))
		assert(agent.has("patch_ticks_remaining"))
		assert(agent.has("task_queue_ids"))
		(
			signature_parts
			. append(
				(
					"%s|%s|%s|%s|%s|%s|%s|%s|%d|%d|%s"
					% [
						agent["id"],
						agent["type"],
						agent["online"],
						agent["state"],
						agent["trusted"],
						agent["muted"],
						agent["has_pending_review"],
						agent["is_patching"],
						agent["patch_ticks_remaining"],
						agent["task_queue_ids"].size(),
						_activity_text_for_agent(agent, game, agent_activity_text),
					]
				)
			)
		)

	var signature := "%s|%s|%s" % [logged_in, login_phase, ";".join(signature_parts)]
	if signature == last_signature:
		return last_signature

	_clear_children(container)
	for agent in snapshot:
		var card := _build_agent_card(
			agent, logged_in, game, agent_activity_text, on_trust, on_mute, on_patch, on_kill
		)
		container.add_child(card)
	if logged_in:
		container.add_child(_build_add_agent_card(logged_in, on_add))
	return signature


func _build_review_slot(
	item: Dictionary, approve_cb: Callable, deny_cb: Callable
) -> PanelContainer:
	assert(item.has("ticket_id"))
	assert(item.has("task_id"))
	assert(item.has("agent_id"))
	assert(item.has("step"))
	assert(item.has("content_quality"))
	var ticket_id: String = item["ticket_id"]
	var task_id: String = item["task_id"]
	var agent_id: String = item["agent_id"]
	var step: String = item["step"]
	var content_quality: String = item["content_quality"]
	assert(content_quality in [Constants.REVIEW_CONTENT_GOOD, Constants.REVIEW_CONTENT_BAD])
	var slot := PanelContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_theme_stylebox_override(
		"panel", _agent_card_style(Game.AgentState.WAITING_REVIEW, true)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	slot.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = agent_id
	title.add_theme_font_override("font", Ui.FONT_BOLD)
	title.add_theme_font_size_override("font_size", Ui.scaled_font_size(13))
	title.add_theme_color_override("font_color", Ui.TITLE)
	vbox.add_child(title)

	var detail := Label.new()
	var detail_key := "REVIEW_SLOT_DETAIL_GOOD"
	if content_quality == Constants.REVIEW_CONTENT_BAD:
		detail_key = "REVIEW_SLOT_DETAIL_BAD"
	detail.text = _tf_random_variant(detail_key, [task_id, tr(step), ticket_id])
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_override("font", Ui.FONT_REGULAR)
	detail.add_theme_font_size_override("font_size", Ui.scaled_font_size(12))
	detail.add_theme_color_override("font_color", Ui.TEXT_DIM)
	vbox.add_child(detail)

	var buttons := HBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("separation", 6)
	vbox.add_child(buttons)

	var approve_button := Button.new()
	approve_button.text = tr("APPROVE")
	approve_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	approve_button.custom_minimum_size = Vector2(0, 28)
	approve_button.add_theme_font_override("font", Ui.FONT_BOLD)
	approve_button.add_theme_font_size_override("font_size", Ui.scaled_font_size(12))
	buttons.add_child(approve_button)
	approve_button.pressed.connect(approve_cb.bind(ticket_id))

	var deny_button := Button.new()
	deny_button.text = tr("DENY")
	deny_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deny_button.custom_minimum_size = Vector2(0, 28)
	deny_button.add_theme_font_override("font", Ui.FONT_BOLD)
	deny_button.add_theme_font_size_override("font_size", Ui.scaled_font_size(12))
	buttons.add_child(deny_button)
	deny_button.pressed.connect(deny_cb.bind(ticket_id))
	return slot


func _build_agent_card(
	agent: Dictionary,
	logged_in: bool,
	game: Game,
	agent_activity_text: Dictionary,
	on_trust: Callable,
	on_mute: Callable,
	on_patch: Callable,
	on_kill: Callable
) -> PanelContainer:
	var agent_id: String = agent["id"]

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 84)
	card.add_theme_stylebox_override("panel", _agent_card_style(agent["state"], agent["online"]))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = "%s · %s" % [agent_id, tr(agent["type"])]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_override("font", Ui.FONT_BOLD)
	name_label.add_theme_font_size_override("font_size", Ui.scaled_font_size(14))
	name_label.add_theme_color_override("font_color", Ui.TITLE)
	header.add_child(name_label)

	var state_label := Label.new()
	state_label.text = _agent_state_text(agent["state"])
	state_label.add_theme_font_override("font", Ui.FONT_BOLD)
	state_label.add_theme_font_size_override("font_size", Ui.scaled_font_size(11))
	state_label.add_theme_color_override(
		"font_color", _agent_state_color(agent["state"], agent["online"])
	)
	header.add_child(state_label)

	var detail_label := Label.new()
	detail_label.text = _tf(
		"AGENT_CURRENT_ACTIVITY", [_activity_text_for_agent(agent, game, agent_activity_text)]
	)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_override("font", Ui.FONT_REGULAR)
	detail_label.add_theme_font_size_override("font_size", Ui.scaled_font_size(12))
	detail_label.add_theme_color_override("font_color", Ui.TEXT_DIM)
	vbox.add_child(detail_label)

	var action_row := HBoxContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_theme_constant_override("separation", 6)
	vbox.add_child(action_row)

	var trust_button := Button.new()
	trust_button.text = tr("DISTRUST") if agent["trusted"] else tr("TRUST")
	trust_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trust_button.custom_minimum_size = Vector2(0, 26)
	trust_button.disabled = not logged_in
	trust_button.add_theme_font_override("font", Ui.FONT_BOLD)
	trust_button.add_theme_font_size_override("font_size", Ui.scaled_font_size(11))
	action_row.add_child(trust_button)
	trust_button.pressed.connect(on_trust.bind(agent_id))

	var mute_button := Button.new()
	mute_button.text = tr("UNMUTE") if agent["muted"] else tr("MUTE")
	mute_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mute_button.custom_minimum_size = Vector2(0, 26)
	mute_button.disabled = not logged_in
	mute_button.add_theme_font_override("font", Ui.FONT_BOLD)
	mute_button.add_theme_font_size_override("font_size", Ui.scaled_font_size(11))
	action_row.add_child(mute_button)
	mute_button.pressed.connect(on_mute.bind(agent_id))

	var patch_button := Button.new()
	patch_button.text = tr("PATCH")
	patch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	patch_button.custom_minimum_size = Vector2(0, 26)
	patch_button.disabled = (not logged_in or not agent["online"] or agent["is_patching"])
	patch_button.add_theme_font_override("font", Ui.FONT_BOLD)
	patch_button.add_theme_font_size_override("font_size", Ui.scaled_font_size(11))
	action_row.add_child(patch_button)
	patch_button.pressed.connect(on_patch.bind(agent_id))

	var power_button := Button.new()
	power_button.text = tr("KILL")
	power_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	power_button.custom_minimum_size = Vector2(0, 26)
	power_button.disabled = not logged_in
	power_button.add_theme_font_override("font", Ui.FONT_BOLD)
	power_button.add_theme_font_size_override("font_size", Ui.scaled_font_size(11))
	action_row.add_child(power_button)
	power_button.pressed.connect(on_kill.bind(agent_id))

	return card


func _build_add_agent_card(logged_in: bool, on_add: Callable) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 84)
	card.add_theme_stylebox_override("panel", _agent_card_style(Game.AgentState.OK, true))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title_label := Label.new()
	title_label.text = _t("ADD_AGENT")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", Ui.FONT_BOLD)
	title_label.add_theme_font_size_override("font_size", Ui.scaled_font_size(13))
	title_label.add_theme_color_override("font_color", Ui.TITLE)
	vbox.add_child(title_label)

	var hint_label := Label.new()
	hint_label.text = _t("ADD_AGENT_HINT")
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_override("font", Ui.FONT_REGULAR)
	hint_label.add_theme_font_size_override("font_size", Ui.scaled_font_size(11))
	hint_label.add_theme_color_override("font_color", Ui.TEXT_DIM)
	vbox.add_child(hint_label)

	var button_row := HBoxContainer.new()
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_theme_constant_override("separation", 4)
	vbox.add_child(button_row)

	for role in Constants.AGENT_TYPES:
		var role_button := Button.new()
		role_button.text = tr(role)
		role_button.tooltip_text = tr(role)
		role_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		role_button.custom_minimum_size = Vector2(0, 26)
		role_button.disabled = not logged_in
		role_button.add_theme_font_override("font", Ui.FONT_BOLD)
		role_button.add_theme_font_size_override("font_size", Ui.scaled_font_size(11))
		role_button.pressed.connect(on_add.bind(role))
		button_row.add_child(role_button)

	return card


func _activity_text_for_agent(
	agent: Dictionary, game: Game, agent_activity_text: Dictionary
) -> String:
	var agent_id: String = agent["id"]
	var text := ""
	if not agent["online"]:
		text = _t("ACTIVITY_AGENT_OFFLINE")
	elif agent["is_patching"]:
		text = _tf("ACTIVITY_PATCHING", [agent["patch_ticks_remaining"]])
	elif agent_activity_text.has(agent_id):
		text = agent_activity_text[agent_id]
	elif agent["has_pending_review"]:
		text = _t("ACTIVITY_REVIEW_REQUESTED")
	elif agent["task_queue_ids"].is_empty():
		text = _t("ACTIVITY_IDLE")
	else:
		var task_id: String = agent["task_queue_ids"][0]
		assert(game.tasks.has(task_id))
		var task: Dictionary = game.tasks[task_id]
		assert(task.has("status"))
		if task["status"] == Constants.TASK_STATUS_RUNNING:
			assert(task.has("current_step"))
			assert(task.has("steps"))
			assert(task["current_step"] >= 0)
			assert(task["current_step"] < task["steps"].size())
			text = _tf("ACTIVITY_DOING_STEP", [tr(task["steps"][task["current_step"]])])
		elif task["status"] == Constants.TASK_STATUS_WAITING_REVIEW:
			text = _t("ACTIVITY_REVIEW_REQUESTED")
		elif task["status"] == Constants.TASK_STATUS_QUEUED:
			text = _t("ACTIVITY_QUEUED")
		else:
			text = _task_status_text(task["status"])
	return text


func _agent_state_text(state: int) -> String:
	match state:
		Game.AgentState.OK:
			return _t("AGENT_STATE_OK")
		Game.AgentState.DRIFTING:
			return _t("AGENT_STATE_DRIFTING")
		Game.AgentState.UNSTABLE:
			return _t("AGENT_STATE_UNSTABLE")
		Game.AgentState.WAITING_REVIEW:
			return _t("AGENT_STATE_WAITING_REVIEW")
		Game.AgentState.OFFLINE:
			return _t("AGENT_STATE_OFFLINE")
		_:
			assert(false, "Unknown agent state")
	return ""


func _task_status_text(status: String) -> String:
	var key := "TASK_STATUS_%s" % status
	return _t(key)


func _agent_state_color(state: int, online: bool) -> Color:
	var color := Ui.COLOR_GRAY
	if not online:
		color = Ui.COLOR_GRAY
	else:
		match state:
			Game.AgentState.OK:
				color = Ui.COLOR_GREEN
			Game.AgentState.DRIFTING:
				color = Ui.COLOR_YELLOW
			Game.AgentState.UNSTABLE:
				color = Ui.COLOR_RED
			Game.AgentState.WAITING_REVIEW:
				color = Ui.COLOR_BLUE
			Game.AgentState.OFFLINE:
				color = Ui.COLOR_GRAY
			_:
				assert(false, "Unknown agent state")
	return color


func _task_status_color(status: String) -> Color:
	match status:
		"DONE":
			return Ui.COLOR_GREEN
		"ACTIVE":
			return Ui.COLOR_GREEN
		"WAITING":
			return Ui.COLOR_BLUE
		"FAILED":
			return Ui.COLOR_RED
		_:
			assert(false, "Unknown task status")
	return Ui.TEXT


func _task_slot_style(status: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Ui.PANEL_DARK
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = _task_status_color(status)
	return style


func _agent_card_style(state: int, online: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Ui.PANEL_DARK
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = _agent_state_color(state, online)
	return style


func _clear_children(container: Control) -> void:
	assert(container != null)
	for child in container.get_children():
		child.queue_free()
