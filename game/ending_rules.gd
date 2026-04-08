class_name EndingRules
extends RefCounted


func evaluate_round_outcome(game: Game) -> Game.Outcome:
	if game.time_left_seconds <= 0:
		return Game.Outcome.TIMEOUT
	if game.budget <= 0:
		return Game.Outcome.BUDGET
	if game.stability <= 0:
		return Game.Outcome.COLLAPSE
	if game.goal["status"] == Constants.GOAL_STATUS_ACHIEVED:
		return Game.Outcome.KPI
	return Game.Outcome.NONE


func round_outcome_key(outcome: int) -> String:
	match outcome:
		Game.Outcome.NONE:
			return ""
		Game.Outcome.TIMEOUT:
			return "TIMEOUT"
		Game.Outcome.BUDGET:
			return "BUDGET"
		Game.Outcome.COLLAPSE:
			return "COLLAPSE"
		Game.Outcome.KPI:
			return "KPI"
		_:
			assert(false, "Unknown outcome code in ending rules")
	return ""


func final_bucket(history: Array[int]) -> String:
	var budget_count := 0
	var collapse_count := 0
	var timeout_count := 0
	var kpi_count := 0
	var bucket: String = Constants.CONSOLE_FINAL_BUCKET_REORG
	for outcome in history:
		match outcome:
			Game.Outcome.BUDGET:
				budget_count += 1
			Game.Outcome.COLLAPSE:
				collapse_count += 1
			Game.Outcome.TIMEOUT:
				timeout_count += 1
			Game.Outcome.KPI:
				kpi_count += 1
			Game.Outcome.NONE:
				pass
			_:
				assert(false, "Unknown outcome in final bucket")

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
