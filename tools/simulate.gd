extends SceneTree

const DEFAULT_TOTAL_ROUNDS := 60
const SIM_STEP_SECONDS := 1.0
const DEFAULT_BASE_SEED := 42

const SPEED_SECONDS_LEVELS: Array[int] = [5, 10, 15, 20]
const REVIEW_ACCURACY_PERCENT_LEVELS: Array[int] = [0, 25, 50, 75, 100]
const PATCH_RATE_PERCENT_LEVELS: Array[int] = [0, 25, 50, 75, 100]


func _init() -> void:
	var scenarios: Array[Dictionary] = _build_human_scenarios()
	var selected_scenarios := _select_scenarios_for_rounds(scenarios, DEFAULT_TOTAL_ROUNDS)
	var run_reports: Array[Dictionary] = []
	for index in range(selected_scenarios.size()):
		var scenario: Dictionary = selected_scenarios[index]
		seed(DEFAULT_BASE_SEED + index)
		var report: Dictionary = _run_round(scenario)
		run_reports.append({"scenario": scenario, "report": report})

	_print_sweep_analysis(run_reports)
	print("simulation completed.")
	quit()


func _build_human_scenarios() -> Array[Dictionary]:
	var scenarios: Array[Dictionary] = []
	for mix in _build_agent_mixes():
		for speed_seconds in SPEED_SECONDS_LEVELS:
			for accuracy_percent in REVIEW_ACCURACY_PERCENT_LEVELS:
				for patch_rate_percent in PATCH_RATE_PERCENT_LEVELS:
					(
						scenarios
						. append(
							{
								"mix_id": mix["id"],
								"generator_count": mix["generator_count"],
								"planner_count": mix["planner_count"],
								"evaluator_count": mix["evaluator_count"],
								"total_agents": mix["total_agents"],
								"speed_seconds": speed_seconds,
								"accuracy_percent": accuracy_percent,
								"accuracy": accuracy_percent / 100.0,
								"patch_rate_percent": patch_rate_percent,
								"patch_rate": patch_rate_percent / 100.0,
							}
						)
					)
	return scenarios


func _build_agent_mixes() -> Array[Dictionary]:
	var mixes: Array[Dictionary] = []
	for total_agents in range(1, 6):
		for planner_count in range(total_agents + 1):
			for generator_count in range(total_agents - planner_count + 1):
				var evaluator_count := total_agents - planner_count - generator_count
				(
					mixes
					. append(
						{
							"id": "p%dg%de%d" % [planner_count, generator_count, evaluator_count],
							"generator_count": generator_count,
							"planner_count": planner_count,
							"evaluator_count": evaluator_count,
							"total_agents": total_agents,
						}
					)
				)
	return mixes


func _run_round(scenario: Dictionary) -> Dictionary:
	var game: Game = Game.new()

	game.finish_boot()
	_configure_agent_mix(game, scenario)
	var speed_seconds: int = scenario["speed_seconds"]
	var elapsed_seconds: int = 0

	while game.run_state == Game.RunState.RUNNING:
		if elapsed_seconds % speed_seconds == 0:
			_human_take_actions(game, scenario, elapsed_seconds)

		game.advance_time(SIM_STEP_SECONDS)

		elapsed_seconds += 1

	var outcome_name: String = _outcome_name(game.last_outcome)
	var overall: Dictionary = _new_outcome_counter()
	overall[outcome_name] = overall[outcome_name] + 1

	return {
		"overall": overall,
		"total_rounds": 1,
		"round_seconds": elapsed_seconds,
		"outcome": outcome_name,
	}


func _select_scenarios_for_rounds(
	scenarios: Array[Dictionary], total_rounds: int
) -> Array[Dictionary]:
	if scenarios.is_empty():
		return []
	var rounds := maxi(1, total_rounds)
	if rounds >= scenarios.size():
		var all_scenarios: Array[Dictionary] = []
		for scenario in scenarios:
			all_scenarios.append(scenario)
		return all_scenarios
	var scenarios_by_mix: Dictionary = {}
	var mix_order: Array[String] = []
	for scenario in scenarios:
		var mix_id: String = scenario["mix_id"]
		if not scenarios_by_mix.has(mix_id):
			scenarios_by_mix[mix_id] = []
			mix_order.append(mix_id)
		var bucket: Array = scenarios_by_mix[mix_id]
		bucket.append(scenario)
		scenarios_by_mix[mix_id] = bucket
	var selected: Array[Dictionary] = []
	for i in range(rounds):
		var mix_id := mix_order[i % mix_order.size()]
		var bucket: Array = scenarios_by_mix[mix_id]
		var bucket_step: float = bucket.size() * 1.0 / rounds
		var bucket_index := mini(bucket.size() - 1, int(floor(i * bucket_step)))
		selected.append(bucket[bucket_index])
	return selected


func _configure_agent_mix(game: Game, scenario: Dictionary) -> void:
	var target_by_type: Dictionary = {
		"PLANNER": scenario["planner_count"],
		"GENERATOR": scenario["generator_count"],
		"EVALUATOR": scenario["evaluator_count"],
	}

	for agent_type in ["PLANNER", "GENERATOR", "EVALUATOR"]:
		var online_ids := _online_agent_ids_by_type(game, agent_type)
		for id in online_ids:
			_perform_and_record(game, scenario, 0, "setup", "kill", id)

	for agent_type in ["PLANNER", "GENERATOR", "EVALUATOR"]:
		var target: int = target_by_type[agent_type]
		for _i in range(target):
			_perform_and_record(game, scenario, 0, "setup", "run", agent_type.to_lower())


func _online_agent_ids_by_type(game: Game, agent_type: String) -> Array[String]:
	var ids: Array[String] = []
	for agent in game.get_agent_snapshot():
		if agent["type"] != agent_type:
			continue
		if not agent["online"]:
			continue
		ids.append(agent["id"])
	return ids


func _human_take_actions(game: Game, scenario: Dictionary, tick: int) -> void:
	_ensure_target_agents_online(game, scenario, tick)

	var accuracy: float = scenario["accuracy"]
	_resolve_pending_reviews(game, scenario, tick, accuracy)

	var patch_rate: float = scenario["patch_rate"]
	_patch_clearable_incidents(game, scenario, tick, patch_rate)


func _ensure_target_agents_online(game: Game, scenario: Dictionary, tick: int) -> void:
	for agent_type in ["PLANNER", "GENERATOR", "EVALUATOR"]:
		var target: int = 0
		match agent_type:
			"PLANNER":
				target = scenario["planner_count"]
			"GENERATOR":
				target = scenario["generator_count"]
			"EVALUATOR":
				target = scenario["evaluator_count"]

		var online_now := _online_agent_ids_by_type(game, agent_type).size()
		if online_now >= target:
			continue
		_perform_and_record(game, scenario, tick, "human", "run", agent_type.to_lower())


func _resolve_pending_reviews(game: Game, scenario: Dictionary, tick: int, accuracy: float) -> void:
	var snapshot := game.get_agent_snapshot()
	for agent in snapshot:
		if not agent["has_pending_review"]:
			continue

		var target: String = agent["id"]
		if target.is_empty():
			continue

		var judged_good := randf() < accuracy

		if game.stability < 35:
			judged_good = false

		var command := "approve" if judged_good else "deny"
		_perform_and_record(game, scenario, tick, "human", command, target)


func _patch_clearable_incidents(
	game: Game, scenario: Dictionary, tick: int, patch_probability: float = 1.0
) -> void:
	var patched := 0
	for incident in game.get_incident_snapshot():
		if patched >= 1:
			return
		if incident["type"] == "BUDGET_OPTIMIZATION":
			continue
		var incident_id: String = incident["id"]
		if incident_id.is_empty():
			continue
		if randf() > patch_probability:
			continue
		_perform_and_record(game, scenario, tick, "human", "patch", incident_id)
		patched += 1


func _perform_and_record(
	game: Game,
	_scenario: Dictionary,
	_tick: int,
	_source: String,
	action: String,
	target: String = ""
) -> void:
	_run_action(game, action, target)


func _run_action(game: Game, action: String, target: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match action:
		"run":
			var run_target := game.run_agent(target.strip_edges().to_upper())
			if run_target.is_empty():
				return events
			events.append({"type": "agent_ran", "target": run_target})
		"kill":
			var kill_result := game.kill_agent(target)
			if not kill_result["ok"]:
				return events
			for event in kill_result["events"]:
				events.append(event)
		"approve":
			var resolved: Dictionary = game.flow._resolve_review_by_target(
				game, target, true, "human-reviewer", "HUMAN"
			)
			if resolved.is_empty():
				return events
			events.append(resolved)
		"deny":
			var denied: Dictionary = game.flow._resolve_review_by_target(
				game, target, false, "human-reviewer", "HUMAN"
			)
			if denied.is_empty():
				return events
			events.append(denied)
			assert(game.tasks.has(denied["task_id"]))
			var rejected_task: Dictionary = game.tasks[denied["task_id"]]
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
		"patch":
			var patch_result: Dictionary = game.flow._patch_target(game, target)
			if not patch_result["ok"]:
				return events
			var incident: Dictionary = patch_result["incident"]
			(
				events
				. append(
					{
						"type": "incident_patched",
						"incident_id": incident["id"],
						"incident": incident["type"],
						"target": incident["agent_id"],
					}
				)
			)
		_:
			assert(false, "Unknown simulate action")
	return events


func _new_outcome_counter() -> Dictionary:
	return {
		"KPI": 0,
		"BUDGET": 0,
		"COLLAPSE": 0,
		"TIMEOUT": 0,
		"NONE": 0,
	}


func _outcome_name(outcome: int) -> String:
	match outcome:
		Game.Outcome.KPI:
			return "KPI"
		Game.Outcome.BUDGET:
			return "BUDGET"
		Game.Outcome.COLLAPSE:
			return "COLLAPSE"
		Game.Outcome.TIMEOUT:
			return "TIMEOUT"
		_:
			return "NONE"


func _print_sweep_analysis(run_reports: Array[Dictionary]) -> void:
	if run_reports.is_empty():
		return

	_print_distribution_header()
	_print_distribution_row("overall", run_reports, _aggregate_outcomes(run_reports))
	for total_agents in range(1, 6):
		var size_group: Array[Dictionary] = _entries_by_total_agents(run_reports, total_agents)
		if size_group.is_empty():
			continue
		_print_distribution_row(
			"agents-%d" % total_agents, size_group, _aggregate_outcomes(size_group)
		)
	for mix in _build_agent_mixes():
		var mix_id: String = mix["id"]
		var group: Array[Dictionary] = _entries_by_mix(run_reports, mix_id)
		if group.is_empty():
			continue
		_print_distribution_row(mix_id, group, _aggregate_outcomes(group))


func _aggregate_outcomes(entries: Array[Dictionary]) -> Dictionary:
	var aggregate := _new_outcome_counter()
	for entry in entries:
		var report: Dictionary = entry["report"]
		if report.is_empty():
			continue
		var overall: Dictionary = report["overall"]
		for outcome_key in aggregate.keys():
			aggregate[outcome_key] = aggregate[outcome_key] + overall[outcome_key]
	return aggregate


func _distribution_total(counts: Dictionary) -> int:
	var total := 0
	for key in ["KPI", "BUDGET", "COLLAPSE", "TIMEOUT", "NONE"]:
		total += counts[key]
	return total


func _pct(count: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return 100.0 * count / total


func _print_distribution_header() -> void:
	print(
		(
			"  %-10s %-10s %-10s %-10s %-10s %-10s %-10s"
			% ["GROUP", "ROUNDS", "SECONDS", "KPI%", "BUDGET%", "COLLAPSE%", "TIMEOUT%"]
		)
	)


func _print_distribution_row(label: String, entries: Array[Dictionary], counts: Dictionary) -> void:
	var total := _distribution_total(counts)
	var kpi: int = counts["KPI"]
	var budget: int = counts["BUDGET"]
	var collapse: int = counts["COLLAPSE"]
	var timeout: int = counts["TIMEOUT"]
	var avg_seconds: float = _average_round_seconds(entries)
	print(
		(
			"  %-10s %-10d %-10.1f %-10.1f %-10.1f %-10.1f %-10.1f"
			% [
				label,
				total,
				avg_seconds,
				_pct(kpi, total),
				_pct(budget, total),
				_pct(collapse, total),
				_pct(timeout, total),
			]
		)
	)


func _average_round_seconds(entries: Array[Dictionary]) -> float:
	if entries.is_empty():
		return 0.0
	var total_seconds: int = 0
	var total_rounds: int = 0
	for entry in entries:
		var report: Dictionary = entry["report"]
		if report.is_empty():
			continue
		total_seconds += int(report["round_seconds"])
		total_rounds += int(report["total_rounds"])
	if total_rounds <= 0:
		return 0.0
	return total_seconds * 1.0 / total_rounds


func _entries_by_mix(run_reports: Array[Dictionary], mix_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry in run_reports:
		var scenario: Dictionary = entry["scenario"]
		if scenario["mix_id"] == mix_id:
			entries.append(entry)
	return entries


func _entries_by_total_agents(
	run_reports: Array[Dictionary], total_agents: int
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry in run_reports:
		var scenario: Dictionary = entry["scenario"]
		if int(scenario["total_agents"]) == total_agents:
			entries.append(entry)
	return entries
