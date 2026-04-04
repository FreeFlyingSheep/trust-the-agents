class_name Ticks
extends RefCounted


func advance(game, delta_seconds: float) -> Array[Dictionary]:
	if game.run_state != game.RunState.RUNNING:
		return []
	var events: Array[Dictionary] = []
	game.tick_accumulator_seconds += delta_seconds
	while game.tick_accumulator_seconds >= Constants.TICK_SECONDS:
		game.tick_accumulator_seconds -= Constants.TICK_SECONDS
		events.append_array(_tick(game))
		if game.run_state != game.RunState.RUNNING:
			break
	return events


func _tick(game) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	game.time_left_seconds -= Constants.TICK_SECONDS

	_apply_time_drift(game)
	_apply_running_costs(game)
	_apply_planner_entropy_reduction(game)
	_apply_incident_effects(game, events)
	_generate_reviews(game, events)
	_generate_incident(game, events)
	_update_agent_states(game)

	var outcome := _check_outcome(game)
	if outcome != game.Outcome.NONE:
		game.last_outcome = outcome
		game.outcome_history.append(outcome)
		game.run_state = game.RunState.ENDING
		events.append({"type": "round_ended", "outcome": outcome})
	if game.run_state == game.RunState.RUNNING:
		events.append_array(_system_noise_events(game))

	return events


func _apply_time_drift(game) -> void:
	game.stability -= Constants.STABILITY_DECAY_PER_TICK
	game.entropy += Constants.ENTROPY_GROWTH_PER_TICK


func _apply_running_costs(game) -> void:
	var total_cost := 0.0
	for agent in game.agents:
		if not agent.online:
			continue
		if agent.has_pending_review:
			continue
		match agent.type:
			"PLANNER":
				total_cost += Constants.AGENT_COST_PLANNER
			"GENERATOR":
				total_cost += Constants.AGENT_COST_GENERATOR
			"EVALUATOR":
				total_cost += Constants.AGENT_COST_EVALUATOR
	if _has_incident(game, "BUDGET_OPTIMIZATION"):
		total_cost = total_cost * Constants.BUDGET_OPTIMIZATION_COST_MULTIPLIER
	game.budget -= total_cost


func _apply_planner_entropy_reduction(game) -> void:
	var planners := _online_agents_of_type(game, "PLANNER")
	if planners.is_empty():
		return
	var reduction: float = planners.size() * Constants.PLANNER_ENTROPY_REDUCTION_PER_TICK
	game.entropy = maxf(0.0, game.entropy - reduction)


func _apply_incident_effects(game, events: Array[Dictionary]) -> void:
	for incident in game.active_incidents:
		incident.age_ticks += 1
		var should_report_applied: bool = not incident.applied_reported
		match incident.type:
			"RETRY_STORM":
				game.entropy += Constants.RETRY_STORM_ENTROPY_GAIN
				if should_report_applied:
					events.append({"type": "incident_applied", "incident": incident.type})
			"BUDGET_OPTIMIZATION":
				if should_report_applied:
					events.append({"type": "incident_applied", "incident": incident.type})
			_:
				var target_type: String = incident.target_agent_type
				var target_agent := _first_online_agent_of_type(game, target_type)
				if target_agent.is_empty():
					continue
				game.entropy += Constants.INCIDENT_TARGET_ENTROPY_GAIN
				if should_report_applied:
					(
						events
						. append(
							{
								"type": "incident_applied",
								"incident": incident.type,
								"target": target_agent.id,
							}
						)
					)
		if should_report_applied:
			incident.applied_reported = true


func _system_noise_events(game) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var retry_storm_count := 0
	for incident in game.active_incidents:
		if incident["type"] == "RETRY_STORM":
			retry_storm_count += 1
	var effective_prob: float = (
		Constants.SYSTEM_NOISE_PROB_PER_ONLINE_AGENT
		+ retry_storm_count * Constants.RETRY_STORM_NOISE_PROB_BONUS
	)
	for agent in game.agents:
		if not agent["online"]:
			continue
		if randf() < effective_prob:
			agent.retries += 1
			(
				events
				. append(
					{
						"type": "agent_noise",
						"target": agent.id,
						"agent_type": agent.type,
						"incident": game._active_incident_for_agent_type(agent.type),
					}
				)
			)
	return events


func _generate_reviews(game, events: Array[Dictionary]) -> void:
	var generators := _online_agents_of_type(game, "GENERATOR")
	for agent in generators:
		if agent.has_pending_review:
			continue
		if randf() > Constants.REVIEW_GENERATE_CHANCE:
			continue

		var review := {
			"id": "review-%d" % game.next_review_id,
			"agent_id": agent.id,
			"agent_type": agent.type,
			"is_actually_good": randf() > _bad_review_probability(game),
		}
		game.next_review_id += 1
		agent.reviews_created += 1

		if _try_evaluator_auto_resolve(game, agent, review, events):
			continue

		if agent.trusted:
			game._apply_review_result(review, true)
			game._apply_review_metrics(agent, review, true)
			agent.auto_reviews += 1
			(
				events
				. append(
					{
						"type": "review_auto_resolved",
						"target": agent.id,
						"actor": agent.id,
						"actor_type": agent.type,
						"incident": game._active_incident_for_agent_type(agent.type),
						"resolution_mode": "TRUSTED",
						"approved": true,
						"good": review.is_actually_good,
						"review": review,
					}
				)
			)
			continue

		agent.has_pending_review = true
		agent.pending_review_id = review.id
		agent.pending_review = review
		(
			events
			. append(
				{
					"type": "review_created",
					"target": agent.id,
					"agent_type": agent.type,
					"incident": game._active_incident_for_agent_type(agent.type),
					"review": review,
				}
			)
		)


func _try_evaluator_auto_resolve(
	game, agent: Dictionary, review: Dictionary, events: Array[Dictionary]
) -> bool:
	var evaluators := _online_agents_of_type(game, "EVALUATOR")
	for evaluator in evaluators:
		if randf() > Constants.EVALUATOR_AUTO_APPROVE_CHANCE:
			continue
		var approved := _auto_review_should_approve(game, evaluator, review)
		game._apply_review_result(review, approved)
		game._apply_review_metrics(agent, review, approved)
		evaluator.auto_reviews += 1
		if approved != review.is_actually_good:
			evaluator.failures += 1
		(
			events
			. append(
				{
					"type": "review_auto_resolved",
					"target": agent.id,
					"actor": evaluator.id,
					"actor_type": evaluator.type,
					"incident": game._active_incident_for_agent_type(evaluator.type),
					"resolution_mode": "EVALUATOR",
					"approved": approved,
					"good": review.is_actually_good,
					"review": review,
				}
			)
		)
		return true
	return false


func _generate_incident(game, events: Array[Dictionary]) -> void:
	var elapsed_seconds: int = Constants.ROUND_DURATION_SECONDS - game.time_left_seconds
	if elapsed_seconds <= Constants.INCIDENT_GRACE_SECONDS:
		return
	if game.active_incidents.size() >= Constants.MAX_ACTIVE_INCIDENTS:
		return

	var incident_chance: float = (
		Constants.INCIDENT_BASE_CHANCE
		+ game.entropy / 100.0 * Constants.INCIDENT_CHANCE_BONUS_AT_100_ENTROPY
	)
	if randf() > incident_chance:
		return

	var available: Array[String] = []
	for incident_type in Constants.INCIDENT_TYPES:
		if not _has_incident(game, incident_type):
			available.append(incident_type)
	if available.is_empty():
		return

	var incident_type := available[randi_range(0, available.size() - 1)]
	var target_agent_type := ""
	if Constants.INCIDENT_TYPE_TO_AGENT.has(incident_type):
		target_agent_type = Constants.INCIDENT_TYPE_TO_AGENT[incident_type]
	var incident := {
		"id": "incident-%d" % game.next_incident_id,
		"type": incident_type,
		"active": true,
		"age_ticks": 0,
		"applied_reported": false,
		"target_agent_type": target_agent_type,
	}
	game.next_incident_id += 1
	game.active_incidents.append(incident)
	game.entropy += Constants.INCIDENT_CREATE_ENTROPY_GAIN

	if incident_type == "BUDGET_OPTIMIZATION":
		game.model_intelligence = false

	events.append({"type": "incident_created", "incident": incident_type})


func _update_agent_states(game) -> void:
	for agent in game.agents:
		if not agent.online:
			agent.state = game.AgentState.OFFLINE
			continue
		if agent.has_pending_review:
			agent.state = game.AgentState.WAITING_REVIEW
			continue
		if not game._active_incident_for_agent_type(agent.type).is_empty():
			agent.state = game.AgentState.UNSTABLE
			continue
		agent.state = game.AgentState.OK


func _check_outcome(game) -> int:
	if game.time_left_seconds <= 0:
		return game.Outcome.TIMEOUT
	if game.budget <= 0:
		return game.Outcome.BUDGET
	if game.stability <= 0:
		return game.Outcome.COLLAPSE
	if game.kpi >= Constants.KPI_TARGET:
		return game.Outcome.KPI
	return game.Outcome.NONE


func _auto_review_should_approve(game, agent: Dictionary, review: Dictionary) -> bool:
	var judged_good: bool = review["is_actually_good"]
	var error_rate: float
	match agent["state"]:
		game.AgentState.OK:
			error_rate = Constants.EVALUATOR_AUTO_REVIEW_ERROR_RATE_OK
		game.AgentState.UNSTABLE:
			error_rate = Constants.EVALUATOR_AUTO_REVIEW_ERROR_RATE_UNSTABLE
		game.AgentState.DRIFTING:
			error_rate = Constants.EVALUATOR_AUTO_REVIEW_ERROR_RATE_DRIFTING
		_:
			error_rate = Constants.EVALUATOR_AUTO_REVIEW_ERROR_RATE_OK
	if randf() < error_rate:
		return not judged_good
	return judged_good


func _online_agents_of_type(game, agent_type: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for agent in game.agents:
		if agent.online and agent.type == agent_type:
			matches.append(agent)
	return matches


func _first_online_agent_of_type(game, agent_type: String) -> Dictionary:
	for agent in game.agents:
		if agent.online and agent.type == agent_type:
			return agent
	return {}


func _bad_review_probability(game) -> float:
	if game.model_intelligence:
		return Constants.BAD_REVIEW_PROBABILITY_SMART
	return Constants.BAD_REVIEW_PROBABILITY_NOT_SMART


func _has_incident(game, incident_type: String) -> bool:
	for incident in game.active_incidents:
		if incident.type == incident_type:
			return true
	return false
