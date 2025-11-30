extends RigidBody3D
class_name Projectile

## Projectile speed in units per second
@export var speed: float = 20.0
## Damage dealt on impact
@export var damage: float = 10.0
## Projectile lifetime in seconds (0 = infinite)
@export var lifetime: float = 100.0
## Explosion radius for splash damage (0 = no splash)
@export var explosion_radius: float = 0.0
## Precision spread in degrees (0 = perfectly accurate)
@export var precision_spread: float = 0.0
## Projectile visual color
@export var projectile_color: Color = Color.WHITE
## Projectile scale
@export var projectile_scale: float = 1.0

var _logger: Node
var _initial_velocity: Vector3 = Vector3.ZERO
var _owner: Node = null
var _weapon_type: String = ""

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	
	# Set up physics
	freeze = false
	sleeping = false
	
	# Set up visuals
	_setup_visuals()
	
	# Set up collision detection
	# RigidBody3D uses body_shape_entered signal, not body_entered
	contact_monitor = true
	max_contacts_reported = 10
	if not body_shape_entered.is_connected(_on_body_shape_entered):
		body_shape_entered.connect(_on_body_shape_entered)
	
	# Apply initial velocity after a frame (ensures physics is ready)
	call_deferred("_apply_initial_velocity")
	
	if _logger != null:
		_logger.info("projectile", self, "🚀 projectile spawned: type=%s, speed=%.2f, damage=%.1f, gravity=%.2f" % [_weapon_type, speed, damage, gravity_scale])
	
	# Set up lifetime timer
	if lifetime > 0.0:
		var timer: Timer = Timer.new()
		timer.wait_time = lifetime
		timer.one_shot = true
		timer.timeout.connect(_on_lifetime_expired)
		add_child(timer)
		timer.start()
		_logger.debug("projectile", self, "⏱️ lifetime timer set: %.2f seconds" % lifetime)

func _apply_initial_velocity() -> void:
	if _initial_velocity != Vector3.ZERO:
		linear_velocity = _initial_velocity
		_logger.debug("projectile", self, "📏 initial velocity applied: %s" % _initial_velocity)

func _setup_visuals() -> void:
	# Create or update mesh instance with projectile visual
	var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "MeshInstance3D"
		add_child(mesh_instance)
	
	# Create material with projectile color
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = projectile_color
	material.emission_enabled = true
	material.emission = projectile_color * 0.5
	
	# If mesh doesn't exist, create default sphere
	if mesh_instance.mesh == null:
		var sphere_mesh: SphereMesh = SphereMesh.new()
		sphere_mesh.radius = 0.1 * projectile_scale
		sphere_mesh.height = 0.2 * projectile_scale
		mesh_instance.mesh = sphere_mesh
	
	mesh_instance.set_surface_override_material(0, material)

func initialize(direction: Vector3, owner_node: Node, weapon_type_str: String) -> void:
	if direction == Vector3.ZERO:
		_logger.error("projectile", self, "❌ Cannot initialize projectile: direction is zero")
		return
	
	if owner_node == null:
		_logger.error("projectile", self, "❌ Cannot initialize projectile: owner is null")
		return
	
	_owner = owner_node
	_weapon_type = weapon_type_str
	
	# Calculate initial velocity with precision spread
	var spread_direction: Vector3 = _apply_precision_spread(direction)
	_initial_velocity = spread_direction * speed
	
	_logger.debug("projectile", self, "📐 initialized: dir=%s, spread_dir=%s, vel=%s" % [direction, spread_direction, _initial_velocity])
	
	# Apply initial velocity if ready (otherwise will be applied in _apply_initial_velocity)
	if is_inside_tree() and is_physics_processing():
		linear_velocity = _initial_velocity

func _apply_precision_spread(direction: Vector3) -> Vector3:
	if precision_spread <= 0.0:
		return direction.normalized()
	
	# Generate random spread within precision_spread degrees
	var spread_angle: float = deg_to_rad(randf_range(-precision_spread, precision_spread))
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	if right.length() < 0.1:
		right = Vector3.RIGHT
	
	var up: Vector3 = direction.cross(right).normalized()
	var spread_direction: Vector3 = direction.normalized()
	spread_direction = spread_direction.rotated(right, spread_angle)
	spread_direction = spread_direction.rotated(up, randf_range(-PI, PI) * precision_spread / 180.0)
	
	return spread_direction.normalized()

func _integrate_forces(_state: PhysicsDirectBodyState3D) -> void:
	# Note: RigidBody3D already handles gravity via gravity_scale property
	# This is here for custom gravity effects if needed in the future
	# The built-in gravity_scale property is sufficient for most cases
	pass

func _on_lifetime_expired() -> void:
	_logger.debug("projectile", self, "⏱️ projectile lifetime expired")
	_explode_or_destroy()

func _on_body_shape_entered(_body_rid: RID, body: Node3D, body_shape_index: int, _local_shape_index: int) -> void:
	if body == null:
		return
	
	# Don't collide with owner
	if body == _owner:
		return
	
	# Don't collide with other projectiles
	if body is Projectile:
		return
	
	# Don't collide with weapon attachments
	if body is WeaponAttachment:
		return
	
	_logger.info("projectile", self, "💥 projectile hit: %s (shape_index=%d)" % [body.name, body_shape_index])
	
	# Apply damage and explode
	_apply_damage(body)
	_explode_or_destroy()

func _apply_damage(target: Node3D) -> void:
	# TODO: Implement actual damage system
	_logger.info("projectile", self, "⚔️ applying damage: %.1f to %s" % [damage, target.name])
	
	# If explosion radius > 0, apply splash damage
	if explosion_radius > 0.0:
		_apply_splash_damage()
	else:
		# Direct hit damage
		_logger.debug("projectile", self, "🎯 direct hit: %.1f damage" % damage)

func _apply_splash_damage() -> void:
	_logger.debug("projectile", self, "💣 applying splash damage: radius=%.2f, damage=%.1f" % [explosion_radius, damage])
	# TODO: Find all targets within explosion_radius and apply damage

func _explode_or_destroy() -> void:
	# TODO: Spawn explosion effect here
	_logger.debug("projectile", self, "💥 projectile destroyed")
	queue_free()
