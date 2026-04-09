class_name Flow
extends RefCounted


func _create_task_for_agent(
	game, agent_id: String, intent: String, planned_by_agent_id: String
) -> Dictionary:
	assert(not game.goal.is_empty())
	assert(game.goal["status"] == Constants.GOAL_STATUS_ACTIVE)
	var owner_index := _find_agent_index_by_exact_id(game, agent_id)
	assert(owner_index >= 0)
	assert(game.agents[owner_index]["online"])
	assert(_find_agent_index_by_exact_id(game, planned_by_agent_id) >= 0)

	var owner: Dictionary = game.agents[owner_index]
	var role: String = owner["type"]
	var planned_with_planner := false
	if role == "GENERATOR":
		planned_with_planner = _has_online_planner(game)

	var task_id := "task-%d" % game.next_task_id
	game.next_task_id += 1
	var task := {
		"id": task_id,
		"goal_id": game.goal["id"],
		"agent_id": agent_id,
		"role": role,
		"intent": intent,
		"steps": Constants.WORKFLOW_STEPS.duplicate(),
		"current_step": 0,
		"status": Constants.TASK_STATUS_QUEUED,
		"cancel_reason": "",
		"tool_name": "",
		"review_ticket_id": "",
		"planned_by_agent_id": planned_by_agent_id,
		"planned_with_planner": planned_with_planner,
		"created_tick": game.elapsed_ticks,
		"step_remaining_ticks": _roll_step_duration_ticks(),
		"step_started": false,
	}
	game.tasks[task_id] = task
	owner["task_queue_ids"].append(task_id)
	game.agents[owner_index] = owner
	return task.duplicate(true)


func _cancel_task(game, task_id: String, reason: String) -> Dictionary:
	assert(game.tasks.has(task_id))
	assert(not reason.is_empty())
	var task: Dictionary = game.tasks[task_id]
	assert(task["status"] != Constants.TASK_STATUS_DONE)
	assert(task["status"] != Constants.TASK_STATUS_CANCELED)
	task["status"] = Constants.TASK_STATUS_CANCELED
	task["cancel_reason"] = reason
	game.tasks[task_id] = task
	_remove_task_from_queue(game, task["agent_id"], task_id)
	if task["review_ticket_id"] != "":
		_cancel_review_ticket(game, task["review_ticket_id"], reason)
	return task.duplicate(true)


func _cancel_tasks_for_agent(game, agent_id: String, reason: String) -> Array[Dictionary]:
	assert(_find_agent_index_by_exact_id(game, agent_id) >= 0)
	var canceled: Array[Dictionary] = []
	for task_id in game.tasks.keys():
		var task: Dictionary = game.tasks[task_id]
		if task["agent_id"] != agent_id:
			continue
		if _is_task_terminal(task["status"]):
			continue
		canceled.append(_cancel_task(game, task_id, reason))
	return canceled


func _replan_for_canceled_task(game, canceled_task: Dictionary, reason: String) -> Dictionary:
	assert(canceled_task.has("role"))
	assert(canceled_task.has("goal_id"))
	assert(not reason.is_empty())
	if game.goal.is_empty() or game.goal["status"] != Constants.GOAL_STATUS_ACTIVE:
		return {"ok": false, "reason": "goal_not_active"}
	if canceled_task["goal_id"] != game.goal["id"]:
		return {"ok": false, "reason": "goal_mismatch"}

	var replacement_agent_id := _first_online_agent_id_by_type(game, canceled_task["role"])
	if replacement_agent_id == "":
		return {"ok": false, "reason": "no_online_agent"}

	var planner_id := _planner_for_planning(game, replacement_agent_id)
	var replacement := _create_task_for_agent(
		game, replacement_agent_id, "replanned_after_cancel", planner_id
	)
	return {"ok": true, "task": replacement}


func _create_review_ticket(game, task_id: String, reviewer_agent_id: String) -> Dictionary:
	assert(game.tasks.has(task_id))
	var task: Dictionary = game.tasks[task_id]
	assert(task["status"] == Constants.TASK_STATUS_RUNNING)
	assert(task["steps"][task["current_step"]] == Constants.WORKFLOW_STEP_REVIEW_GATE)
	assert(task["review_ticket_id"] == "")

	var ticket_id := "review-%d" % game.next_review_id
	game.next_review_id += 1
	var ticket := {
		"id": ticket_id,
		"task_id": task_id,
		"requester_agent_id": task["agent_id"],
		"reviewer_agent_id": reviewer_agent_id,
		"status": Constants.REVIEW_STATUS_PENDING,
		"decision": "",
		"created_tick": game.elapsed_ticks,
	}
	game.review_tickets[ticket_id] = ticket
	task["review_ticket_id"] = ticket_id
	task["status"] = Constants.TASK_STATUS_WAITING_REVIEW
	game.tasks[task_id] = task
	_sync_pending_review_for_agent(game, task["agent_id"])
	return ticket.duplicate(true)


func _resolve_review_by_target(
	game, target: String, approved: bool, actor_agent_id: String, actor_type: String
) -> Dictionary:
	var index := _find_agent_index_by_target(game, target)
	if index < 0:
		return {}
	var agent: Dictionary = game.agents[index]
	if not agent["has_pending_review"]:
		return {}
	return _resolve_review_ticket(
		game, agent["pending_review_id"], approved, actor_agent_id, actor_type
	)


func _resolve_review_ticket(
	game, ticket_id: String, approved: bool, actor_agent_id: String, actor_type: String
) -> Dictionary:
	assert(game.review_tickets.has(ticket_id))
	var ticket: Dictionary = game.review_tickets[ticket_id]
	assert(ticket["status"] == Constants.REVIEW_STATUS_PENDING)
	assert(game.tasks.has(ticket["task_id"]))
	assert(ticket.has("content_quality"))
	assert(
		ticket["content_quality"] in [Constants.REVIEW_CONTENT_GOOD, Constants.REVIEW_CONTENT_BAD]
	)
	var content_quality: String = ticket["content_quality"]

	ticket["status"] = (
		Constants.REVIEW_STATUS_APPROVED if approved else Constants.REVIEW_STATUS_DENIED
	)
	ticket["decision"] = (
		Constants.REVIEW_DECISION_APPROVE if approved else Constants.REVIEW_DECISION_DENY
	)
	game.review_tickets[ticket_id] = ticket

	var task: Dictionary = game.tasks[ticket["task_id"]]
	assert(task["status"] == Constants.TASK_STATUS_WAITING_REVIEW)
	task["review_ticket_id"] = ""
	if approved:
		task["status"] = Constants.TASK_STATUS_APPROVED
		task["current_step"] += 1
		task["status"] = Constants.TASK_STATUS_RUNNING
		task["step_remaining_ticks"] = _roll_step_duration_ticks()
		task["step_started"] = false
	else:
		task["status"] = Constants.TASK_STATUS_REJECTED
		_remove_task_from_queue(game, task["agent_id"], task["id"])
	game.tasks[task["id"]] = task

	if approved and content_quality == Constants.REVIEW_CONTENT_GOOD:
		game.kpi += Constants.REVIEW_EFFECT_APPROVE_GOOD_KPI_DELTA
	elif approved and content_quality == Constants.REVIEW_CONTENT_BAD:
		game.stability = maxf(
			0.0, game.stability + Constants.REVIEW_EFFECT_APPROVE_BAD_STABILITY_DELTA
		)
	elif (not approved) and content_quality == Constants.REVIEW_CONTENT_BAD:
		game.stability = minf(
			100.0, game.stability + Constants.REVIEW_EFFECT_DENY_BAD_STABILITY_DELTA
		)
	else:
		assert((not approved) and content_quality == Constants.REVIEW_CONTENT_GOOD)
		game.entropy += Constants.REVIEW_EFFECT_DENY_GOOD_ENTROPY_DELTA

	_sync_pending_review_for_agent(game, task["agent_id"])

	return {
		"type": "review_resolved",
		"ticket_id": ticket_id,
		"task_id": task["id"],
		"target": task["agent_id"],
		"actor": actor_agent_id,
		"actor_type": actor_type,
		"approved": approved,
		"content_quality": content_quality,
	}


func _cancel_review_ticket(game, ticket_id: String, reason: String) -> void:
	assert(game.review_tickets.has(ticket_id))
	var ticket: Dictionary = game.review_tickets[ticket_id]
	if ticket["status"] != Constants.REVIEW_STATUS_PENDING:
		return
	ticket["status"] = Constants.REVIEW_STATUS_CANCELED
	ticket["decision"] = reason
	game.review_tickets[ticket_id] = ticket
	if game.tasks.has(ticket["task_id"]):
		var task: Dictionary = game.tasks[ticket["task_id"]]
		task["review_ticket_id"] = ""
		game.tasks[task["id"]] = task
	_sync_pending_review_for_agent(game, ticket["requester_agent_id"])


func _patch_target(game, target: String) -> Dictionary:
	var incident_index := _find_incident_index_by_target(game, target)
	if incident_index >= 0:
		var patched_incident := _patch_incident_at(game, incident_index)
		return {"ok": true, "incident": patched_incident}

	var agent_index := _find_agent_index_by_target(game, target)
	if agent_index < 0:
		return {"ok": false}
	var agent_id: String = game.agents[agent_index]["id"]

	for index in range(game.active_incidents.size()):
		var incident: Dictionary = game.active_incidents[index]
		if incident["agent_id"] != agent_id:
			continue
		if not incident["patchable"]:
			continue
		var patched := _patch_incident_at(game, index)
		return {"ok": true, "incident": patched}
	return {"ok": false}


func _complete_patch_for_agent(game, agent_id: String) -> Dictionary:
	var index := _find_agent_index_by_exact_id(game, agent_id)
	assert(index >= 0)
	var agent: Dictionary = game.agents[index]
	assert(agent["is_patching"])
	assert(agent["patch_ticks_remaining"] == 0)
	var incident_index := _patchable_incident_index_for_agent(game, agent_id)
	var patched := {}
	if incident_index >= 0:
		patched = _patch_incident_at(game, incident_index)
	agent["is_patching"] = false
	agent["patch_ticks_remaining"] = 0
	game.agents[index] = agent
	return patched


func _patch_incident_at(game, index: int) -> Dictionary:
	assert(index >= 0)
	assert(index < game.active_incidents.size())
	var incident: Dictionary = game.active_incidents[index]
	assert(incident["patchable"])
	game.active_incidents.remove_at(index)
	game.stability = minf(100.0, game.stability + Constants.INCIDENT_PATCH_RECOVER_STABILITY)
	return incident


func _create_incident(game, agent_id: String, incident_type: String) -> Dictionary:
	assert(_find_agent_index_by_exact_id(game, agent_id) >= 0)
	assert(incident_type in Constants.INCIDENT_TYPES)
	assert(game.active_incidents.size() < Constants.MAX_ACTIVE_INCIDENTS)

	var incident := {
		"id": "incident-%d" % game.next_incident_id,
		"type": incident_type,
		"agent_id": agent_id,
		"age_ticks": 0,
		"patchable": Constants.INCIDENT_TYPE_PATCHABLE[incident_type],
	}
	game.next_incident_id += 1
	game.active_incidents.append(incident)
	game.entropy += Constants.INCIDENT_CREATE_ENTROPY_GAIN
	game.stability = maxf(0.0, game.stability - Constants.INCIDENT_CREATE_STABILITY_DAMAGE)
	return incident.duplicate(true)


func _active_incident_for_agent(game, agent_id: String) -> String:
	assert(_find_agent_index_by_exact_id(game, agent_id) >= 0)
	for incident in game.active_incidents:
		if incident["agent_id"] == agent_id:
			return incident["type"]
	return ""


func _first_online_evaluator(game) -> String:
	for agent in game.agents:
		assert(agent.has("online"))
		assert(agent.has("type"))
		if agent["online"] and agent["type"] == "EVALUATOR":
			return agent["id"]
	return ""


func _has_online_planner(game) -> bool:
	for agent in game.agents:
		assert(agent.has("online"))
		assert(agent.has("type"))
		if agent["online"] and agent["type"] == "PLANNER":
			return true
	return false


func _planner_for_planning(game, owner_agent_id: String) -> String:
	assert(_find_agent_index_by_exact_id(game, owner_agent_id) >= 0)
	if _has_online_planner(game):
		var planner_id := _first_online_agent_id_by_type(game, "PLANNER")
		assert(not planner_id.is_empty())
		return planner_id
	return owner_agent_id


func _is_agent_muted(game, agent_id: String) -> bool:
	var index := _find_agent_index_by_exact_id(game, agent_id)
	assert(index >= 0)
	return game.agents[index]["muted"]


func _pending_review_count(game) -> int:
	var total := 0
	for agent in game.agents:
		assert(agent.has("has_pending_review"))
		if agent["has_pending_review"]:
			total += 1
	return total


func _roll_step_duration_ticks() -> int:
	assert(Constants.WORKFLOW_STEP_DURATION_MIN_TICKS >= 1)
	assert(Constants.WORKFLOW_STEP_DURATION_MAX_TICKS >= Constants.WORKFLOW_STEP_DURATION_MIN_TICKS)
	return randi_range(
		Constants.WORKFLOW_STEP_DURATION_MIN_TICKS, Constants.WORKFLOW_STEP_DURATION_MAX_TICKS
	)


func _find_agent_index_by_exact_id(game, target_id: String) -> int:
	assert(not target_id.is_empty())
	for index in range(game.agents.size()):
		if game.agents[index]["id"] == target_id:
			return index
	return -1


func _find_agent_index_by_target(game, target: String) -> int:
	assert(not target.is_empty())
	var exact := _find_agent_index_by_exact_id(game, target)
	if exact >= 0:
		return exact
	for index in range(game.agents.size()):
		if game.agents[index]["type"].to_lower() == target.to_lower():
			return index
	return -1


func _find_incident_index_by_target(game, target: String) -> int:
	assert(not target.is_empty())
	for index in range(game.active_incidents.size()):
		var incident: Dictionary = game.active_incidents[index]
		if incident["id"] == target or incident["type"] == target:
			return index
	return -1


func _remove_task_from_queue(game, agent_id: String, task_id: String) -> void:
	var index := _find_agent_index_by_exact_id(game, agent_id)
	assert(index >= 0)
	var agent: Dictionary = game.agents[index]
	assert(task_id in agent["task_queue_ids"])
	agent["task_queue_ids"].erase(task_id)
	game.agents[index] = agent


func _is_task_terminal(status: String) -> bool:
	assert(
		(
			status
			in [
				Constants.TASK_STATUS_DONE,
				Constants.TASK_STATUS_CANCELED,
				Constants.TASK_STATUS_REJECTED,
				Constants.TASK_STATUS_QUEUED,
				Constants.TASK_STATUS_RUNNING,
				Constants.TASK_STATUS_WAITING_REVIEW,
				Constants.TASK_STATUS_APPROVED,
			]
		)
	)
	return (
		status == Constants.TASK_STATUS_DONE
		or status == Constants.TASK_STATUS_CANCELED
		or status == Constants.TASK_STATUS_REJECTED
	)


func _sync_pending_review_for_agent(game, agent_id: String) -> void:
	var index := _find_agent_index_by_exact_id(game, agent_id)
	assert(index >= 0)
	var pending_ticket_id := ""
	for ticket_id in game.review_tickets.keys():
		var ticket: Dictionary = game.review_tickets[ticket_id]
		if ticket["requester_agent_id"] != agent_id:
			continue
		if ticket["status"] != Constants.REVIEW_STATUS_PENDING:
			continue
		pending_ticket_id = ticket_id
		break

	var agent: Dictionary = game.agents[index]
	if pending_ticket_id == "":
		agent["has_pending_review"] = false
		agent["pending_review_id"] = ""
		agent["pending_review"] = {}
		game.agents[index] = agent
		return

	agent["has_pending_review"] = true
	agent["pending_review_id"] = pending_ticket_id
	agent["pending_review"] = game.review_tickets[pending_ticket_id].duplicate(true)
	game.agents[index] = agent


func _queue_snapshot(game) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for agent in game.agents:
		var pending_ids: Array[String] = agent["task_queue_ids"]
		var statuses: Array[String] = []
		for task_id in pending_ids:
			assert(game.tasks.has(task_id))
			statuses.append(game.tasks[task_id]["status"])
		(
			rows
			. append(
				{
					"agent_id": agent["id"],
					"online": agent["online"],
					"queue_size": pending_ids.size(),
					"queue_statuses": statuses,
				}
			)
		)
	return rows


func _incident_ids_for_agent(game, agent_id: String) -> Array[String]:
	assert(_find_agent_index_by_exact_id(game, agent_id) >= 0)
	var ids: Array[String] = []
	for incident in game.active_incidents:
		if incident["agent_id"] == agent_id:
			ids.append(incident["id"])
	return ids


func _patchable_incident_index_for_agent(game, agent_id: String) -> int:
	assert(_find_agent_index_by_exact_id(game, agent_id) >= 0)
	for index in range(game.active_incidents.size()):
		var incident: Dictionary = game.active_incidents[index]
		if incident["agent_id"] != agent_id:
			continue
		if not incident["patchable"]:
			continue
		return index
	return -1


func _task_payloads_for_queue(game, task_ids: Array) -> Array[Dictionary]:
	var payload: Array[Dictionary] = []
	for raw_task_id in task_ids:
		assert(raw_task_id is String)
		var task_id: String = raw_task_id
		assert(game.tasks.has(task_id))
		payload.append(game.tasks[task_id].duplicate(true))
	return payload


func _first_online_agent_id_by_type(game, role: String) -> String:
	assert(role in Constants.AGENT_TYPES)
	for agent in game.agents:
		if agent["online"] and agent["type"] == role:
			return agent["id"]
	return ""
