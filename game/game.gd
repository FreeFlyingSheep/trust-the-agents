class_name Game
extends RefCounted

enum RunState { BOOTING, RUNNING, ENDING }
enum AgentState { OK, DRIFTING, UNSTABLE, WAITING_REVIEW, OFFLINE }
enum Outcome { NONE, TIMEOUT, BUDGET, COLLAPSE, KPI }

var commands: Commands
var ticks: Ticks

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
var active_incidents: Array[Dictionary] = []
var agents: Array[Dictionary] = []
var next_review_id: int = 0
var next_incident_id: int = 0
var next_agent_suffix: int = 0
var tick_accumulator_seconds: float = 0.0


func _init() -> void:
	commands = Commands.new()
	ticks = Ticks.new()
	seed(Constants.RANDOM_SEED)
	start_round(Constants.INITIAL_ROUND_INDEX)


func start_round(new_round_index: int) -> void:
	round_index = new_round_index
	run_state = RunState.BOOTING
	time_left_seconds = Constants.ROUND_DURATION_SECONDS
	budget = Constants.INITIAL_BUDGET
	entropy = Constants.INITIAL_ENTROPY
	kpi = Constants.INITIAL_KPI
	stability = Constants.INITIAL_STABILITY
	model_intelligence = Constants.INITIAL_MODEL_INTELLIGENCE
	active_incidents.clear()
	next_review_id = Constants.INITIAL_REVIEW_ID
	next_incident_id = Constants.INITIAL_INCIDENT_ID
	next_agent_suffix = Constants.INITIAL_AGENT_SUFFIX
	tick_accumulator_seconds = 0.0
	agents.clear()
	for agent_seed in Constants.INITIAL_AGENT_SEEDS:
		agents.append(_make_agent(str(agent_seed["id"]), str(agent_seed["type"])))


func finish_boot() -> void:
	run_state = RunState.RUNNING


func has_more_rounds() -> bool:
	return round_index < Constants.TOTAL_ROUNDS


func begin_next_round() -> void:
	start_round(round_index + 1)


func current_user_key() -> String:
	if round_index <= 0:
		return Constants.USER_KEYS_BY_ROUND[0]
	if round_index > Constants.USER_KEYS_BY_ROUND.size():
		return Constants.USER_KEYS_BY_ROUND[Constants.USER_KEYS_BY_ROUND.size() - 1]
	return Constants.USER_KEYS_BY_ROUND[round_index - 1]


func previous_user_key() -> String:
	if round_index <= 1:
		return Constants.PREVIOUS_USER_KEY_DEFAULT
	return Constants.USER_KEYS_BY_ROUND[round_index - 2]


func get_status_snapshot() -> Dictionary:
	return {
		"stability": stability,
		"budget": budget,
		"entropy": entropy,
		"kpi": kpi,
		"time_left_seconds": time_left_seconds,
		"model_intelligence": model_intelligence,
		"active_incidents": active_incidents.size(),
		"pending_reviews": _pending_review_count(),
		"round_index": round_index,
	}


func get_agent_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for agent in agents:
		snapshot.append(agent.duplicate(true))
	return snapshot


func get_incident_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for incident in active_incidents:
		snapshot.append(incident.duplicate(true))
	return snapshot


func inspect_target(target: String) -> Dictionary:
	var agent := _find_agent(target)
	if not agent.is_empty():
		var agent_payload := agent.duplicate(true)
		agent_payload["active_incident"] = _active_incident_for_agent_type(agent.type)
		return {
			"kind": "agent",
			"value": agent_payload,
		}

	var incident := _find_incident(target)
	if not incident.is_empty():
		return {
			"kind": "incident",
			"value": incident.duplicate(true),
		}

	return {}


func perform_command(command: String, target: String = "") -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"events": [],
	}
	if run_state != RunState.RUNNING:
		return result

	var command_result: Dictionary = commands.apply(self, command, target)
	result.ok = command_result.ok
	result.events.append_array(command_result.events)
	return result


func advance_time(delta_seconds: float) -> Array[Dictionary]:
	return ticks.advance(self, delta_seconds)


func _make_agent(agent_id: String, agent_type: String) -> Dictionary:
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
		"reviews_created": 0,
		"reviews_rejected": 0,
		"auto_reviews": 0,
		"retries": 0,
		"failures": 0,
	}


func _find_agent(target: String) -> Dictionary:
	for agent in agents:
		if agent.id == target or agent.type.to_lower() == target.to_lower():
			return agent
	return {}


func _find_incident(target: String) -> Dictionary:
	for incident in active_incidents:
		if incident.id == target or incident.type == target:
			return incident
	return {}


func _apply_review_result(review: Dictionary, approved: bool) -> void:
	if approved:
		if review.is_actually_good:
			kpi += Constants.REVIEW_APPROVE_GOOD_KPI_GAIN
		else:
			stability -= Constants.REVIEW_APPROVE_BAD_STABILITY_LOSS
	elif review.is_actually_good:
		stability -= Constants.REVIEW_DENY_GOOD_STABILITY_LOSS


func _apply_review_metrics(agent: Dictionary, review: Dictionary, approved: bool) -> void:
	if not approved:
		agent.reviews_rejected += 1
	if (not approved) or (not review.is_actually_good):
		agent.failures += 1


func _active_incident_for_agent_type(agent_type: String) -> String:
	for incident in active_incidents:
		if incident["target_agent_type"] == agent_type:
			return str(incident["type"])
	return ""


func _pending_review_count() -> int:
	var total := 0
	for agent in agents:
		if agent.has_pending_review:
			total += 1
	return total


func is_agent_muted(agent_id: String) -> bool:
	for agent in agents:
		if agent.id == agent_id:
			return agent.muted
	return false
