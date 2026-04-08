class_name Console
extends RefCounted

enum LogLevel { NONE, INFO, WARN, CRIT }

var copybook: Copybook
var logs: Logs
var scripts: Scripts


func _init() -> void:
	copybook = Copybook.new()
	logs = Logs.new(copybook)
	scripts = Scripts.new(copybook)


func build_boot_logs() -> Array[Dictionary]:
	return scripts.build_boot_logs()


func finish_boot_and_build_login_logs(game: Game) -> Array[Dictionary]:
	return scripts.finish_boot_and_build_login_logs(game)


func build_round_transition_logs(game: Game) -> Array[Dictionary]:
	return scripts.build_round_transition_logs(game)


func status_items(game: Game) -> Array:
	var snapshot := game.get_status_snapshot()
	return [
		{
			"key": "STABILITY",
			"name": tr("STABILITY"),
			"value": snapshot["stability"],
			"color": Ui.COLOR_STATUS_STABILITY,
		},
		{
			"key": "BUDGET",
			"name": tr("BUDGET"),
			"value": snapshot["budget"],
			"color": Ui.COLOR_STATUS_BUDGET,
		},
		{
			"key": "ENTROPY",
			"name": tr("ENTROPY"),
			"value": snapshot["entropy"],
			"color": Ui.COLOR_YELLOW,
		},
		{
			"key": "KPI",
			"name": tr("KPI"),
			"value": snapshot["kpi"],
			"color": Ui.COLOR_STATUS_KPI,
		},
	]


func time_text(game: Game) -> String:
	var display_seconds := game.time_left_seconds
	if game.run_state == Game.RunState.RUNNING:
		display_seconds = floori(game.time_left_seconds - game.tick_accumulator_seconds)
	return tr("TIME_LEFT_FORMAT") % display_seconds


func round_text(game: Game) -> String:
	assert(game.round_index >= 1)
	return tr("ROUND_FORMAT") % game.round_index


func map_events(events: Array, game: Game) -> Array[Dictionary]:
	return logs.map(events, game)


func map_tick_events(events: Array, game: Game) -> Array[Dictionary]:
	return logs.map_tick(events, game)
