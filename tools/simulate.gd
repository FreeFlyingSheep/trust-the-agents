@tool
extends EditorScript

const DEFAULT_SEED_VALUE := 42
const SIM_STEP_SECONDS := 1.0

const SPEED_SECONDS_LEVELS: Array[int] = [5, 10, 15, 20]
const REVIEW_ACCURACY_PERCENT_LEVELS: Array[int] = [0, 25, 50, 75, 100]
const PATCH_RATE_PERCENT_LEVELS: Array[int] = [0, 25, 50, 75, 100]


func _run() -> void:
	var scenarios: Array[Dictionary] = _build_human_scenarios()

	var run_reports: Array[Dictionary] = []
	for scenario in scenarios:
		seed(DEFAULT_SEED_VALUE)

		var report: Dictionary = _run_round(scenario)
		(
			run_reports
			. append(
				{
					"scenario": scenario,
					"report": report,
				}
			)
		)

	_print_sweep_analysis(run_reports)


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
	return [
		{
			"id": "pg",
			"generator_count": 1,
			"planner_count": 1,
			"evaluator_count": 0,
			"total_agents": 2
		},
		{
			"id": "ge",
			"generator_count": 1,
			"planner_count": 0,
			"evaluator_count": 1,
			"total_agents": 2
		},
		{
			"id": "pge",
			"generator_count": 1,
			"planner_count": 1,
			"evaluator_count": 1,
			"total_agents": 3
		},
		{
			"id": "ppg",
			"generator_count": 1,
			"planner_count": 2,
			"evaluator_count": 0,
			"total_agents": 3
		},
		{
			"id": "gee",
			"generator_count": 1,
			"planner_count": 0,
			"evaluator_count": 2,
			"total_agents": 3
		},
		{
			"id": "pgg",
			"generator_count": 2,
			"planner_count": 1,
			"evaluator_count": 0,
			"total_agents": 3
		},
		{
			"id": "gge",
			"generator_count": 2,
			"planner_count": 0,
			"evaluator_count": 1,
			"total_agents": 3
		},
		{
			"id": "ggg",
			"generator_count": 3,
			"planner_count": 0,
			"evaluator_count": 0,
			"total_agents": 3
		},
	]


func _run_round(scenario: Dictionary) -> Dictionary:
	var game: Game = Game.new()

	game.finish_boot()
	_configure_agent_mix(game, scenario)
	var speed_seconds: int = scenario["speed_seconds"]
	var elapsed_seconds: int = 0

	while game.run_state == Game.RunState.RUNNING:
		if elapsed_seconds % speed_seconds == 0:
			_human_take_actions(game, scenario)
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


func _configure_agent_mix(game: Game, scenario: Dictionary) -> void:
	var target_by_type: Dictionary = {
		"PLANNER": scenario["planner_count"],
		"GENERATOR": scenario["generator_count"],
		"EVALUATOR": scenario["evaluator_count"],
	}

	for agent_type in ["PLANNER", "GENERATOR", "EVALUATOR"]:
		var online_ids := _online_agent_ids_by_type(game, agent_type)
		for id in online_ids:
			game.perform_command("kill", id)

	for agent_type in ["PLANNER", "GENERATOR", "EVALUATOR"]:
		var target: int = target_by_type[agent_type]
		for _i in range(target):
			game.perform_command("run", agent_type.to_lower())


func _online_agent_ids_by_type(game: Game, agent_type: String) -> Array[String]:
	var ids: Array[String] = []
	for agent in game.get_agent_snapshot():
		if agent["type"] != agent_type:
			continue
		if not agent["online"]:
			continue
		ids.append(agent["id"])
	return ids


func _human_take_actions(game: Game, scenario: Dictionary) -> void:
	_ensure_target_agents_online(game, scenario)

	var accuracy: float = scenario["accuracy"]
	_resolve_pending_reviews(game, accuracy)

	var patch_rate: float = scenario["patch_rate"]
	var patch_probability: float = patch_rate
	_patch_clearable_incidents(game, patch_probability)


func _ensure_target_agents_online(game: Game, scenario: Dictionary) -> void:
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
		game.perform_command("run", agent_type.to_lower())


func _resolve_pending_reviews(game: Game, accuracy: float) -> void:
	var snapshot := game.get_agent_snapshot()
	for agent in snapshot:
		if not agent["has_pending_review"]:
			continue

		var review: Dictionary = agent["pending_review"]
		var target: String = agent["id"]
		if target.is_empty():
			continue

		var actual_good: bool = review["is_actually_good"]
		var judged_good: bool = actual_good
		if randf() > accuracy:
			judged_good = not actual_good

		if game.stability < 35:
			judged_good = false

		var command := "approve" if judged_good else "deny"
		game.perform_command(command, target)


func _patch_clearable_incidents(game: Game, patch_probability: float = 1.0) -> void:
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
		game.perform_command("patch", incident_id)
		patched += 1


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
	for entry in entries:
		var report: Dictionary = entry["report"]
		if report.is_empty():
			continue
		total_seconds += report["round_seconds"]
	return total_seconds * 1.0 / entries.size()


func _entries_by_mix(run_reports: Array[Dictionary], mix_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry in run_reports:
		var scenario: Dictionary = entry["scenario"]
		if scenario["mix_id"] == mix_id:
			entries.append(entry)
	return entries
