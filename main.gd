extends Node2D

enum LoginPhase { BOOT_STREAMING, WAITING_LOGIN, POST_LOGIN_STREAM, READY }

var ui_root: Control
var title_label: Label
var hotkey_hint_label: Label
var time_label: Label
var round_label: Label
var log_view: RichTextLabel
var prompt_label: Label
var input_line: LineEdit
var status_title_label: Label
var commands_title_label: Label

var status_name_labels: Dictionary = {}
var status_value_labels: Dictionary = {}
var log_history: Array[Dictionary] = []
var scripted_log_items: Array[Dictionary] = []
var next_scripted_log_delay_seconds: float = -1.0
var login_phase: int = LoginPhase.BOOT_STREAMING

var game: Game
var console: Console


func _ready() -> void:
	var system_language := OS.get_locale_language().to_lower()
	if system_language.begins_with("zh"):
		TranslationServer.set_locale("zh")
	else:
		TranslationServer.set_locale("en")
	game = Game.new()
	console = Console.new()
	_build_ui()
	_start_boot_sequence(console.build_boot_logs())
	_refresh_chrome()
	input_line.keep_editing_on_text_submit = true
	input_line.grab_focus()
	input_line.text_submitted.connect(_on_command_submitted)


func _build_ui() -> void:
	var ui := Ui.new().build(self, "", console.status_items(game), console.command_rows())
	ui_root = ui["ui_root"]
	title_label = ui["title_label"]
	hotkey_hint_label = ui["hotkey_hint_label"]
	time_label = ui["time_label"]
	round_label = ui["round_label"]
	status_title_label = ui["status_title_label"]
	commands_title_label = ui["commands_title_label"]
	status_name_labels = ui["status_name_labels"]
	log_view = ui["log_view"]
	prompt_label = ui["prompt_label"]
	input_line = ui["input_line"]
	status_value_labels = ui["status_value_labels"]
	_refresh_locale_ui()


func _on_command_submitted(raw_input: String) -> void:
	var response := console.handle_input(raw_input, game)
	var response_logs: Array[Dictionary] = []
	for item in response["logs"]:
		response_logs.append(item)
	_append_logs(response_logs)
	input_line.clear()

	_handle_round_transition_if_needed()
	_refresh_chrome()
	if input_line.editable:
		input_line.call_deferred("grab_focus")


func _process(delta: float) -> void:
	var tick_events := game.advance_time(delta)
	if not tick_events.is_empty():
		_append_logs(console.map_events(tick_events, game))
		_handle_round_transition_if_needed()
	_drain_scripted_log_queue(delta)
	_refresh_chrome()


func _handle_round_transition_if_needed() -> void:
	if game.run_state != Game.RunState.ENDING:
		return
	var continue_play := game.has_more_rounds()
	var transition_logs := console.build_round_transition_logs(game)
	if continue_play:
		_start_boot_sequence(transition_logs)
		return
	_append_logs(transition_logs)
	input_line.editable = false


func _refresh_chrome() -> void:
	var logged_in := game.run_state == Game.RunState.RUNNING
	time_label.text = console.time_text(game)
	round_label.text = console.round_text(game)
	prompt_label.visible = logged_in
	if logged_in:
		prompt_label.text = console.prompt_text(game)
	else:
		prompt_label.text = ""
	input_line.editable = logged_in
	input_line.caret_blink = logged_in
	_refresh_status_values()


func _toggle_language() -> void:
	if TranslationServer.get_locale().begins_with("zh"):
		TranslationServer.set_locale("en")
	else:
		TranslationServer.set_locale("zh")
	_refresh_locale_ui()
	_refresh_chrome()


func _refresh_locale_ui() -> void:
	title_label.text = tr("TITLE")
	hotkey_hint_label.text = tr("HOTKEY_HINT")
	status_title_label.text = tr("STATUS")
	commands_title_label.text = tr("COMMANDS")
	for key in status_name_labels.keys():
		var label: Label = status_name_labels[key]
		if label != null:
			label.text = tr(key)
	_rerender_log_history()


func _input(event: InputEvent) -> void:
	var handled := false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		var is_wheel := (
			mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP
			or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN
			or mouse_event.button_index == MOUSE_BUTTON_WHEEL_LEFT
			or mouse_event.button_index == MOUSE_BUTTON_WHEEL_RIGHT
		)
		if not is_wheel:
			handled = true
	elif event is InputEventMouseMotion:
		handled = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
			handled = true
		elif event.keycode == KEY_F1:
			_toggle_language()
			handled = true
		elif event.keycode == KEY_F2:
			_toggle_fullscreen()
			handled = true
		elif (
			(event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)
			and login_phase == LoginPhase.WAITING_LOGIN
		):
			_on_login_confirmed()
			handled = true

	if handled:
		get_viewport().set_input_as_handled()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _append_logs(logs: Array[Dictionary]) -> void:
	for item in logs:
		log_history.append(item)
		log_view.append_text(_format_log(item) + "\n")


func _append_scripted_logs(logs: Array[Dictionary]) -> void:
	for item in logs:
		scripted_log_items.append(item)
	if next_scripted_log_delay_seconds < 0.0 and not scripted_log_items.is_empty():
		next_scripted_log_delay_seconds = randf_range(
			Constants.LOG_DELAY_MIN_SECONDS, Constants.LOG_DELAY_MAX_SECONDS
		)


func _start_boot_sequence(boot_logs: Array[Dictionary]) -> void:
	login_phase = LoginPhase.BOOT_STREAMING
	scripted_log_items.clear()
	next_scripted_log_delay_seconds = -1.0
	_append_scripted_logs(boot_logs)


func _on_login_confirmed() -> void:
	if login_phase != LoginPhase.WAITING_LOGIN:
		return
	var login_logs := console.finish_boot_and_build_login_logs(game)
	if login_logs.is_empty():
		login_phase = LoginPhase.READY
		return

	var immediate_logs: Array[Dictionary] = [login_logs[0]]
	_append_logs(immediate_logs)

	if login_logs.size() == 1:
		login_phase = LoginPhase.READY
		return

	var delayed_logs: Array[Dictionary] = []
	for index in range(1, login_logs.size()):
		delayed_logs.append(login_logs[index])
	login_phase = LoginPhase.POST_LOGIN_STREAM
	_append_scripted_logs(delayed_logs)


func _drain_scripted_log_queue(delta: float) -> void:
	if scripted_log_items.is_empty():
		next_scripted_log_delay_seconds = -1.0
		if login_phase == LoginPhase.BOOT_STREAMING:
			login_phase = LoginPhase.WAITING_LOGIN
		elif login_phase == LoginPhase.POST_LOGIN_STREAM:
			login_phase = LoginPhase.READY
		return

	if next_scripted_log_delay_seconds < 0.0:
		next_scripted_log_delay_seconds = randf_range(
			Constants.LOG_DELAY_MIN_SECONDS, Constants.LOG_DELAY_MAX_SECONDS
		)

	next_scripted_log_delay_seconds -= delta
	while next_scripted_log_delay_seconds <= 0.0 and not scripted_log_items.is_empty():
		var item: Dictionary = scripted_log_items.pop_front()
		_append_logs([item])
		if scripted_log_items.is_empty():
			next_scripted_log_delay_seconds = -1.0
			if login_phase == LoginPhase.BOOT_STREAMING:
				login_phase = LoginPhase.WAITING_LOGIN
			elif login_phase == LoginPhase.POST_LOGIN_STREAM:
				login_phase = LoginPhase.READY
			return
		next_scripted_log_delay_seconds += randf_range(
			Constants.LOG_DELAY_MIN_SECONDS, Constants.LOG_DELAY_MAX_SECONDS
		)


func _rerender_log_history() -> void:
	log_view.clear()
	for item in log_history:
		log_view.append_text(_format_log(item) + "\n")


func _format_log(item: Dictionary) -> String:
	var level: int = item.level
	var event_key: String = item.event_key
	var message := _resolve_log_message(item)
	var event_label := TranslationServer.translate(event_key)
	var color := _color_for_level(level)
	if event_key == "TITLE":
		return "[color=%s][b]%s[/b] %s[/color]" % [color, event_label, message]
	return "[color=%s][%s] %s[/color]" % [color, event_label, message]


func _resolve_log_message(item: Dictionary) -> String:
	if item.has("message_key"):
		var template := TranslationServer.translate(item["message_key"])
		var resolved_args: Array = []
		for arg in item["message_args"]:
			resolved_args.append(_sanitize_log_arg(_resolve_log_arg(arg)))
		if resolved_args.is_empty():
			return _escape_bbcode(template)
		return template % resolved_args
	return _escape_bbcode(item["message"])


func _resolve_log_arg(arg: Variant) -> Variant:
	if arg is Dictionary:
		var arg_dict: Dictionary = arg
		if arg_dict.has("tr_key"):
			return tr(arg_dict["tr_key"])
		if arg_dict.has("join_tr_keys"):
			var parts: Array[String] = []
			for key in arg_dict["join_tr_keys"]:
				parts.append(tr(key))
			return ", ".join(parts)
	return arg


func _sanitize_log_arg(arg: Variant) -> Variant:
	if arg is String:
		return _escape_bbcode(arg)
	return arg


func _escape_bbcode(text: String) -> String:
	return text.replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]")


func _color_for_level(level: int) -> String:
	match level:
		Console.LogLevel.NONE:
			return Ui.TEXT.to_html(false)
		Console.LogLevel.INFO:
			return Ui.COLOR_BLUE.to_html(false)
		Console.LogLevel.WARN:
			return Ui.COLOR_YELLOW.to_html(false)
		Console.LogLevel.CRIT:
			return Ui.COLOR_RED.to_html(false)
		Console.LogLevel.MAIL:
			return Ui.COLOR_GREEN.to_html(false)
		_:
			return Ui.TEXT.to_html(false)


func _refresh_status_values() -> void:
	var snapshot := game.get_status_snapshot()
	_set_status_value("STABILITY", snapshot.stability)
	_set_status_value("BUDGET", snapshot.budget)
	_set_status_value("ENTROPY", snapshot.entropy)
	_set_status_value("KPI", snapshot.kpi)


func _set_status_value(key: String, value: float) -> void:
	if not status_value_labels.has(key):
		return
	var label: Label = status_value_labels[key]
	label.text = "%.1f/100" % value
