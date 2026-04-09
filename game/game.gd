class_name Game
extends RefCounted

enum RunState { BOOTING, RUNNING, ENDING }
enum AgentState { OK, DRIFTING, UNSTABLE, WAITING_REVIEW, OFFLINE }
enum Outcome { NONE, TIMEOUT, BUDGET, COLLAPSE, KPI }

var ticks: Ticks
var flow

var run_state: RunState = RunState.BOOTING
var round_index: int = 1
var time_left_seconds: int = 0
var budget: float = 0.0
var entropy: float = 0.0
var kpi: float = 0.0
var stability: float = 0.0
var model_intelligence: bool = true
var last_outcome: Outcome = Outcome.NONE
var outcome_history: Array[int] = []
var tick_accumulator_seconds: float = 0.0
var delayed_mail_tick_accumulator_seconds: float = 0.0
var elapsed_ticks: int = 0
var scheduler_cursor: int = 0

var goal: Dictionary = {}
var next_goal_id: int = 0

var agents: Array[Dictionary] = []
var active_incidents: Array[Dictionary] = []

var tasks: Dictionary = {}
var review_tickets: Dictionary = {}
var next_task_id: int = 0
var next_review_id: int = 0
var next_incident_id: int = 0
var next_agent_suffix: int = 0
var pending_delayed_mail_logs: Array[Dictionary] = []


func _init() -> void:
	ticks = Ticks.new()
	flow = preload("res://game/flow.gd").new()
	seed(Constants.RANDOM_SEED)
	start_round(Constants.INITIAL_ROUND_INDEX)


func start_round(new_round_index: int) -> void:
	assert(new_round_index >= 1)
	assert(new_round_index <= Constants.TOTAL_ROUNDS)
	round_index = new_round_index
	run_state = RunState.BOOTING
	time_left_seconds = Constants.ROUND_DURATION_SECONDS
	budget = Constants.INITIAL_BUDGET
	entropy = Constants.INITIAL_ENTROPY
	kpi = Constants.INITIAL_KPI
	stability = Constants.INITIAL_STABILITY
	model_intelligence = Constants.INITIAL_MODEL_INTELLIGENCE
	last_outcome = Outcome.NONE
	tick_accumulator_seconds = 0.0
	delayed_mail_tick_accumulator_seconds = 0.0
	elapsed_ticks = 0
	scheduler_cursor = 0

	next_goal_id = Constants.INITIAL_GOAL_ID
	next_task_id = Constants.INITIAL_TASK_ID
	next_review_id = Constants.INITIAL_REVIEW_ID
	next_incident_id = Constants.INITIAL_INCIDENT_ID
	next_agent_suffix = Constants.INITIAL_AGENT_SUFFIX
	pending_delayed_mail_logs.clear()

	goal = {
		"id": "goal-%d" % next_goal_id,
		"kpi_baseline": kpi,
		"kpi_target": Constants.KPI_TARGET,
		"deadline_tick": Constants.ROUND_DURATION_SECONDS,
		"status": Constants.GOAL_STATUS_ACTIVE,
	}
	next_goal_id += 1
	tasks.clear()
	review_tickets.clear()
	active_incidents.clear()
	agents.clear()
	for agent_seed in Constants.INITIAL_AGENT_SEEDS:
		agents.append(_make_agent(agent_seed["id"], agent_seed["type"]))


func finish_boot() -> void:
	assert(run_state == RunState.BOOTING)
	assert(not goal.is_empty())
	run_state = RunState.RUNNING


func has_more_rounds() -> bool:
	assert(round_index >= 1)
	assert(round_index <= Constants.TOTAL_ROUNDS)
	return round_index < Constants.TOTAL_ROUNDS


func begin_next_round() -> void:
	assert(has_more_rounds())
	start_round(round_index + 1)


func current_user_key() -> String:
	assert(round_index >= 1)
	assert(round_index <= Constants.USER_KEYS_BY_ROUND.size())
	return Constants.USER_KEYS_BY_ROUND[round_index - 1]


func previous_user_key() -> String:
	assert(round_index >= 1)
	if round_index == 1:
		return Constants.PREVIOUS_USER_KEY_DEFAULT
	return Constants.USER_KEYS_BY_ROUND[round_index - 2]


func get_status_snapshot() -> Dictionary:
	assert(not goal.is_empty())
	return {
		"stability": stability,
		"budget": budget,
		"entropy": entropy,
		"kpi": kpi,
		"time_left_seconds": time_left_seconds,
		"model_intelligence": model_intelligence,
		"active_incidents": active_incidents.size(),
		"pending_reviews": flow._pending_review_count(self),
		"round_index": round_index,
		"goal_status": goal["status"],
		"goal_target": goal["kpi_target"],
	}


func get_goal_snapshot() -> Dictionary:
	assert(not goal.is_empty())
	return goal.duplicate(true)


func get_agent_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for agent in agents:
		assert(agent.has("id"))
		assert(agent.has("type"))
		assert(agent.has("task_queue_ids"))
		snapshot.append(agent.duplicate(true))
	return snapshot


func get_incident_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for incident in active_incidents:
		assert(incident.has("id"))
		assert(incident.has("type"))
		assert(incident.has("agent_id"))
		snapshot.append(incident.duplicate(true))
	return snapshot


func get_task_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for task_id in tasks.keys():
		var task: Dictionary = tasks[task_id]
		assert(task.has("id"))
		snapshot.append(task.duplicate(true))
	return snapshot


func inspect_target(target: String) -> Dictionary:
	assert(not target.is_empty())
	if target == "goal":
		var goal_payload: Dictionary = get_goal_snapshot()
		goal_payload["queues"] = flow._queue_snapshot(self)
		return {"kind": "goal", "value": goal_payload}

	var agent_index: int = flow._find_agent_index_by_target(self, target)
	if agent_index >= 0:
		var agent_payload: Dictionary = agents[agent_index].duplicate(true)
		agent_payload["active_incidents"] = flow._incident_ids_for_agent(self, agent_payload["id"])
		agent_payload["queue_tasks"] = flow._task_payloads_for_queue(
			self, agent_payload["task_queue_ids"]
		)
		return {"kind": "agent", "value": agent_payload}

	var incident_index: int = flow._find_incident_index_by_target(self, target)
	if incident_index >= 0:
		return {"kind": "incident", "value": active_incidents[incident_index].duplicate(true)}

	if tasks.has(target):
		return {"kind": "task", "value": tasks[target].duplicate(true)}

	return {}


func advance_time(delta_seconds: float) -> Array[Dictionary]:
	assert(delta_seconds >= 0.0)
	return ticks.advance(self, delta_seconds)


func advance_delayed_mail(delta_seconds: float) -> Array[Dictionary]:
	assert(delta_seconds >= 0.0)
	var events: Array[Dictionary] = []
	delayed_mail_tick_accumulator_seconds += delta_seconds
	while delayed_mail_tick_accumulator_seconds >= Constants.TICK_SECONDS:
		delayed_mail_tick_accumulator_seconds -= Constants.TICK_SECONDS
		_dispatch_delayed_mail_logs(events)
	return events


func queue_delayed_mail_logs(logs: Array[Dictionary], delay_seconds: int) -> void:
	assert(delay_seconds >= 0)
	for item in logs:
		assert(item.has("event_key"))
		assert(item.has("level"))
		(
			pending_delayed_mail_logs
			. append(
				{
					"delay_ticks": delay_seconds,
					"log": item.duplicate(true),
				}
			)
		)


func _dispatch_delayed_mail_logs(events: Array[Dictionary]) -> void:
	if pending_delayed_mail_logs.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for queued in pending_delayed_mail_logs:
		assert(queued.has("delay_ticks"))
		assert(queued.has("log"))
		var delay_ticks: int = int(queued["delay_ticks"]) - 1
		if delay_ticks > 0:
			queued["delay_ticks"] = delay_ticks
			remaining.append(queued)
			continue
		events.append({"type": "mail_delivered", "log": queued["log"]})
	pending_delayed_mail_logs = remaining


func start_patch_for_agent(target: String) -> Dictionary:
	var index: int = flow._find_agent_index_by_target(self, target)
	if index < 0:
		return {"ok": false}
	var agent: Dictionary = agents[index]
	if not agent["online"]:
		return {"ok": false}
	if agent["is_patching"]:
		return {"ok": false}
	var incident_index: int = flow._patchable_incident_index_for_agent(self, agent["id"])
	agent["is_patching"] = true
	agent["patch_ticks_remaining"] = Constants.INCIDENT_PATCH_DURATION_TICKS
	agents[index] = agent
	var incident := {}
	if incident_index >= 0:
		incident = active_incidents[incident_index]
	return {
		"ok": true,
		"target": agent["id"],
		"incident_id": "" if incident_index < 0 else incident["id"],
		"incident": "" if incident_index < 0 else incident["type"],
		"patched_incident_present": incident_index >= 0,
		"duration_ticks": Constants.INCIDENT_PATCH_DURATION_TICKS,
	}


func run_agent(agent_type: String) -> String:
	assert(agent_type in Constants.AGENT_TYPES)
	for index in range(agents.size()):
		var existing: Dictionary = agents[index]
		if existing["type"] != agent_type:
			continue
		if existing["online"]:
			continue
		existing["online"] = true
		existing["state"] = AgentState.OK
		existing["is_patching"] = false
		existing["patch_ticks_remaining"] = 0
		agents[index] = existing
		return existing["id"]

	var current_type_count := 0
	for agent in agents:
		if agent["type"] == agent_type:
			current_type_count += 1
	var new_id := "%s-%d" % [agent_type.to_lower(), current_type_count + 1]
	agents.append(_make_agent(new_id, agent_type))
	return new_id


func kill_agent(target: String) -> Dictionary:
	var index: int = flow._find_agent_index_by_target(self, target)
	if index < 0:
		return {"ok": false, "events": []}

	var agent: Dictionary = agents[index]
	agent["online"] = false
	agent["state"] = AgentState.OFFLINE
	agent["is_patching"] = false
	agent["patch_ticks_remaining"] = 0
	agents[index] = agent

	var events: Array[Dictionary] = []
	var canceled_tasks: Array[Dictionary] = flow._cancel_tasks_for_agent(
		self, agent["id"], "agent_killed"
	)
	for task in canceled_tasks:
		(
			events
			. append(
				{
					"type": "task_canceled",
					"task_id": task["id"],
					"target": task["agent_id"],
					"reason": "agent_killed",
				}
			)
		)
		var replanned: Dictionary = flow._replan_for_canceled_task(self, task, "agent_killed")
		if replanned["ok"]:
			var replacement: Dictionary = replanned["task"]
			(
				events
				. append(
					{
						"type": "task_replanned",
						"from_task_id": task["id"],
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
						"task_id": task["id"],
						"reason": replanned["reason"],
					}
				)
			)

	events.append({"type": "agent_killed", "target": agent["id"]})
	return {"ok": true, "events": events, "target": agent["id"]}


func toggle_agent_flag(target: String, field: String) -> Dictionary:
	var index: int = flow._find_agent_index_by_target(self, target)
	if index < 0:
		return {"ok": false}
	var agent: Dictionary = agents[index]
	assert(agent.has(field))
	agent[field] = not agent[field]
	agents[index] = agent
	return {"ok": true, "target": agent["id"]}


func _make_agent(agent_id: String, agent_type: String) -> Dictionary:
	assert(agent_type in Constants.AGENT_TYPES)
	return {
		"id": agent_id,
		"type": agent_type,
		"online": true,
		"state": AgentState.OK,
		"trusted": false,
		"muted": false,
		"has_pending_review": false,
		"pending_review_id": "",
		"pending_review": {},
		"is_patching": false,
		"patch_ticks_remaining": 0,
		"reviews_created": 0,
		"reviews_rejected": 0,
		"auto_reviews": 0,
		"retries": 0,
		"failures": 0,
		"task_queue_ids": [],
	}
