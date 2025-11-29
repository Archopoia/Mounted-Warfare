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
var _is_charging_secondary: bool = false
var _charge_time: float = 0.0
var _charged_ammo_consumed: int = 0
var _fractional_ammo_accumulator: float = 0.0  # Accumulate fractional ammo consumption
var _mesh_instances: Array[MeshInstance3D] = []  # Cache mesh instances for visual feedback
var _base_materials: Array[StandardMaterial3D] = []  # Cache base materials
var _flicker_tween: Tween = null

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	_collect_mesh_instances()
	_update_visuals()
	
	# Initialize ammo if not already set
	if max_ammo == 30 and current_ammo == 30:  # Default values, initialize from registry
		max_ammo = WeaponRegistry.get_max_ammo(weapon_type)
		current_ammo = max_ammo
	
	_logger.info("weapon", self, "⚔️ weapon attachment ready: type=%s, ammo=%d/%d" % [weapon_type, current_ammo, max_ammo])

func _collect_mesh_instances() -> void:
	# Recursively collect all MeshInstance3D nodes
	_mesh_instances.clear()
	_collect_mesh_instances_recursive(self)

func _collect_mesh_instances_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		_mesh_instances.append(node as MeshInstance3D)
	
	for child in node.get_children():
		_collect_mesh_instances_recursive(child)

func _update_visuals() -> void:
	# Update material colors for all mesh instances to match weapon color
	_base_materials.clear()
	
	for mesh_instance in _mesh_instances:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = weapon_color
		material.emission_enabled = true
		material.emission = weapon_color * 0.3
		mesh_instance.set_surface_override_material(0, material)
		_base_materials.append(material)

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
	
	# Re-collect mesh instances after reparenting
	_collect_mesh_instances()
	
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
	
	# Visual feedback for primary attack
	_flicker_weapon_red()
	
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
	var old_ammo: int = current_ammo
	current_ammo -= projectile_count
	_logger.info("weapon", self, "🎯 fired %d projectiles, ammo: %d -> %d/%d" % [projectile_count, old_ammo, current_ammo, max_ammo])
	
	# Emit ammo changed signal
	_logger.debug("weapon", self, "📡 emitting ammo_changed signal: current_ammo=%d, max_ammo=%d" % [current_ammo, max_ammo])
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

## Fire projectiles without consuming ammo (used for upgraded weapons)
func fire_without_consuming_ammo() -> void:
	if _attached_to_mount == null:
		_logger.error("weapon", self, "❌ Cannot fire: weapon not attached to mount")
		return
	
	if not is_inside_tree():
		_logger.debug("weapon", self, "⚠️ Cannot fire: weapon not in scene tree (may have been dropped during attack)")
		return
	
	# Get projectile spawn position and direction
	var mount: RigidBody3D = _attached_to_mount as RigidBody3D
	if mount == null:
		_logger.error("weapon", self, "❌ Cannot fire: mount is not a RigidBody3D")
		return
	
	# Calculate spawn position (weapon position + forward offset)
	var spawn_position: Vector3 = global_position
	var forward: Vector3 = -mount.global_transform.basis.z  # Mount's forward direction
	
	# Get projectile count
	var projectile_count: int = WeaponRegistry.get_projectile_count(weapon_type)
	
	# Spawn projectiles without consuming ammo
	for i in range(projectile_count):
		_spawn_projectile(spawn_position, forward, i, projectile_count)
	
	_logger.debug("weapon", self, "💥 fired %d projectiles (no ammo consumed): type=%s" % [projectile_count, weapon_type])

## Start charging secondary attack (called when mouse button is held)
func start_secondary_attack() -> void:
	if _attached_to_mount == null:
		_logger.error("weapon", self, "❌ Cannot start secondary attack: weapon not attached to mount")
		return
	
	if not is_inside_tree():
		_logger.error("weapon", self, "❌ Cannot start secondary attack: weapon not in scene tree")
		return
	
	if _is_charging_secondary:
		return  # Already charging
	
	if current_ammo <= 0:
		_logger.info("weapon", self, "⚠️ cannot start secondary attack: out of ammo")
		return
	
	_is_charging_secondary = true
	_charge_time = 0.0
	_charged_ammo_consumed = 0
	_fractional_ammo_accumulator = 0.0
	_start_charging_visual_feedback()
	_logger.info("weapon", self, "⚡ starting secondary attack charge: type=%s, ammo=%d/%d" % [weapon_type, current_ammo, max_ammo])

## Update secondary attack charge (called every frame while charging)
func update_secondary_charge(delta: float) -> void:
	if not _is_charging_secondary:
		return
	
	if _attached_to_mount == null or not is_inside_tree():
		_is_charging_secondary = false
		return
	
	if current_ammo <= 0:
		# Release immediately if out of ammo
		release_secondary_attack()
		return
	
	var ammo_per_second: float = WeaponRegistry.get_secondary_ammo_per_second(weapon_type)
	var ammo_to_consume: float = ammo_per_second * delta
	
	# Accumulate fractional ammo
	_fractional_ammo_accumulator += ammo_to_consume
	var ammo_consumed_this_frame: int = int(_fractional_ammo_accumulator)
	
	# Consume ammo if we've accumulated at least 1 unit
	if ammo_consumed_this_frame > 0 and current_ammo >= ammo_consumed_this_frame:
		var old_ammo: int = current_ammo
		current_ammo -= ammo_consumed_this_frame
		_charged_ammo_consumed += ammo_consumed_this_frame
		_fractional_ammo_accumulator -= float(ammo_consumed_this_frame)  # Subtract consumed amount
		_charge_time += delta
		
		# Emit ammo changed signal
		ammo_changed.emit(current_ammo, max_ammo)
		
		# Check if ammo is depleted
		if current_ammo <= 0:
			ammo_depleted.emit(weapon_type)
			release_secondary_attack()
			return
	else:
		# Still update charge time even if no ammo consumed this frame
		_charge_time += delta

## Release secondary attack (called when mouse button is released)
func release_secondary_attack() -> void:
	if not _is_charging_secondary:
		return
	
	if _attached_to_mount == null:
		_is_charging_secondary = false
		return
	
	if not is_inside_tree():
		_is_charging_secondary = false
		return
	
	var mount: RigidBody3D = _attached_to_mount as RigidBody3D
	if mount == null:
		_logger.error("weapon", self, "❌ Cannot release secondary attack: mount is not a RigidBody3D")
		_is_charging_secondary = false
		return
	
	# Calculate spawn position and direction
	var spawn_position: Vector3 = global_position
	var forward: Vector3 = -mount.global_transform.basis.z  # Mount's forward direction
	
	# Get base secondary attack properties
	var base_secondary_projectile_count: int = WeaponRegistry.get_secondary_projectile_count(weapon_type)
	var secondary_color: Color = WeaponRegistry.get_secondary_color(weapon_type)
	var ammo_per_second: float = WeaponRegistry.get_secondary_ammo_per_second(weapon_type)
	
	# Calculate power multiplier based on ammo consumed
	# Base charge time for minimum effect (0.5 seconds)
	var base_charge_time: float = 0.5
	var base_ammo_for_min_effect: float = ammo_per_second * base_charge_time
	
	# Calculate power multiplier (minimum 1.0, scales with ammo consumed)
	var power_multiplier: float = 1.0
	if _charged_ammo_consumed > 0:
		power_multiplier = max(1.0, float(_charged_ammo_consumed) / base_ammo_for_min_effect)
	
	# Scale projectile count based on power multiplier
	var scaled_projectile_count: int = int(base_secondary_projectile_count * power_multiplier)
	# Cap at reasonable maximum (3x base)
	scaled_projectile_count = min(scaled_projectile_count, base_secondary_projectile_count * 3)
	
	_logger.info("weapon", self, "💥 releasing secondary attack: type=%s, charge_time=%.2f, ammo_consumed=%d, base_count=%d, scaled_count=%d, power=%.2fx" % [weapon_type, _charge_time, _charged_ammo_consumed, base_secondary_projectile_count, scaled_projectile_count, power_multiplier])
	
	# Weapon-specific secondary attack behavior (scaled by power)
	match weapon_type:
		"rocket_launcher":
			# Rocket launcher: Fires a volley of rockets in a spread pattern
			_secondary_rocket_launcher(spawn_position, forward, scaled_projectile_count, secondary_color, power_multiplier)
		"mine_layer":
			# Mine layer: Fires mines in a wide spread pattern
			_secondary_mine_layer(spawn_position, forward, scaled_projectile_count, secondary_color, power_multiplier)
		"autocannon":
			# Autocannon: Rapid-fire burst in a cone
			_secondary_autocannon(spawn_position, forward, scaled_projectile_count, secondary_color, power_multiplier)
		_:
			_logger.warn("weapon", self, "⚠️ unknown weapon type for secondary attack: %s" % weapon_type)
	
	_is_charging_secondary = false
	_charge_time = 0.0
	_charged_ammo_consumed = 0
	_fractional_ammo_accumulator = 0.0
	_stop_charging_visual_feedback()

## Rocket launcher secondary attack: volley spread (scaled by power)
func _secondary_rocket_launcher(spawn_position: Vector3, direction: Vector3, count: int, color: Color, power: float) -> void:
	# Spread angle scales with power (more power = wider spread, up to 60 degrees)
	var base_spread: float = deg_to_rad(30.0)
	var max_spread: float = deg_to_rad(60.0)
	var spread_angle: float = lerp(base_spread, max_spread, min(1.0, (power - 1.0) / 2.0))
	
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	if right.length() < 0.1:
		right = Vector3.RIGHT
	
	# Scale projectile size and speed with power
	var projectile_scale: float = lerp(1.5, 2.5, min(1.0, (power - 1.0) / 2.0))
	var speed_multiplier: float = lerp(1.2, 1.8, min(1.0, (power - 1.0) / 2.0))
	
	for i in range(count):
		var angle_offset: float = (float(i) / float(count - 1) - 0.5) * spread_angle if count > 1 else 0.0
		var fire_direction: Vector3 = direction.rotated(right, angle_offset).normalized()
		_spawn_secondary_projectile(spawn_position, fire_direction, color, projectile_scale, speed_multiplier)

## Mine layer secondary attack: wide spread pattern (scaled by power)
func _secondary_mine_layer(spawn_position: Vector3, direction: Vector3, count: int, color: Color, power: float) -> void:
	# Spread angle scales with power (more power = wider spread, up to 120 degrees)
	var base_spread: float = deg_to_rad(60.0)
	var max_spread: float = deg_to_rad(120.0)
	var spread_angle: float = lerp(base_spread, max_spread, min(1.0, (power - 1.0) / 2.0))
	
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	if right.length() < 0.1:
		right = Vector3.RIGHT
	
	# Scale projectile size with power
	var projectile_scale: float = lerp(0.8, 1.2, min(1.0, (power - 1.0) / 2.0))
	var speed_multiplier: float = 1.0  # Mines stay at base speed
	
	for i in range(count):
		var angle_offset: float = (float(i) / float(count - 1) - 0.5) * spread_angle if count > 1 else 0.0
		var fire_direction: Vector3 = direction.rotated(right, angle_offset).normalized()
		# Mines with slight upward arc (arc increases with power)
		var up: Vector3 = Vector3.UP
		var arc_strength: float = lerp(0.2, 0.4, min(1.0, (power - 1.0) / 2.0))
		fire_direction = (fire_direction + up * arc_strength).normalized()
		_spawn_secondary_projectile(spawn_position, fire_direction, color, projectile_scale, speed_multiplier)

## Autocannon secondary attack: rapid-fire cone (scaled by power)
func _secondary_autocannon(spawn_position: Vector3, direction: Vector3, count: int, color: Color, power: float) -> void:
	# Cone spread scales with power (more power = wider cone, up to 90 degrees)
	var base_spread: float = deg_to_rad(45.0)
	var max_spread: float = deg_to_rad(90.0)
	var spread_angle: float = lerp(base_spread, max_spread, min(1.0, (power - 1.0) / 2.0))
	
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	if right.length() < 0.1:
		right = Vector3.RIGHT
	
	# Scale projectile size and speed with power
	var projectile_scale: float = lerp(1.2, 1.8, min(1.0, (power - 1.0) / 2.0))
	var speed_multiplier: float = lerp(1.2, 2.0, min(1.0, (power - 1.0) / 2.0))
	
	var vertical_spread: float = lerp(deg_to_rad(20.0), deg_to_rad(40.0), min(1.0, (power - 1.0) / 2.0))
	
	for i in range(count):
		var angle_offset: float = (float(i) / float(count - 1) - 0.5) * spread_angle if count > 1 else 0.0
		var vertical_offset: float = (float(i) / float(count - 1) - 0.5) * vertical_spread if count > 1 else 0.0
		var up: Vector3 = direction.cross(right).normalized()
		var fire_direction: Vector3 = direction.rotated(right, angle_offset)
		fire_direction = fire_direction.rotated(right.cross(up), vertical_offset).normalized()
		_spawn_secondary_projectile(spawn_position, fire_direction, color, projectile_scale, speed_multiplier)

## Spawn a secondary attack projectile with custom color, scale, and speed multiplier
func _spawn_secondary_projectile(spawn_position: Vector3, direction: Vector3, color: Color, scale: float, speed_mult: float = 1.2) -> void:
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
	
	# Set secondary attack properties
	projectile.projectile_color = color
	projectile.projectile_scale = scale
	projectile.speed *= speed_mult  # Speed multiplier based on power
	
	# Add to scene tree
	var scene_root: Node = get_tree().root
	if scene_root == null:
		_logger.error("weapon", self, "❌ Cannot spawn projectile: scene root is null")
		return
	
	scene_root.add_child(projectile)
	
	# Position projectile
	projectile.global_position = spawn_position
	
	# Initialize projectile
	projectile.initialize(direction, _attached_to_mount, weapon_type)
	
	_logger.debug("weapon", self, "⚡ secondary projectile spawned: pos=%s, dir=%s, color=%s, scale=%.2f" % [spawn_position, direction, color, scale])

## Visual feedback: flicker weapon red for primary attack
func _flicker_weapon_red() -> void:
	if _mesh_instances.is_empty():
		return
	
	# Stop any existing flicker
	if _flicker_tween != null:
		_flicker_tween.kill()
		_flicker_tween = null
	
	_flicker_tween = create_tween()
	_flicker_tween.set_loops(2)  # Flicker twice (red -> normal -> red -> normal)
	
	for i in range(_mesh_instances.size()):
		var mesh_instance: MeshInstance3D = _mesh_instances[i]
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		
		var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
		if material == null:
			continue
		
		var base_color: Color = weapon_color
		var red_color: Color = Color.RED
		
		# Create callable for color update
		var update_color_callable: Callable = func(color: Color): 
			if is_instance_valid(material):
				material.albedo_color = color
				material.emission = color * 0.5
		
		var restore_color_callable: Callable = func(color: Color): 
			if is_instance_valid(material):
				material.albedo_color = color
				material.emission = color * 0.3
		
		# Flicker to red
		_flicker_tween.parallel().tween_method(update_color_callable, base_color, red_color, 0.05)
		# Flicker back to normal
		_flicker_tween.parallel().tween_method(restore_color_callable, red_color, base_color, 0.05)

## Visual feedback: start charging visual (continuous red flicker)
func _start_charging_visual_feedback() -> void:
	if _mesh_instances.is_empty():
		return
	
	# Stop any existing flicker
	if _flicker_tween != null:
		_flicker_tween.kill()
		_flicker_tween = null
	
	_flicker_tween = create_tween()
	_flicker_tween.set_loops()  # Loop indefinitely
	
	for i in range(_mesh_instances.size()):
		var mesh_instance: MeshInstance3D = _mesh_instances[i]
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		
		var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
		if material == null:
			continue
		
		var base_color: Color = weapon_color
		var red_color: Color = Color.RED
		
		# Create callable for color update
		var update_color_callable: Callable = func(color: Color): 
			if is_instance_valid(material):
				material.albedo_color = color
				material.emission = color * 0.5
		
		var restore_color_callable: Callable = func(color: Color): 
			if is_instance_valid(material):
				material.albedo_color = color
				material.emission = color * 0.3
		
		# Continuous flicker between base and red
		_flicker_tween.parallel().tween_method(update_color_callable, base_color, red_color, 0.15)
		_flicker_tween.parallel().tween_method(restore_color_callable, red_color, base_color, 0.15)

## Visual feedback: stop charging visual (restore normal color)
func _stop_charging_visual_feedback() -> void:
	if _flicker_tween != null:
		_flicker_tween.kill()
		_flicker_tween = null
	
	# Restore base color immediately
	for i in range(_mesh_instances.size()):
		var mesh_instance: MeshInstance3D = _mesh_instances[i]
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		
		var material: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
		if material == null:
			continue
		
		material.albedo_color = weapon_color
		material.emission = weapon_color * 0.3

