extends Area3D
class_name WeaponPickup

## Weapon type identifier (can be any string, used for spawning weapons on mounts)
@export var weapon_type: String = "rocket_launcher"
## Visual color for the pickup (for different weapon types)
@export var pickup_color: Color = Color(1.0, 0.5, 0.0, 1.0)
## Rotation speed for visual effect (radians per second)
@export var rotation_speed: float = 2.0
## Bobbing speed for visual effect
@export var bob_speed: float = 2.0
## Bobbing amplitude in units
@export var bob_amplitude: float = 0.3
## Pickup detection radius
@export var pickup_radius: float = 2.0

var _base_position: Vector3
var _logger: Node
var _pickup_used: bool = false

signal weapon_picked_up(pickup: WeaponPickup, mount: Node, weapon_type: String)

func _ready() -> void:
	_base_position = position
	_logger = get_node_or_null("/root/LoggerInstance")
	
	# Get color from weapon registry if not explicitly set
	if pickup_color == Color(1.0, 0.5, 0.0, 1.0):  # Default orange
		pickup_color = WeaponRegistry.get_weapon_color(weapon_type)
	
	# Connect body_entered signal for pickup detection
	body_entered.connect(_on_body_entered)
	
	# Set up visual representation
	_setup_visuals()
	
	_logger.info("pickup", self, "🎁 weapon pickup spawned: type=%s, color=%s, pos=%s" % [weapon_type, pickup_color, position])

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
	
	# Ensure collision shape exists and is set up
	var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if collision_shape != null and collision_shape.shape == null:
		var sphere_shape: SphereShape3D = SphereShape3D.new()
		sphere_shape.radius = pickup_radius
		collision_shape.shape = sphere_shape
	
	# Set collision layers - pickup should detect all physics bodies (default)
	# Area3D will detect RigidBody3D by default
	collision_layer = 0
	collision_mask = 0xFFFFFFFF  # Detect all collision layers (default behavior)

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
	
	# Rotate the pickup
	rotate_y(rotation_speed * delta)
	
	# Bob up and down
	var bob_offset: float = sin(Time.get_ticks_msec() / 1000.0 * bob_speed) * bob_amplitude
	position.y = _base_position.y + bob_offset

func _on_body_entered(body: Node3D) -> void:
	if _pickup_used:
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
	# Setting monitoring/monitorable during signal callbacks is blocked for thread safety
	# All errors from this (and all other errors/warnings) are automatically captured in log.txt
	# via Godot's file logging system configured in project.godot (file_logging/enable_file_logging=true)
	visible = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# Remove after a short delay (for cleanup)
	await get_tree().create_timer(0.5).timeout
	queue_free()
