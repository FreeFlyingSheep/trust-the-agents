class_name Feed
extends RefCounted

const MAIL_HISTORY_LIMIT := 12
const LOG_EMIT_INTERVAL_SECONDS := 0.8
const LOGS_PER_FLUSH := 1

var log_view: RichTextLabel
var mail_list: ItemList
var mail_detail_view: RichTextLabel

var log_history: Array[Dictionary] = []
var mail_items: Array[Dictionary] = []
var selected_mail_index := -1
var pending_log_queue: Array[Dictionary] = []
var log_emit_accumulator_seconds := 0.0
var mail_updated_at_counter := 0


func _t(key: String) -> String:
	var translated := tr(key)
	assert(translated != key, "Missing translation key: %s" % key)
	return translated


func _tf(key: String, args: Array = []) -> String:
	var template := _t(key)
	if args.is_empty():
		assert(template.find("%") == -1, "Unexpected format pattern in key: %s" % key)
		return template
	assert(template.find("%") != -1, "Missing format pattern in key: %s" % key)
	return template % args


func bind_views(
	log_view_ref: RichTextLabel, mail_list_ref: ItemList, mail_detail_view_ref: RichTextLabel
) -> void:
	assert(log_view_ref != null)
	assert(mail_list_ref != null)
	assert(mail_detail_view_ref != null)
	log_view = log_view_ref
	mail_list = mail_list_ref
	mail_detail_view = mail_detail_view_ref


func append_immediate_logs(logs: Array[Dictionary]) -> void:
	_append_logs_internal(logs)


func queue_mapped_logs(logs: Array[Dictionary]) -> void:
	for item in logs:
		pending_log_queue.append(item)


func flush(delta: float) -> void:
	assert(delta >= 0.0)
	if pending_log_queue.is_empty():
		log_emit_accumulator_seconds = 0.0
		return
	log_emit_accumulator_seconds += delta
	if log_emit_accumulator_seconds < LOG_EMIT_INTERVAL_SECONDS:
		return
	log_emit_accumulator_seconds = 0.0
	var emitted := 0
	while emitted < LOGS_PER_FLUSH and not pending_log_queue.is_empty():
		var next_log: Dictionary = pending_log_queue.pop_front()
		var chunk: Array[Dictionary] = [next_log]
		_append_logs_internal(chunk)
		emitted += 1


func rerender_views() -> void:
	_rerender_log_history()
	_render_mail_history()


func on_mail_selected(index: int) -> void:
	assert(index >= 0)
	assert(index < mail_items.size())
	selected_mail_index = index
	_render_selected_mail()


func _append_logs_internal(logs: Array[Dictionary]) -> void:
	assert(log_view != null)
	for item in logs:
		assert(item.has("level"))
		assert(item.has("event_key"))
		if _is_mail_feed_item(item):
			_collect_mail_notification(item)
			continue
		log_history.append(item)
		log_view.append_text(_format_log(item) + "\n")
	_render_mail_history()


func _rerender_log_history() -> void:
	assert(log_view != null)
	log_view.clear()
	for item in log_history:
		log_view.append_text(_format_log(item) + "\n")


func _format_log(item: Dictionary) -> String:
	assert(item.has("level"))
	assert(item.has("event_key"))
	var level: int = item["level"]
	var event_key: String = item["event_key"]
	var event_label := TranslationServer.translate(event_key)
	var message := _resolve_log_message(item)
	var color := _color_for_level(level)
	if event_key == "TITLE":
		return "[color=%s][b]%s[/b] %s[/color]" % [color, event_label, message]
	return "[color=%s][%s] %s[/color]" % [color, event_label, message]


func _resolve_log_message(item: Dictionary) -> String:
	if item.has("message_key"):
		assert(item.has("message_args"))
		var template := TranslationServer.translate(item["message_key"])
		var resolved_args: Array = []
		for arg in item["message_args"]:
			resolved_args.append(_resolve_log_arg(arg))
		if resolved_args.is_empty():
			return template
		return template % resolved_args
	assert(item.has("message"))
	return str(item["message"])


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
		_:
			assert(false, "Unknown log level")
	return Ui.TEXT.to_html(false)


func _is_mail_feed_item(item: Dictionary) -> bool:
	assert(item.has("event_key"))
	var event_key: String = item["event_key"]
	if event_key == "NOTIFIER":
		return true
	if event_key == "BOSS":
		return true
	if event_key in Constants.USER_KEYS_BY_ROUND:
		return true
	if event_key == Constants.PREVIOUS_USER_KEY_DEFAULT:
		return true
	return false


func _collect_mail_notification(item: Dictionary) -> void:
	assert(item.has("event_key"))
	if not _is_mail_feed_item(item):
		return
	var is_incident_notice: bool = item["event_key"] == "NOTIFIER"
	if is_incident_notice:
		_upsert_mail("notifier", "NOTIFIER", "MAIL_SUBJECT_NOTIFIER", item, false)
		return
	if item["event_key"] == "BOSS":
		_upsert_mail("boss", "BOSS", "MAIL_SUBJECT_BOSS", item, true)
		return
	_upsert_mail("colleague", "COLLEAGUE", "MAIL_SUBJECT_COLLEAGUE", item, true)


func _upsert_mail(
	bucket: String,
	sender_key: String,
	subject_key: String,
	body_item: Dictionary,
	merge_existing: bool
) -> void:
	assert(not bucket.is_empty())
	assert(not sender_key.is_empty())
	assert(not subject_key.is_empty())
	assert(not body_item.is_empty())
	if merge_existing:
		for index in range(mail_items.size()):
			if mail_items[index]["bucket"] != bucket:
				continue
			var body_items: Array = mail_items[index]["body_items"]
			body_items.append(body_item.duplicate(true))
			mail_items[index]["body_items"] = body_items
			mail_items[index]["updated_at"] = mail_updated_at_counter
			mail_updated_at_counter += 1
			var updated: Dictionary = mail_items[index]
			mail_items.remove_at(index)
			mail_items.append(updated)
			_sort_mail_items_by_time_desc()
			selected_mail_index = _index_for_bucket(bucket)
			return
	(
		mail_items
		. append(
			{
				"bucket": bucket,
				"sender_key": sender_key,
				"subject_key": subject_key,
				"body_items": [body_item.duplicate(true)],
				"updated_at": mail_updated_at_counter,
			}
		)
	)
	mail_updated_at_counter += 1
	_sort_mail_items_by_time_desc()
	if mail_items.size() > MAIL_HISTORY_LIMIT:
		mail_items.remove_at(mail_items.size() - 1)
	selected_mail_index = _index_for_bucket(bucket)


func _render_mail_history() -> void:
	assert(mail_list != null)
	assert(mail_detail_view != null)
	_sort_mail_items_by_time_desc()
	mail_list.clear()
	if mail_items.is_empty():
		selected_mail_index = -1
		mail_detail_view.clear()
		mail_detail_view.append_text(
			"[color=%s]%s[/color]\n" % [Ui.TEXT_DIM.to_html(false), _t("MAIL_EMPTY")]
		)
		return
	for item in mail_items:
		mail_list.add_item(_mail_list_title(item))
		mail_list.set_item_tooltip_enabled(mail_list.item_count - 1, false)
	if selected_mail_index < 0 or selected_mail_index >= mail_items.size():
		selected_mail_index = 0
	mail_list.select(selected_mail_index)
	_render_selected_mail()


func _mail_list_title(item: Dictionary) -> String:
	assert(item.has("sender_key"))
	assert(item.has("subject_key"))
	return "[%s] %s" % [TranslationServer.translate(item["sender_key"]), _t(item["subject_key"])]


func _render_selected_mail() -> void:
	assert(mail_detail_view != null)
	if mail_items.is_empty():
		mail_detail_view.clear()
		return
	assert(selected_mail_index >= 0)
	assert(selected_mail_index < mail_items.size())
	mail_detail_view.clear()
	mail_detail_view.append_text(_format_mail_item(mail_items[selected_mail_index]) + "\n")


func _format_mail_item(item: Dictionary) -> String:
	assert(item.has("sender_key"))
	assert(item.has("subject_key"))
	assert(item.has("body_items"))
	var sender_key: String = item["sender_key"]
	var sender := TranslationServer.translate(sender_key)
	var subject: String = _t(item["subject_key"])
	var body_items: Array = item["body_items"]
	var body_lines: Array[String] = []
	for raw_line_item in body_items:
		assert(raw_line_item is Dictionary)
		var line_item: Dictionary = raw_line_item
		body_lines.append(_resolve_log_message(line_item))
	var body: String = "\n".join(body_lines)
	return (
		(
			"[color=%s][b]%s[/b][/color] %s\n[color=%s][b]%s[/b][/color] %s\n"
			+ "[color=%s]%s[/color]"
		)
		% [
			Ui.COLOR_BLUE.to_html(false),
			_t("MAIL_FROM_LABEL"),
			sender,
			Ui.COLOR_YELLOW.to_html(false),
			_t("MAIL_SUBJECT_LABEL"),
			subject,
			Ui.TEXT.to_html(false),
			body,
		]
	)


func _sort_mail_items_by_time_desc() -> void:
	mail_items.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["updated_at"] > b["updated_at"]
	)


func _index_for_bucket(bucket: String) -> int:
	for index in range(mail_items.size()):
		if mail_items[index]["bucket"] == bucket:
			return index
	assert(false, "Mail bucket must exist after upsert")
	return -1
