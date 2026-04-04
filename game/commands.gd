class_name Commands
extends RefCounted


func apply(game, command: String, target: String) -> Dictionary:
	var command_result: Dictionary = {
		"ok": true,
		"events": [],
	}

	match command:
		"agents":
			command_result.events.append(
				{"type": "agents_requested", "snapshot": game.get_agent_snapshot()}
			)
		"approve":
			var approve_result := _resolve_review(game, target, true)
			if approve_result.is_empty():
				command_result = _invalid_target_result(command, target)
			else:
				command_result.events.append(approve_result)
		"deny":
			var deny_result := _resolve_review(game, target, false)
			if deny_result.is_empty():
				command_result = _invalid_target_result(command, target)
			else:
				command_result.events.append(deny_result)
		"help":
			command_result.events.append({"type": "help_requested"})
		"incidents":
			command_result.events.append(
				{"type": "incidents_requested", "snapshot": game.get_incident_snapshot()}
			)
		"inspect":
			var inspected: Dictionary = game.inspect_target(target)
			if inspected.is_empty():
				command_result = _invalid_target_result(command, target)
			else:
				command_result.events.append(
					{"type": "inspect_requested", "target": target, "payload": inspected}
				)
		"kill":
			if not _kill_agent(game, target):
				command_result = _invalid_target_result(command, target)
			else:
				command_result.events.append({"type": "agent_killed", "target": target})
		"mute":
			if not _toggle_agent_flag(game, target, "muted"):
				command_result = _invalid_target_result(command, target)
			else:
				command_result.events.append({"type": "mute_toggled", "target": target})
		"patch":
			if not _clear_incident(game, target):
				command_result = _invalid_target_result(command, target)
			else:
				command_result.events.append({"type": "incident_cleared", "target": target})
		"run":
			var run_target := _run_agent(game, target)
			if run_target.is_empty():
				command_result = _invalid_target_result(command, target)
			else:
				command_result.events.append({"type": "agent_ran", "target": run_target})
		"status":
			command_result.events.append(
				{"type": "status_requested", "snapshot": game.get_status_snapshot()}
			)
		"trust":
			if not _toggle_agent_flag(game, target, "trusted"):
				command_result = _invalid_target_result(command, target)
			else:
				command_result.events.append({"type": "trust_toggled", "target": target})
		_:
			command_result = {
				"ok": false,
				"events": [{"type": "invalid_command", "command": command}],
			}

	return command_result


func _invalid_target_result(command: String, target: String) -> Dictionary:
	return {
		"ok": false,
		"events": [{"type": "invalid_target", "command": command, "target": target}],
	}


func _toggle_agent_flag(game, target: String, field: String) -> bool:
	for agent in game.agents:
		if agent.id == target or agent.type.to_lower() == target.to_lower():
			agent[field] = not agent[field]
			return true
	return false


func _kill_agent(game, target: String) -> bool:
	for agent in game.agents:
		if agent.id == target or agent.type.to_lower() == target.to_lower():
			agent.online = false
			agent.state = game.AgentState.OFFLINE
			agent.has_pending_review = false
			agent.pending_review_id = ""
			agent.pending_review = {}
			return true
	return false


func _run_agent(game, target_type: String) -> String:
	var normalized := target_type.strip_edges().to_upper()
	if normalized not in Constants.AGENT_TYPES:
		return ""
	if _online_agent_count(game) >= Constants.MAX_AGENTS:
		return ""
	var type_count := 0
	for agent in game.agents:
		if agent.type == normalized:
			type_count += 1
	var new_id := "%s-%d" % [normalized.to_lower(), type_count + 1]
	game.agents.append(game._make_agent(new_id, normalized))
	return new_id


func _online_agent_count(game) -> int:
	var total := 0
	for agent in game.agents:
		if agent.online:
			total += 1
	return total


func _clear_incident(game, target: String) -> bool:
	for index in range(game.active_incidents.size()):
		var incident: Dictionary = game.active_incidents[index]
		if incident.id == target or incident.type == target:
			if incident.type == "BUDGET_OPTIMIZATION":
				return false
			game.active_incidents.remove_at(index)
			return true
	return false


func _resolve_review(game, target: String, approved: bool) -> Dictionary:
	for agent in game.agents:
		if agent.id != target and agent.type.to_lower() != target.to_lower():
			continue
		if not agent.has_pending_review:
			return {}
		var review: Dictionary = agent.pending_review
		agent.has_pending_review = false
		agent.pending_review_id = ""
		agent.pending_review = {}
		game._apply_review_result(review, approved)
		game._apply_review_metrics(agent, review, approved)
		return {
			"type": "review_resolved",
			"target": agent.id,
			"approved": approved,
			"good": review.is_actually_good,
			"review": review,
		}
	return {}
