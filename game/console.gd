class_name Console
extends RefCounted

enum LogLevel { NONE, INFO, WARN, CRIT, MAIL }

var copybook: Copybook
var logs: Logs
var scripts: Scripts


func _init() -> void:
	copybook = Copybook.new()
	logs = Logs.new(copybook)
	scripts = Scripts.new(copybook)


func command_rows() -> Array[String]:
	var rows: Array[String] = []
	for command in Constants.CONSOLE_COMMANDS:
		rows.append(str(command))
	return rows


func build_boot_logs() -> Array[Dictionary]:
	return scripts.build_boot_logs()


func handle_input(raw_input: String, game: Game) -> Dictionary:
	if game.run_state == Game.RunState.BOOTING:
		return {"logs": []}

	var cleaned := raw_input.strip_edges()
	if cleaned.is_empty():
		return {"logs": []}

	var parts := cleaned.split(" ", false)
	var command := parts[0].to_lower()
	var target := ""
	if parts.size() > 1:
		target = cleaned.trim_prefix(parts[0]).strip_edges()

	if command in Constants.CONSOLE_COMMANDS_REQUIRE_TARGET and target.is_empty():
		return {
			"logs":
			[
				{
					"level": Console.LogLevel.WARN,
					"event_key": "SYSTEM",
					"message_key":
					copybook.resolve_structured_key(
						"EVENT", "SYSTEM", "R1", "ANY", "MISSING_TARGET", "00"
					),
					"message_args": [command],
					"message": "",
				}
			]
		}

	var result := game.perform_command(command, target)
	return {"logs": map_events(result.events, game)}


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
			"value": snapshot.stability,
			"color": Ui.COLOR_STATUS_STABILITY
		},
		{
			"key": "BUDGET",
			"name": tr("BUDGET"),
			"value": snapshot.budget,
			"color": Ui.COLOR_STATUS_BUDGET
		},
		{
			"key": "ENTROPY",
			"name": tr("ENTROPY"),
			"value": snapshot.entropy,
			"color": Ui.COLOR_YELLOW
		},
		{"key": "KPI", "name": tr("KPI"), "value": snapshot.kpi, "color": Ui.COLOR_STATUS_KPI},
	]


func time_text(game: Game) -> String:
	var display_seconds := game.time_left_seconds
	if game.run_state == Game.RunState.RUNNING:
		display_seconds = floori(game.time_left_seconds - game.tick_accumulator_seconds)
	return tr("TIME_LEFT_FORMAT") % display_seconds


func round_text(game: Game) -> String:
	return tr("ROUND_FORMAT") % game.round_index


func prompt_text(game: Game) -> String:
	return tr(game.current_user_key()) + " #"


func map_events(events: Array, game: Game) -> Array[Dictionary]:
	return logs.map(events, game)
