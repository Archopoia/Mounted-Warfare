extends Node
class_name BotDriver

@export var target: Node3D
@export var mount: CharacterBody3D
@onready var _services: Node = get_node_or_null("/root/Services")
@onready var _logger = _services.logger() if _services != null else get_node_or_null("/root/LoggerInstance")
@onready var _bus: Node = _services.bus() if _services != null else get_node_or_null("/root/EventBus")
@onready var _utility: Node = preload("res://scripts/ai/utility/utility_ai.gd").new()
@onready var _executor: Node = preload("res://scripts/ai/utility/behavior_executor.gd").new()
var _reported_no_mount := false
var _reported_no_target := false
const LOG_INTERVAL: float = 0.35
var _log_elapsed: float = 0.0
var _last_behavior: String = "idle"

func _ready() -> void:
	_logger.info("ai", self, "🤖 utility AI ready")
	if target == null:
		var p := get_tree().get_first_node_in_group("players")
		if p and p is Node3D:
			target = p
			_logger.info("ai", self, "🎯 target set to %s" % p.name)
		else:
			_logger.warn("ai", self, "⚠️ no player found in group 'players'")
	var mount_parent := get_parent()
	if mount == null and mount_parent and mount_parent is CharacterBody3D:
		mount = mount_parent
		_logger.info("ai", self, "🐎 mount set to parent %s" % mount_parent.name)
	if mount and not (mount is CharacterBody3D):
		_logger.error("ai", self, "Mount export is not a CharacterBody3D")
		mount = null
	# keep helpers as children so they can be freed with us
	add_child(_utility)
	add_child(_executor)

func _exit_tree() -> void:
	# Nothing dynamic to disconnect yet; helpers are children and will free
	pass

func _physics_process(delta: float) -> void:
	if target == null or mount == null:
		if mount == null and not _reported_no_mount:
			_logger.error("ai", self, "🤖 bot has no mount")
			_reported_no_mount = true
		if target == null and not _reported_no_target:
			_logger.warn("ai", self, "🎯 no target available")
			_reported_no_target = true
		return
	var ctx := {
		"mount": mount,
		"target": target,
		"logger": _logger,
		"bus": _bus
	}
	var scores: Dictionary = _utility.call("evaluate_scores", ctx)
	var choice: String = _utility.call("select_best", scores)
	_executor.call("execute", choice, ctx, delta)
	_log_elapsed += delta
	if _log_elapsed >= LOG_INTERVAL:
		_log_elapsed = 0.0
		if _bus and _bus.has_method("emit_ai_decision"):
			_bus.emit_ai_decision(name, choice)
		if _bus and _bus.has_method("emit_ai_scores"):
			_bus.emit_ai_scores(name, scores)
		if choice != _last_behavior:
			_logger.info("ai", self, "🎯 chose=%s scores=%s" % [choice, JSON.stringify(scores)])
			_last_behavior = choice
