extends RigidBody3D
class_name WeaponPickup

## Weapon type identifier (can be any string, used for spawning weapons on mounts)
@export var weapon_type: String = "rocket_launcher"
## Visual color for the pickup (for different weapon types)
@export var pickup_color: Color = Color(1.0, 0.5, 0.0, 1.0)
## Rotation speed for visual effect (radians per second) - only used when landed
@export var rotation_speed: float = 2.0
## Bobbing speed for visual effect - only used when landed
@export var bob_speed: float = 2.0
## Bobbing amplitude in units - only used when landed
@export var bob_amplitude: float = 0.3
## Pickup detection radius
@export var pickup_radius: float = 2.0
## Delay in seconds before pickup becomes collectible (prevents immediate re-pickup after dropping)
@export var pickup_delay: float = 0.5
## Ejection velocity when dropped (units per second)
@export var ejection_speed: float = 15.0
## Stored ammo state (if -1, use registry default; otherwise use this value)
## This preserves ammo state when weapons are dropped and picked up again
@export var stored_current_ammo: int = -1
@export var stored_max_ammo: int = -1

var _logger: Node
var _pickup_used: bool = false
var _pickup_enabled: bool = false
var _landed: bool = false
var _ejection_velocity: Vector3 = Vector3.ZERO
var _detection_area: Area3D = null

signal weapon_picked_up(pickup: WeaponPickup, mount: Node, weapon_type: String)

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	
	# Get color from weapon registry if not explicitly set
	if pickup_color == Color(1.0, 0.5, 0.0, 1.0):  # Default orange
		pickup_color = WeaponRegistry.get_weapon_color(weapon_type)
	
	# Set up physics (RigidBody3D)
	freeze = false
	sleeping = false
	gravity_scale = 1.0  # Normal gravity
	lock_rotation = false  # Allow rotation for tumbling effect
	
	# Set up detection Area3D as child for pickup detection
	_setup_detection_area()
	
	# Disable detection initially to prevent immediate pickup after dropping
	_pickup_enabled = false
	
	# Set up visual representation
	_setup_visuals()
	
	_logger.info("pickup", self, "🎁 weapon pickup spawned: type=%s, color=%s, pos=%s, delay=%s" % [weapon_type, pickup_color, global_position, pickup_delay])
	
	# Apply ejection velocity if set (for dropped weapons)
	if _ejection_velocity != Vector3.ZERO:
		call_deferred("_apply_ejection_velocity")
	
	# Enable pickup after delay
	if pickup_delay > 0.0:
		await get_tree().create_timer(pickup_delay).timeout
	
	_pickup_enabled = true
	if _detection_area != null:
		_detection_area.monitoring = true
	_logger.debug("pickup", self, "✅ pickup enabled after delay")

func _setup_detection_area() -> void:
	# Create Area3D child for pickup detection (since RigidBody3D uses different collision system)
	_detection_area = Area3D.new()
	_detection_area.name = "DetectionArea"
	add_child(_detection_area)
	
	# Create collision shape
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = pickup_radius
	collision_shape.shape = sphere_shape
	_detection_area.add_child(collision_shape)
	
	# Connect body_entered signal for pickup detection
	_detection_area.body_entered.connect(_on_body_entered)
	
	# Disable monitoring initially
	_detection_area.monitoring = false
	_detection_area.monitorable = false

func _apply_ejection_velocity() -> void:
	if _ejection_velocity != Vector3.ZERO:
		linear_velocity = _ejection_velocity
		# Add some random angular velocity for tumbling effect
		angular_velocity = Vector3(
			randf_range(-5.0, 5.0),
			randf_range(-5.0, 5.0),
			randf_range(-5.0, 5.0)
		)
		_logger.debug("pickup", self, "🚀 ejection velocity applied: %s, angular: %s" % [_ejection_velocity, angular_velocity])

func _setup_visuals() -> void:
	# Load the appropriate weapon scene for this pickup
	var weapon_scene_path: String = WeaponRegistry.get_weapon_scene_path(weapon_type)
	var weapon_scene: PackedScene = load(weapon_scene_path)
	
	if weapon_scene != null:
		# Instantiate the weapon visual
		var weapon_visual: Node = weapon_scene.instantiate()
		if weapon_visual != null:
			# Remove the script from the visual (we don't want weapon attachment behavior on pickup)
			weapon_visual.set_script(null)
			
			# Update color to match pickup color (which should match weapon type color)
			_update_weapon_visual_color(weapon_visual, pickup_color)
			
			# Add as child
			add_child(weapon_visual)
			_logger.debug("pickup", self, "🎨 weapon visual loaded: %s" % weapon_type)
		else:
			_logger.error("pickup", self, "❌ Failed to instantiate weapon visual")
	else:
		_logger.error("pickup", self, "❌ Failed to load weapon scene: %s" % weapon_scene_path)
		# Fallback to simple box
		_create_fallback_visual()
	
	# Ensure RigidBody3D collision shape exists for physics
	var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		add_child(collision_shape)
	
	if collision_shape.shape == null:
		var sphere_shape: SphereShape3D = SphereShape3D.new()
		sphere_shape.radius = pickup_radius * 0.8  # Slightly smaller than detection radius
		collision_shape.shape = sphere_shape

func _update_weapon_visual_color(node: Node, color: Color) -> void:
	# Recursively update all MeshInstance3D nodes with the color
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color * 0.5
		mesh_instance.set_surface_override_material(0, material)
	
	for child in node.get_children():
		_update_weapon_visual_color(child, color)

func _create_fallback_visual() -> void:
	# Fallback simple box if weapon scene fails to load
	var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "MeshInstance3D"
		add_child(mesh_instance)
	
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = Vector3(0.8, 0.8, 0.8)
	mesh_instance.mesh = box_mesh
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = pickup_color
	material.emission_enabled = true
	material.emission = pickup_color * 0.5
	mesh_instance.set_surface_override_material(0, material)

func _process(delta: float) -> void:
	if _pickup_used:
		return
	
	# Only apply visual effects when landed (not tumbling through air)
	# Check if velocity is low (landed)
	if linear_velocity.length() < 1.0 and _landed == false:
		_landed = true
		# Lock rotation when landed for smoother visual rotation
		lock_rotation = true
		freeze = true  # Freeze physics when landed
		_logger.debug("pickup", self, "🏠 pickup landed, freezing physics")
	
	if _landed:
		# Rotate the pickup visually (independent of physics)
		rotate_y(rotation_speed * delta)
		
		# Bob up and down
		var bob_offset: float = sin(Time.get_ticks_msec() / 1000.0 * bob_speed) * bob_amplitude
		var base_y: float = global_position.y
		global_position.y = base_y + bob_offset

func _on_body_entered(body: Node3D) -> void:
	if _pickup_used:
		return
	
	if not _pickup_enabled:
		_logger.debug("pickup", self, "⏸️ pickup disabled (still in delay), ignoring collision")
		return
	
	# Check if the body is a mount (RigidBody3D with MountController)
	if not body is RigidBody3D:
		return
	
	var mount: RigidBody3D = body as RigidBody3D
	
	# Check if it has MountController class
	var mount_controller: MountController = null
	if mount.get_script() != null:
		# Try to cast to MountController
		if mount is MountController:
			mount_controller = mount as MountController
	
	if mount_controller == null:
		return
	
	# Pickup detected! Handle the pickup
	_handle_pickup(mount_controller)

func _handle_pickup(mount: MountController) -> void:
	if _pickup_used:
		return
	
	_pickup_used = true
	
	_logger.info("pickup", self, "✨ weapon picked up: type=%s, by=%s" % [weapon_type, mount.name])
	
	# Emit signal for other systems to handle (e.g., attaching weapon to mount)
	weapon_picked_up.emit(self, mount, weapon_type)
	
	# Visual/audio feedback could go here (particles, sound, etc.)
	
	# Hide and disable the pickup
	# Use set_deferred() because we're inside a signal callback (body_entered)
	visible = false
	if _detection_area != null:
		_detection_area.set_deferred("monitoring", false)
		_detection_area.set_deferred("monitorable", false)
	
	# Remove after a short delay (for cleanup)
	await get_tree().create_timer(0.5).timeout
	queue_free()
