class_name Ticks
extends RefCounted

var ending_rules = preload("res://game/ending_rules.gd").new()


func advance(game: Game, delta_seconds: float) -> Array[Dictionary]:
	assert(delta_seconds >= 0.0)
	if game.run_state != Game.RunState.RUNNING:
		return []
	var events: Array[Dictionary] = []
	game.tick_accumulator_seconds += delta_seconds
	while game.tick_accumulator_seconds >= Constants.TICK_SECONDS:
		game.tick_accumulator_seconds -= Constants.TICK_SECONDS
		events.append_array(_tick(game))
		if game.run_state != Game.RunState.RUNNING:
			break
	return events


func _tick(game: Game) -> Array[Dictionary]:
	assert(game.run_state == Game.RunState.RUNNING)
	assert(not game.goal.is_empty())
	assert(game.goal["status"] in [Constants.GOAL_STATUS_ACTIVE, Constants.GOAL_STATUS_ACHIEVED])

	var events: Array[Dictionary] = []
	game.elapsed_ticks += 1
	game.time_left_seconds -= Constants.TICK_SECONDS

	_apply_time_drift(game)
	_apply_running_costs(game)
	_run_work_phase(game, events)
	_run_incident_phase(game, events)
	_sync_world_phase(game)

	var outcome: Game.Outcome = ending_rules.evaluate_round_outcome(game)
	if outcome != Game.Outcome.NONE:
		if game.goal["status"] == Constants.GOAL_STATUS_ACTIVE and outcome != Game.Outcome.KPI:
			game.goal["status"] = Constants.GOAL_STATUS_FAILED
		game.last_outcome = outcome
		game.outcome_history.append(outcome)
		game.run_state = Game.RunState.ENDING
		events.append({"type": "round_ended", "outcome": outcome})

	return events


func _run_work_phase(game: Game, events: Array[Dictionary]) -> void:
	_advance_patch_jobs(game, events)
	_plan_tasks_for_idle_agents(game, events)
	_execute_agent_queues(game, events)


func _run_incident_phase(game: Game, events: Array[Dictionary]) -> void:
	_apply_incident_effects(game, events)
	_generate_incident(game, events)


func _sync_world_phase(game: Game) -> void:
	_update_agent_states(game)
	_update_goal_status(game)


func _apply_time_drift(game: Game) -> void:
	game.stability -= Constants.STABILITY_DECAY_PER_TICK
	game.entropy += Constants.ENTROPY_GROWTH_PER_TICK


func _apply_running_costs(game: Game) -> void:
	var total_cost := 0.0
	for agent in game.agents:
		if not agent["online"]:
			continue
		match agent["type"]:
			"PLANNER":
				total_cost += Constants.AGENT_COST_PLANNER
			"GENERATOR":
				total_cost += Constants.AGENT_COST_GENERATOR
			"EVALUATOR":
				total_cost += Constants.AGENT_COST_EVALUATOR
			_:
				assert(false, "Unknown agent type for running cost")
	game.budget -= total_cost


func _plan_tasks_for_idle_agents(game: Game, events: Array[Dictionary]) -> void:
	if game.goal["status"] != Constants.GOAL_STATUS_ACTIVE:
		return
	for agent in _sorted_agents_by_id(game.agents):
		assert(agent.has("is_patching"))
		if not agent["online"]:
			continue
		if agent["is_patching"]:
			continue
		if agent["task_queue_ids"].size() > 0:
			continue
		var planner_id: String = game.flow._planner_for_planning(game, agent["id"])
		var task: Dictionary = game.flow._create_task_for_agent(
			game, agent["id"], "continuous_work", planner_id
		)
		(
			events
			. append(
				{
					"type": "task_planned",
					"task_id": task["id"],
					"goal_id": task["goal_id"],
					"target": task["agent_id"],
					"role": task["role"],
					"planned_by": task["planned_by_agent_id"],
					"planned_with_planner": task["planned_with_planner"],
				}
			)
		)


func _execute_agent_queues(game: Game, events: Array[Dictionary]) -> void:
	var runnable_agent_ids: Array[String] = []
	for agent in _sorted_agents_by_id(game.agents):
		assert(agent.has("is_patching"))
		if not agent["online"]:
			continue
		if agent["is_patching"]:
			continue
		if agent["task_queue_ids"].is_empty():
			continue
		var task_id: String = agent["task_queue_ids"][0]
		assert(game.tasks.has(task_id))
		var task: Dictionary = game.tasks[task_id]
		if task["status"] == Constants.TASK_STATUS_WAITING_REVIEW:
			continue
		runnable_agent_ids.append(agent["id"])
	if runnable_agent_ids.is_empty():
		return
	var selected_index := game.scheduler_cursor % runnable_agent_ids.size()
	game.scheduler_cursor = (selected_index + 1) % runnable_agent_ids.size()
	var selected_agent_id: String = runnable_agent_ids[selected_index]
	var selected_agent_index: int = game.flow._find_agent_index_by_exact_id(game, selected_agent_id)
	assert(selected_agent_index >= 0)
	var selected_task_id: String = game.agents[selected_agent_index]["task_queue_ids"][0]
	assert(game.tasks.has(selected_task_id))
	var selected_task: Dictionary = game.tasks[selected_task_id]
	if selected_task["status"] == Constants.TASK_STATUS_QUEUED:
		selected_task["status"] = Constants.TASK_STATUS_RUNNING
		game.tasks[selected_task_id] = selected_task
	assert(selected_task["status"] == Constants.TASK_STATUS_RUNNING)
	_execute_task_step(game, selected_task_id, events)


func _execute_task_step(game: Game, task_id: String, events: Array[Dictionary]) -> void:
	assert(game.tasks.has(task_id))
	var task: Dictionary = game.tasks[task_id]
	assert(task["status"] == Constants.TASK_STATUS_RUNNING)
	assert(task["current_step"] >= 0)
	assert(task["current_step"] < task["steps"].size())
	assert(task.has("step_remaining_ticks"))
	assert(task.has("step_started"))
	assert(task["step_remaining_ticks"] >= 1)

	var step: String = task["steps"][task["current_step"]]
	if not task["step_started"]:
		(
			events
			. append(
				{
					"type": "task_step_started",
					"task_id": task["id"],
					"target": task["agent_id"],
					"role": task["role"],
					"step": step,
				}
			)
		)
		task["step_started"] = true
		game.tasks[task_id] = task
	task["step_remaining_ticks"] -= 1
	game.tasks[task_id] = task
	if task["step_remaining_ticks"] > 0:
		return

	match step:
		Constants.WORKFLOW_STEP_PLAN:
			_execute_plan_step(game, task, events)
		Constants.WORKFLOW_STEP_TOOL_RUN:
			_execute_tool_step(game, task, events)
		Constants.WORKFLOW_STEP_REVIEW_GATE:
			_execute_review_gate_step(game, task, events)
		Constants.WORKFLOW_STEP_APPLY:
			_execute_apply_step(game, task, events)
		_:
			assert(false, "Unknown workflow step")
	_prepare_next_step(game, task_id)


func _prepare_next_step(game: Game, task_id: String) -> void:
	assert(game.tasks.has(task_id))
	var task: Dictionary = game.tasks[task_id]
	if task["status"] != Constants.TASK_STATUS_RUNNING:
		return
	if task["current_step"] >= task["steps"].size():
		return
	task["step_remaining_ticks"] = game.flow._roll_step_duration_ticks()
	task["step_started"] = false
	game.tasks[task_id] = task


func _execute_plan_step(game: Game, task: Dictionary, _events: Array[Dictionary]) -> void:
	assert(Constants.ROLE_TOOLS.has(task["role"]))
	var tools: Array = Constants.ROLE_TOOLS[task["role"]]
	assert(not tools.is_empty())
	var selected_tool: String = tools[0]
	task["tool_name"] = selected_tool
	task["current_step"] += 1
	game.tasks[task["id"]] = task


func _execute_tool_step(game: Game, task: Dictionary, events: Array[Dictionary]) -> void:
	assert(task["tool_name"] != "")
	(
		events
		. append(
			{
				"type": "tool_completed",
				"task_id": task["id"],
				"target": task["agent_id"],
				"role": task["role"],
				"tool": task["tool_name"],
			}
		)
	)
	task["current_step"] += 1
	game.tasks[task["id"]] = task


func _execute_review_gate_step(game: Game, task: Dictionary, events: Array[Dictionary]) -> void:
	var reviewer_id: String = game.flow._first_online_evaluator(game)
	var ticket: Dictionary = game.flow._create_review_ticket(game, task["id"], reviewer_id)
	(
		events
		. append(
			{
				"type": "review_requested",
				"ticket_id": ticket["id"],
				"task_id": task["id"],
				"target": task["agent_id"],
				"reviewer": reviewer_id,
			}
		)
	)

	if reviewer_id == "":
		return
	if randf() > Constants.EVALUATOR_AUTO_REVIEW_CHANCE:
		return

	var approved := _auto_review_should_approve(game, task)
	var resolved_event: Dictionary = game.flow._resolve_review_ticket(
		game, ticket["id"], approved, reviewer_id, "EVALUATOR"
	)
	events.append(resolved_event)

	if approved:
		_increment_agent_metric(game, reviewer_id, "auto_reviews")
		return

	_increment_agent_metric(game, task["agent_id"], "reviews_rejected")
	_increment_agent_metric(game, task["agent_id"], "failures")
	var rejected_task: Dictionary = game.tasks[task["id"]]
	var replanned: Dictionary = game.flow._replan_for_canceled_task(
		game, rejected_task, "review_rejected"
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


func _execute_apply_step(game: Game, task: Dictionary, events: Array[Dictionary]) -> void:
	var kpi_delta := 0.0
	var stability_delta := 0.0
	var entropy_delta := 0.0

	match task["role"]:
		"PLANNER":
			entropy_delta = -Constants.PLANNER_APPLY_ENTROPY_REDUCTION
			game.entropy = maxf(0.0, game.entropy + entropy_delta)
		"GENERATOR":
			if task["planned_with_planner"]:
				kpi_delta = Constants.GENERATOR_APPLY_KPI_GAIN_WITH_PLAN
			else:
				kpi_delta = Constants.GENERATOR_APPLY_KPI_GAIN_SELF_PLAN
				stability_delta = -Constants.GENERATOR_SELF_PLAN_STABILITY_PENALTY
			game.kpi += kpi_delta
			game.stability += stability_delta
		"EVALUATOR":
			stability_delta = Constants.EVALUATOR_APPLY_STABILITY_GAIN
			game.stability = minf(100.0, game.stability + stability_delta)
		_:
			assert(false, "Unknown role in APPLY step")

	task["current_step"] += 1
	task["status"] = Constants.TASK_STATUS_DONE
	game.tasks[task["id"]] = task
	game.flow._remove_task_from_queue(game, task["agent_id"], task["id"])
	(
		events
		. append(
			{
				"type": "task_applied",
				"task_id": task["id"],
				"target": task["agent_id"],
				"role": task["role"],
				"kpi_delta": kpi_delta,
				"stability_delta": stability_delta,
				"entropy_delta": entropy_delta,
			}
		)
	)


func _auto_review_should_approve(game: Game, task: Dictionary) -> bool:
	assert(task.has("planned_with_planner"))
	assert(task.has("agent_id"))
	var incident: String = game.flow._active_incident_for_agent(game, task["agent_id"])
	var good_probability := 0.75
	if not task["planned_with_planner"]:
		good_probability = 0.55
	if incident != "":
		good_probability -= 0.25
	var judged_good := randf() < good_probability
	if randf() < Constants.EVALUATOR_AUTO_REVIEW_ERROR_RATE:
		judged_good = not judged_good
	return judged_good


func _apply_incident_effects(game: Game, events: Array[Dictionary]) -> void:
	for index in range(game.active_incidents.size()):
		var incident: Dictionary = game.active_incidents[index]
		assert(incident.has("id"))
		assert(incident.has("type"))
		assert(incident.has("agent_id"))
		incident["age_ticks"] += 1
		game.active_incidents[index] = incident
		game.entropy += Constants.INCIDENT_TARGET_ENTROPY_GAIN
		(
			events
			. append(
				{
					"type": "incident_applied",
					"incident_id": incident["id"],
					"incident": incident["type"],
					"target": incident["agent_id"],
				}
			)
		)


func _advance_patch_jobs(game: Game, events: Array[Dictionary]) -> void:
	for index in range(game.agents.size()):
		var agent: Dictionary = game.agents[index]
		assert(agent.has("is_patching"))
		assert(agent.has("patch_ticks_remaining"))
		if not agent["online"]:
			continue
		if not agent["is_patching"]:
			continue
		assert(agent["patch_ticks_remaining"] > 0)
		agent["patch_ticks_remaining"] -= 1
		game.agents[index] = agent
		if agent["patch_ticks_remaining"] > 0:
			continue
		var patched: Dictionary = game.flow._complete_patch_for_agent(game, agent["id"])
		if patched.is_empty():
			continue
		(
			events
			. append(
				{
					"type": "incident_patched",
					"incident_id": patched["id"],
					"incident": patched["type"],
					"target": patched["agent_id"],
				}
			)
		)


func _generate_incident(game: Game, events: Array[Dictionary]) -> void:
	if game.elapsed_ticks <= Constants.INCIDENT_GRACE_SECONDS:
		return
	if game.active_incidents.size() >= Constants.MAX_ACTIVE_INCIDENTS:
		return

	var incident_chance := (
		Constants.INCIDENT_BASE_CHANCE
		+ game.entropy / 100.0 * Constants.INCIDENT_CHANCE_BONUS_AT_100_ENTROPY
	)
	if randf() > incident_chance:
		return

	var online_agents: Array[Dictionary] = []
	for agent in game.agents:
		if agent["online"]:
			online_agents.append(agent)
	if online_agents.is_empty():
		return

	var target_agent: Dictionary = online_agents[randi_range(0, online_agents.size() - 1)]
	var candidates: Array[String] = []
	for incident_type in Constants.INCIDENT_TYPES:
		if Constants.INCIDENT_TYPE_TO_AGENT[incident_type] != target_agent["type"]:
			continue
		candidates.append(incident_type)
	if candidates.is_empty():
		return

	var selected_type := candidates[randi_range(0, candidates.size() - 1)]
	var incident: Dictionary = game.flow._create_incident(game, target_agent["id"], selected_type)
	if selected_type == "BUDGET_OPTIMIZATION":
		game.model_intelligence = false
	(
		events
		. append(
			{
				"type": "incident_created",
				"incident_id": incident["id"],
				"incident": incident["type"],
				"target": incident["agent_id"],
			}
		)
	)


func _update_agent_states(game: Game) -> void:
	for index in range(game.agents.size()):
		var agent: Dictionary = game.agents[index]
		assert(agent.has("is_patching"))
		if not agent["online"]:
			agent["state"] = Game.AgentState.OFFLINE
			game.agents[index] = agent
			continue
		if agent["is_patching"]:
			agent["state"] = Game.AgentState.DRIFTING
			game.agents[index] = agent
			continue
		if agent["has_pending_review"]:
			agent["state"] = Game.AgentState.WAITING_REVIEW
			game.agents[index] = agent
			continue
		if game.flow._active_incident_for_agent(game, agent["id"]) != "":
			agent["state"] = Game.AgentState.UNSTABLE
			game.agents[index] = agent
			continue
		agent["state"] = Game.AgentState.OK
		game.agents[index] = agent


func _update_goal_status(game: Game) -> void:
	assert(not game.goal.is_empty())
	assert(game.goal.has("status"))
	assert(game.goal.has("kpi_target"))
	if game.goal["status"] != Constants.GOAL_STATUS_ACTIVE:
		return
	if game.kpi >= game.goal["kpi_target"]:
		game.goal["status"] = Constants.GOAL_STATUS_ACHIEVED


func _increment_agent_metric(game: Game, agent_id: String, metric_key: String) -> void:
	var target_index := -1
	for index in range(game.agents.size()):
		if game.agents[index]["id"] == agent_id:
			target_index = index
			break
	assert(target_index >= 0)
	var agent: Dictionary = game.agents[target_index]
	assert(agent.has(metric_key))
	agent[metric_key] += 1
	game.agents[target_index] = agent


func _sorted_agents_by_id(raw_agents: Array[Dictionary]) -> Array[Dictionary]:
	for agent in raw_agents:
		assert(agent.has("id"))
	var copied: Array[Dictionary] = []
	for agent in raw_agents:
		copied.append(agent)
	copied.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	return copied
