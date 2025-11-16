extends Node
class_name BotDriver

@export var target: Node3D
@export var mount: CharacterBody3D
@onready var _logger = get_node("/root/LoggerInstance")
var _reported_no_mount := false
var _reported_no_target := false
const LOG_INTERVAL: float = 0.25
var _log_elapsed: float = 0.0
const MAX_SPEED: float = 20.0

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
	if mount and not (mount is CharacterBody3D):
		_logger.error("ai", self, "Mount export is not a CharacterBody3D")
		mount = null

func _physics_process(delta: float) -> void:
	if target == null or mount == null:
		if mount == null and not _reported_no_mount:
			_logger.error("ai", self, "🤖 bot has no mount")
			_reported_no_mount = true
		if target == null and not _reported_no_target:
			_logger.warn("ai", self, "🎯 no target to chase")
			_reported_no_target = true
		return
	# compute planar direction to target
	var mount_pos: Vector3 = mount.global_transform.origin
	var target_pos: Vector3 = target.global_transform.origin
	var dir: Vector3 = target_pos - mount_pos
	dir.y = 0.0
	var dist: float = dir.length()
	if dist > 0.001:
		dir = dir.normalized()
		# face target
		var desired_yaw: float = atan2(dir.x, dir.z)
		var yaw_delta: float = wrapf(desired_yaw - mount.rotation.y, -PI, PI)
		var yaw_step: float = clamp(yaw_delta, -1.0, 1.0) * delta
		mount.rotation.y += yaw_step
		# throttle forward toward target
		var forward: Vector3 = -mount.transform.basis.z
		var accel: float = 4.0
		mount.velocity += forward * accel * delta
		# clamp velocity for safety
		if mount.velocity.length() > MAX_SPEED:
			_logger.warn("ai", self, "Speed clamped from %.2f to %.2f" % [mount.velocity.length(), MAX_SPEED])
			mount.velocity = mount.velocity.normalized() * MAX_SPEED
		# periodic decision log
		_log_elapsed += delta
		if _log_elapsed >= LOG_INTERVAL:
			_log_elapsed = 0.0
			var speed: float = mount.velocity.dot(forward)
			_logger.info("ai", self, "🎯 intent=chase dist=%.2f yaw_delta=%.2f yaw_step=%.3f speed=%.2f accel=%.2f mount_pos=%s target_pos=%s" % [dist, yaw_delta, yaw_step, speed, accel, str(mount_pos), str(target_pos)])
