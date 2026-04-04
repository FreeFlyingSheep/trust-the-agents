class_name Ui
extends RefCounted

const BG := Color("#08111f")
const PANEL := Color("#0f1b2d")
const PANEL_DARK := Color("#0b1626")
const LOG_BG := Color("#050b14")
const BORDER := Color("#20324a")
const TEXT := Color("#d5dfeb")
const TEXT_DIM := Color("#8596aa")
const TITLE := Color("#f3f7fb")

const COLOR_GRAY := Color("#c9d3df")
const COLOR_BLUE := Color("#4bb3fd")
const COLOR_GREEN := Color("#2ec27e")
const COLOR_YELLOW := Color("#f4c95d")
const COLOR_RED := Color("#ff6b81")
const COLOR_STATUS_STABILITY := Color("#4ade80")
const COLOR_STATUS_BUDGET := Color("#60a5fa")
const COLOR_STATUS_ENTROPY := Color("#c084fc")
const COLOR_STATUS_KPI := Color("#f59e0b")
const COLOR_TRANSPARENT := Color("#00000000")

const FONT_REGULAR := preload("res://ui/font-mono.ttf")
const FONT_BOLD := preload("res://ui/font-bold.ttf")
const FONT_ITALIC := preload("res://ui/font-italic.ttf")
const FONT_BOLD_ITALIC := preload("res://ui/font-bold-italic.ttf")


func build(
	root: Node, time_left_text: String, status_items: Array, commands: Array[String]
) -> Dictionary:
	var canvas := CanvasLayer.new()
	root.add_child(canvas)

	var ui_root := Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui_root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG
	ui_root.add_child(bg)

	var main_margin := MarginContainer.new()
	main_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_margin.add_theme_constant_override("margin_left", 20)
	main_margin.add_theme_constant_override("margin_top", 20)
	main_margin.add_theme_constant_override("margin_right", 20)
	main_margin.add_theme_constant_override("margin_bottom", 20)
	ui_root.add_child(main_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 12)
	main_margin.add_child(root_vbox)

	var top_bar: Dictionary = _build_top_bar(time_left_text)
	root_vbox.add_child(top_bar["panel"])

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root_vbox.add_child(body)

	var left_sidebar: Dictionary = _build_left_sidebar(status_items, commands)
	var left_panel: Control = left_sidebar["panel"]
	left_panel.custom_minimum_size = Vector2(300, 0)
	body.add_child(left_panel)

	var terminal: Dictionary = _build_terminal_panel()
	var right_panel: Control = terminal["panel"]
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_panel)

	return {
		"ui_root": ui_root,
		"title_label": top_bar["title_label"],
		"hotkey_hint_label": top_bar["hotkey_hint_label"],
		"time_label": top_bar["time_label"],
		"round_label": top_bar["round_label"],
		"status_title_label": left_sidebar["status_title_label"],
		"commands_title_label": left_sidebar["commands_title_label"],
		"status_name_labels": left_sidebar["status_name_labels"],
		"status_value_labels": left_sidebar["status_value_labels"],
		"log_view": terminal["log_view"],
		"prompt_label": terminal["prompt_label"],
		"input_line": terminal["input_line"],
	}


func _build_top_bar(time_left_text: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 68)
	panel.add_theme_stylebox_override("panel", _stylebox(PANEL_DARK, BORDER, 2, 8))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	var left_group := HBoxContainer.new()
	left_group.add_theme_constant_override("separation", 8)
	left_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_group)

	var title_label := Label.new()
	title_label.text = tr("TITLE")
	_apply_font(title_label, FONT_BOLD)
	title_label.add_theme_color_override("font_color", TITLE)
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left_group.add_child(title_label)

	var hotkey_hint_label := Label.new()
	hotkey_hint_label.text = tr("HOTKEY_HINT")
	_apply_font(hotkey_hint_label)
	hotkey_hint_label.add_theme_color_override("font_color", TEXT_DIM)
	hotkey_hint_label.add_theme_font_size_override("font_size", 16)
	left_group.add_child(hotkey_hint_label)

	var time_center := CenterContainer.new()
	time_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(time_center)

	var time_label := Label.new()
	time_label.text = time_left_text
	_apply_font(time_label, FONT_BOLD)
	time_label.add_theme_color_override("font_color", TEXT)
	time_label.add_theme_font_size_override("font_size", 26)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_center.add_child(time_label)

	var round_label := Label.new()
	round_label.text = ""
	_apply_font(round_label, FONT_BOLD)
	round_label.add_theme_color_override("font_color", TEXT_DIM)
	round_label.add_theme_font_size_override("font_size", 24)
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(round_label)

	return {
		"panel": panel,
		"title_label": title_label,
		"hotkey_hint_label": hotkey_hint_label,
		"time_label": time_label,
		"round_label": round_label
	}


func _build_left_sidebar(status_items: Array, commands: Array[String]) -> Dictionary:
	var sidebar := VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_FILL
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 12)

	var status_panel: Dictionary = _build_status_panel(status_items)
	sidebar.add_child(status_panel["panel"])
	var command_panel: Dictionary = _build_command_panel(commands)
	sidebar.add_child(command_panel["panel"])

	return {
		"panel": sidebar,
		"status_title_label": status_panel["title_label"],
		"commands_title_label": command_panel["title_label"],
		"status_name_labels": status_panel["name_labels"],
		"status_value_labels": status_panel["value_labels"],
	}


func _build_status_panel(status_items: Array) -> Dictionary:
	var panel := _panel_with_title(tr("STATUS"))
	var content := panel.get_meta("content") as VBoxContainer
	var title_label := panel.get_meta("title_label") as Label
	var name_labels := {}
	var value_labels := {}
	for item in status_items:
		var row: Dictionary = _metric_row(item.name, item.value, item.color)
		content.add_child(row["row"])
		name_labels[item.key] = row["name_label"]
		value_labels[item.key] = row["value_label"]
	return {
		"panel": panel,
		"title_label": title_label,
		"name_labels": name_labels,
		"value_labels": value_labels
	}


func _build_command_panel(commands: Array[String]) -> Dictionary:
	var panel := _panel_with_title(tr("COMMANDS"))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title_label := panel.get_meta("title_label") as Label

	var content := panel.get_meta("content") as VBoxContainer
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = true
	content.add_child(scroll)

	var command_list := VBoxContainer.new()
	command_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_list.add_theme_constant_override("separation", 10)
	scroll.add_child(command_list)

	for command in commands:
		command_list.add_child(_command_row(command))

	return {"panel": panel, "title_label": title_label}


func _build_terminal_panel() -> Dictionary:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 12)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _stylebox(LOG_BG, BORDER, 2, 8))
	wrapper.add_child(panel)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var log_view := RichTextLabel.new()
	log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.bbcode_enabled = true
	log_view.scroll_active = true
	log_view.scroll_following = true
	log_view.selection_enabled = false
	log_view.fit_content = false
	log_view.add_theme_font_override("normal_font", FONT_REGULAR)
	log_view.add_theme_font_override("bold_font", FONT_BOLD)
	log_view.add_theme_font_override("italics_font", FONT_ITALIC)
	log_view.add_theme_font_override("bold_italics_font", FONT_BOLD_ITALIC)
	log_view.add_theme_font_size_override("normal_font_size", 20)
	margin.add_child(log_view)

	var input_panel := PanelContainer.new()
	input_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_panel.custom_minimum_size = Vector2(0, 52)
	input_panel.add_theme_stylebox_override("panel", _stylebox(PANEL_DARK, BORDER, 2, 8))
	wrapper.add_child(input_panel)

	var input_margin := MarginContainer.new()
	input_margin.add_theme_constant_override("margin_left", 14)
	input_margin.add_theme_constant_override("margin_top", 8)
	input_margin.add_theme_constant_override("margin_right", 14)
	input_margin.add_theme_constant_override("margin_bottom", 8)
	input_panel.add_child(input_margin)

	var input_row := HBoxContainer.new()
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_theme_constant_override("separation", 10)
	input_margin.add_child(input_row)

	var prompt_label := Label.new()
	prompt_label.text = tr("PROMPT_READY")
	_apply_font(prompt_label, FONT_BOLD)
	prompt_label.add_theme_color_override("font_color", COLOR_GREEN)
	prompt_label.add_theme_font_size_override("font_size", 20)
	input_row.add_child(prompt_label)

	var input_line := LineEdit.new()
	input_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_line.caret_column = 0
	_apply_font(input_line)
	input_line.add_theme_color_override("font_color", TEXT)
	input_line.add_theme_color_override("caret_color", COLOR_GREEN)
	input_line.add_theme_stylebox_override(
		"normal", _stylebox(COLOR_TRANSPARENT, COLOR_TRANSPARENT, 0, 0)
	)
	input_line.add_theme_stylebox_override(
		"focus", _stylebox(COLOR_TRANSPARENT, COLOR_TRANSPARENT, 0, 0)
	)
	input_line.add_theme_font_size_override("font_size", 20)
	input_row.add_child(input_line)

	return {
		"panel": wrapper,
		"log_view": log_view,
		"prompt_label": prompt_label,
		"input_line": input_line,
	}


func _metric_row(item_name: String, value: int, color: Color) -> Dictionary:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.text = item_name
	_apply_font(name_label, FONT_BOLD)
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	var value_label := Label.new()
	value_label.text = "%d/100" % value
	_apply_font(value_label)
	value_label.add_theme_color_override("font_color", TITLE)
	value_label.add_theme_font_size_override("font_size", 18)
	hbox.add_child(value_label)

	return {"row": hbox, "name_label": name_label, "value_label": value_label}


func _command_row(command: String) -> Control:
	var label := Label.new()
	label.text = "> %s" % command
	_apply_font(label)
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_font_size_override("font_size", 18)
	return label


func _panel_with_title(title_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _stylebox(PANEL, BORDER, 2, 8))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	_apply_font(title, FONT_BOLD)
	title.add_theme_color_override("font_color", TITLE)
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	vbox.add_child(content)

	panel.set_meta("content", content)
	panel.set_meta("title_label", title)
	return panel


func _stylebox(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	return s


func _apply_font(control: Control, font: Font = FONT_REGULAR) -> void:
	control.add_theme_font_override("font", font)
