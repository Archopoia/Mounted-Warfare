extends Node3D
class_name WeaponAttachment

## Weapon type identifier (rocket_launcher, mine_layer, autocannon, etc.)
@export var weapon_type: String = "rocket_launcher"
## Weapon display name
@export var weapon_name: String = "Rocket Launcher"
## Color for the weapon visual representation
@export var weapon_color: Color = Color(1.0, 0.5, 0.0, 1.0)
## Weapon size scale (for visual representation)
@export var weapon_scale: float = 0.5
## Maximum ammunition capacity for this weapon
@export var max_ammo: int = 30
## Current ammunition count
@export var current_ammo: int = 30

## Signal emitted when ammo changes (new_ammo, max_ammo)
signal ammo_changed(new_ammo: int, max_ammo: int)
## Signal emitted when ammo is depleted (weapon_type)
signal ammo_depleted(weapon_type: String)

var _logger: Node
var _attached_to_mount: Node = null

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	_update_visuals()
	
	# Initialize ammo if not already set
	if max_ammo == 30 and current_ammo == 30:  # Default values, initialize from registry
		max_ammo = WeaponRegistry.get_max_ammo(weapon_type)
		current_ammo = max_ammo
	
	_logger.info("weapon", self, "⚔️ weapon attachment ready: type=%s, ammo=%d/%d" % [weapon_type, current_ammo, max_ammo])

func _update_visuals() -> void:
	# Update material colors for all mesh instances to match weapon color
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = weapon_color
	material.emission_enabled = true
	material.emission = weapon_color * 0.3
	
	# Update all MeshInstance3D children to use the weapon color
	for child in get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			mesh_instance.set_surface_override_material(0, material)

func attach_to_mount(mount: Node, marker: Marker3D) -> void:
	if _attached_to_mount != null:
		_logger.warn("weapon", self, "⚠️ weapon already attached to mount")
		return
	
	if marker == null:
		_logger.error("weapon", self, "❌ Failed to attach weapon: marker is null")
		return
	
	_attached_to_mount = mount
	
	# Reparent to the marker node
	if is_inside_tree():
		var old_parent: Node = get_parent()
		if old_parent != null:
			old_parent.remove_child(self)
	
	marker.add_child(self)
	
	# Reset transform to be relative to marker (weapon should be at marker origin)
	transform = Transform3D.IDENTITY
	
	_logger.info("weapon", self, "🔗 weapon attached to mount: type=%s, marker=%s" % [weapon_type, marker.name])

func detach_from_mount() -> void:
	if _attached_to_mount == null:
		return
	
	_logger.info("weapon", self, "🔓 weapon detached from mount: type=%s" % weapon_type)
	_attached_to_mount = null
	
	# Remove weapon from scene
	# Note: If the weapon was already removed from its parent (e.g., by replace_weapon_in_slot),
	# queue_free() will still work correctly to clean up the node
	queue_free()

func attack() -> void:
	if _attached_to_mount == null:
		_logger.error("weapon", self, "❌ Cannot attack: weapon not attached to mount")
		return
	
	if not is_inside_tree():
		_logger.error("weapon", self, "❌ Cannot attack: weapon not in scene tree")
		return
	
	# Check ammo
	var projectile_count: int = WeaponRegistry.get_projectile_count(weapon_type)
	if current_ammo < projectile_count:
		_logger.info("weapon", self, "⚠️ out of ammo: current=%d, needed=%d" % [current_ammo, projectile_count])
		if current_ammo == 0:
			ammo_depleted.emit(weapon_type)
		return
	
	_logger.info("weapon", self, "💥 attacking with weapon: type=%s, name=%s, ammo=%d/%d" % [weapon_type, weapon_name, current_ammo, max_ammo])
	
	# Get projectile spawn position and direction
	var mount: RigidBody3D = _attached_to_mount as RigidBody3D
	if mount == null:
		_logger.error("weapon", self, "❌ Cannot attack: mount is not a RigidBody3D")
		return
	
	# Calculate spawn position (weapon position + forward offset)
	var spawn_position: Vector3 = global_position
	var forward: Vector3 = -mount.global_transform.basis.z  # Mount's forward direction
	
	# Log weapon-specific attack
	match weapon_type:
		"rocket_launcher":
			_logger.debug("weapon", self, "🚀 firing rocket launcher")
		"mine_layer":
			_logger.debug("weapon", self, "💣 deploying mine layer")
		"autocannon":
			_logger.debug("weapon", self, "🔫 firing autocannon burst")
		_:
			_logger.warn("weapon", self, "⚠️ unknown weapon type for attack: %s" % weapon_type)
	
	# Spawn projectiles
	for i in range(projectile_count):
		_spawn_projectile(spawn_position, forward, i, projectile_count)
	
	# Consume ammo
	current_ammo -= projectile_count
	_logger.info("weapon", self, "🎯 fired %d projectiles, ammo remaining: %d/%d" % [projectile_count, current_ammo, max_ammo])
	
	# Emit ammo changed signal
	ammo_changed.emit(current_ammo, max_ammo)
	
	# Check if ammo is depleted
	if current_ammo <= 0:
		ammo_depleted.emit(weapon_type)
		_logger.info("weapon", self, "⚠️ weapon ammo depleted: %s" % weapon_type)

func _spawn_projectile(spawn_position: Vector3, direction: Vector3, index: int, total_count: int) -> void:
	# Load projectile scene based on weapon type
	var projectile_scene_path: String = WeaponRegistry.get_projectile_scene_path(weapon_type)
	var projectile_scene: PackedScene = load(projectile_scene_path)
	
	if projectile_scene == null:
		_logger.error("weapon", self, "❌ Failed to load projectile scene: %s" % projectile_scene_path)
		return
	
	# Instantiate projectile
	var projectile_instance: Node = projectile_scene.instantiate()
	if projectile_instance == null or not projectile_instance is Projectile:
		_logger.error("weapon", self, "❌ Failed to instantiate projectile")
		return
	
	var projectile: Projectile = projectile_instance as Projectile
	
	# Add to scene tree
	var scene_root: Node = get_tree().root
	if scene_root == null:
		_logger.error("weapon", self, "❌ Cannot spawn projectile: scene root is null")
		return
	
	scene_root.add_child(projectile)
	
	# Position projectile
	projectile.global_position = spawn_position
	
	# Apply burst spread for autocannon
	var fire_direction: Vector3 = direction
	if total_count > 1:
		var spread_angle: float = deg_to_rad((index - (total_count - 1) / 2.0) * 3.0)  # 3 degree spread per projectile
		var right: Vector3 = direction.cross(Vector3.UP).normalized()
		if right.length() < 0.1:
			right = Vector3.RIGHT
		fire_direction = direction.rotated(right, spread_angle).normalized()
	
	# Initialize projectile
	projectile.initialize(fire_direction, _attached_to_mount, weapon_type)
	
	_logger.debug("weapon", self, "🚀 projectile spawned: pos=%s, dir=%s" % [spawn_position, fire_direction])

