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

const FONT_REGULAR := preload("res://ui/font-mono.otf")
const FONT_BOLD := preload("res://ui/font-bold.otf")
const FONT_SCALE := 1.15


static func scaled_font_size(base_size: int) -> int:
	assert(base_size >= 1)
	return maxi(1, int(round(float(base_size) * FONT_SCALE)))


func build(root: Node, time_left_text: String, status_items: Array) -> Dictionary:
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

	var workspace: Dictionary = _build_workspace(status_items)
	var workspace_panel: Control = workspace["panel"]
	workspace_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(workspace_panel)

	return {
		"ui_root": ui_root,
		"title_label": top_bar["title_label"],
		"hotkey_hint_label": top_bar["hotkey_hint_label"],
		"time_label": top_bar["time_label"],
		"round_label": top_bar["round_label"],
		"status_title_label": workspace["status_title_label"],
		"agents_title_label": workspace["agents_title_label"],
		"reviews_title_label": workspace["reviews_title_label"],
		"mail_title_label": workspace["mail_title_label"],
		"status_name_labels": workspace["status_name_labels"],
		"status_value_labels": workspace["status_value_labels"],
		"agents_list_container": workspace["agents_list_container"],
		"review_slots_container": workspace["review_slots_container"],
		"task_slots_container": workspace["task_slots_container"],
		"log_view": workspace["log_view"],
		"mail_list": workspace["mail_list"],
		"mail_detail_view": workspace["mail_detail_view"],
	}


func _build_top_bar(time_left_text: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 76)
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
	title_label.add_theme_font_size_override("font_size", scaled_font_size(28))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left_group.add_child(title_label)

	var hotkey_hint_label := Label.new()
	hotkey_hint_label.text = tr("HOTKEY_HINT")
	_apply_font(hotkey_hint_label)
	hotkey_hint_label.add_theme_color_override("font_color", TEXT_DIM)
	hotkey_hint_label.add_theme_font_size_override("font_size", scaled_font_size(16))
	left_group.add_child(hotkey_hint_label)

	var time_center := CenterContainer.new()
	time_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(time_center)

	var time_label := Label.new()
	time_label.text = time_left_text
	_apply_font(time_label, FONT_BOLD)
	time_label.add_theme_color_override("font_color", TEXT)
	time_label.add_theme_font_size_override("font_size", scaled_font_size(26))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_center.add_child(time_label)

	var round_label := Label.new()
	round_label.text = ""
	_apply_font(round_label, FONT_BOLD)
	round_label.add_theme_color_override("font_color", TEXT_DIM)
	round_label.add_theme_font_size_override("font_size", scaled_font_size(24))
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(round_label)

	return {
		"panel": panel,
		"title_label": title_label,
		"hotkey_hint_label": hotkey_hint_label,
		"time_label": time_label,
		"round_label": round_label,
	}


func _build_workspace(status_items: Array) -> Dictionary:
	var workspace := HBoxContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 12)

	var left_column := VBoxContainer.new()
	left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.custom_minimum_size = Vector2(460, 0)
	left_column.add_theme_constant_override("separation", 12)
	workspace.add_child(left_column)

	var status_panel: Dictionary = _build_status_panel(status_items)
	var status_widget: Control = status_panel["panel"]
	status_widget.custom_minimum_size = Vector2(0, 210)
	left_column.add_child(status_widget)

	var mail_panel: Dictionary = _build_mail_panel()
	var mail_widget: Control = mail_panel["panel"]
	mail_widget.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_child(mail_widget)

	var center_column := VBoxContainer.new()
	center_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_column.custom_minimum_size = Vector2(520, 0)
	center_column.add_theme_constant_override("separation", 12)
	workspace.add_child(center_column)

	var agents_panel: Dictionary = _build_agents_panel()
	var agents_widget: Control = agents_panel["panel"]
	agents_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agents_widget.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_column.add_child(agents_widget)

	var log_panel: Dictionary = _build_log_panel()
	var log_widget: Control = log_panel["panel"]
	log_widget.custom_minimum_size = Vector2(0, 240)
	log_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_column.add_child(log_widget)

	var right_column := VBoxContainer.new()
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.custom_minimum_size = Vector2(460, 0)
	right_column.add_theme_constant_override("separation", 12)
	workspace.add_child(right_column)

	var task_panel: Dictionary = _build_task_panel()
	var task_widget: Control = task_panel["panel"]
	task_widget.custom_minimum_size = Vector2(0, 400)
	right_column.add_child(task_widget)

	var review_panel: Dictionary = _build_review_panel()
	var review_widget: Control = review_panel["panel"]
	review_widget.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_child(review_widget)

	return {
		"panel": workspace,
		"status_title_label": status_panel["title_label"],
		"agents_title_label": agents_panel["title_label"],
		"reviews_title_label": review_panel["title_label"],
		"mail_title_label": mail_panel["title_label"],
		"status_name_labels": status_panel["name_labels"],
		"status_value_labels": status_panel["value_labels"],
		"mail_list": mail_panel["mail_list"],
		"mail_detail_view": mail_panel["mail_detail_view"],
		"agents_list_container": agents_panel["agents_list_container"],
		"log_view": log_panel["log_view"],
		"review_slots_container": review_panel["review_slots_container"],
		"task_slots_container": task_panel["task_slots_container"],
	}


func _build_status_panel(status_items: Array) -> Dictionary:
	var panel := _panel_with_title(tr("STATUS"))
	var content := panel.get_meta("content") as VBoxContainer
	var title_label := panel.get_meta("title_label") as Label
	content.add_theme_constant_override("separation", 8)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)

	var name_labels := {}
	var value_labels := {}
	for item in status_items:
		assert(item.has("key"))
		assert(item.has("name"))
		assert(item.has("value"))
		assert(item.has("color"))
		var tile: Dictionary = _metric_tile(item["name"], item["value"], item["color"])
		grid.add_child(tile["tile"])
		name_labels[item["key"]] = tile["name_label"]
		value_labels[item["key"]] = tile["value_label"]

	return {
		"panel": panel,
		"title_label": title_label,
		"name_labels": name_labels,
		"value_labels": value_labels,
	}


func _build_mail_panel() -> Dictionary:
	var panel := _panel_with_title(tr("MAIL"))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content := panel.get_meta("content") as VBoxContainer
	var title_label := panel.get_meta("title_label") as Label
	var mail_list := ItemList.new()
	mail_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mail_list.custom_minimum_size = Vector2(0, 170)
	mail_list.select_mode = ItemList.SELECT_SINGLE
	mail_list.allow_reselect = true
	mail_list.add_theme_font_override("font", FONT_REGULAR)
	mail_list.add_theme_font_size_override("font_size", scaled_font_size(14))
	content.add_child(mail_list)

	content.add_child(HSeparator.new())

	var mail_detail_view := RichTextLabel.new()
	mail_detail_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mail_detail_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mail_detail_view.bbcode_enabled = true
	mail_detail_view.scroll_active = true
	mail_detail_view.scroll_following = true
	mail_detail_view.selection_enabled = false
	mail_detail_view.fit_content = false
	mail_detail_view.add_theme_font_override("normal_font", FONT_REGULAR)
	mail_detail_view.add_theme_font_override("bold_font", FONT_BOLD)
	mail_detail_view.add_theme_font_override("italics_font", FONT_REGULAR)
	mail_detail_view.add_theme_font_override("bold_italics_font", FONT_BOLD)
	mail_detail_view.add_theme_font_size_override("normal_font_size", scaled_font_size(14))
	content.add_child(mail_detail_view)

	return {
		"panel": panel,
		"title_label": title_label,
		"mail_list": mail_list,
		"mail_detail_view": mail_detail_view,
	}


func _build_log_panel() -> Dictionary:
	var panel := _panel_with_title(tr("LOG"))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _stylebox(LOG_BG, BORDER, 2, 8))
	var content := panel.get_meta("content") as VBoxContainer

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
	log_view.add_theme_font_override("italics_font", FONT_REGULAR)
	log_view.add_theme_font_override("bold_italics_font", FONT_BOLD)
	log_view.add_theme_font_size_override("normal_font_size", scaled_font_size(15))
	content.add_child(log_view)

	return {
		"panel": panel,
		"log_view": log_view,
	}


func _build_agents_panel() -> Dictionary:
	var panel := _panel_with_title(tr("AGENTS"))
	var content := panel.get_meta("content") as VBoxContainer
	var title_label := panel.get_meta("title_label") as Label

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = true
	content.add_child(scroll)

	var agents_list_container := GridContainer.new()
	agents_list_container.columns = 2
	agents_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agents_list_container.add_theme_constant_override("h_separation", 8)
	agents_list_container.add_theme_constant_override("v_separation", 8)
	scroll.add_child(agents_list_container)

	return {
		"panel": panel,
		"title_label": title_label,
		"agents_list_container": agents_list_container,
	}


func _build_review_panel() -> Dictionary:
	var panel := _panel_with_title(tr("REVIEWS"))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title_label := panel.get_meta("title_label") as Label
	var content := panel.get_meta("content") as VBoxContainer

	var review_scroll := ScrollContainer.new()
	review_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	review_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	review_scroll.clip_contents = true
	content.add_child(review_scroll)

	var review_slots_container := VBoxContainer.new()
	review_slots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review_slots_container.add_theme_constant_override("separation", 8)
	review_scroll.add_child(review_slots_container)

	return {
		"panel": panel,
		"title_label": title_label,
		"review_slots_container": review_slots_container,
	}


func _build_task_panel() -> Dictionary:
	var panel := _panel_with_title(tr("TASKS"))
	var content := panel.get_meta("content") as VBoxContainer

	var task_scroll := ScrollContainer.new()
	task_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	task_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	task_scroll.clip_contents = true
	content.add_child(task_scroll)

	var task_slots_container := VBoxContainer.new()
	task_slots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_slots_container.add_theme_constant_override("separation", 8)
	task_scroll.add_child(task_slots_container)

	return {
		"panel": panel,
		"task_slots_container": task_slots_container,
	}


func _metric_tile(item_name: String, value: float, color: Color) -> Dictionary:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.add_theme_stylebox_override("panel", _stylebox(PANEL_DARK, BORDER, 1, 6))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	tile.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var name_label := Label.new()
	name_label.text = item_name
	_apply_font(name_label, FONT_BOLD)
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_font_size_override("font_size", scaled_font_size(14))
	vbox.add_child(name_label)

	var value_label := Label.new()
	value_label.text = "%.1f/100" % value
	_apply_font(value_label)
	value_label.add_theme_color_override("font_color", TITLE)
	value_label.add_theme_font_size_override("font_size", scaled_font_size(15))
	vbox.add_child(value_label)

	return {"tile": tile, "name_label": name_label, "value_label": value_label}


func _section_header(text: String) -> Label:
	assert(not text.is_empty())
	var label := Label.new()
	label.text = text
	_apply_font(label, FONT_BOLD)
	label.add_theme_color_override("font_color", COLOR_BLUE)
	label.add_theme_font_size_override("font_size", scaled_font_size(16))
	return label


func _info_label(text: String) -> Label:
	assert(not text.is_empty())
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_font(label)
	label.add_theme_color_override("font_color", TEXT_DIM)
	label.add_theme_font_size_override("font_size", scaled_font_size(14))
	return label


func _panel_with_title(title_text: String) -> PanelContainer:
	assert(not title_text.is_empty())
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
	title.add_theme_font_size_override("font_size", scaled_font_size(22))
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
	assert(border_width >= 0)
	assert(radius >= 0)
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func _apply_font(control: Control, font: Font = FONT_REGULAR) -> void:
	assert(control != null)
	control.add_theme_font_override("font", font)
