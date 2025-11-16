extends Node
class_name BotDriver

@export var target: Node3D
@export var mount: CharacterBody3D
@onready var _logger = get_node("/root/LoggerInstance")
var _reported_no_mount := false
var _reported_no_target := false

func _ready() -> void:
	_logger.info("ai", self, "🤖 ready")
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

func _physics_process(delta: float) -> void:
	if target == null or mount == null:
		if mount == null and not _reported_no_mount:
			_logger.error("ai", self, "🤖 bot has no mount")
			_reported_no_mount = true
		if target == null and not _reported_no_target:
			_logger.warn("ai", self, "🎯 no target to chase")
			_reported_no_target = true
		return
	var dir := (target.global_transform.origin - mount.global_transform.origin)
	dir.y = 0.0
	if dir.length() > 0.1:
		dir = dir.normalized()
		# face target
		var desired_yaw := atan2(dir.x, dir.z)
		var yaw_delta := wrapf(desired_yaw - mount.rotation.y, -PI, PI)
		mount.rotation.y += clamp(yaw_delta, -1.0, 1.0) * delta
		# throttle forward
		var forward := -mount.transform.basis.z
		mount.velocity += forward * 4.0 * delta
		_logger.debug("ai", self, "👣 pursuing %s, yaw_delta=%.2f" % [target.name, yaw_delta])
