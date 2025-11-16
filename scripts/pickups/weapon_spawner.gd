extends Node3D
class_name WeaponSpawner

const WeaponRegistryClass = preload("res://scripts/core/weapon_registry.gd")

## Weapon type to spawn (rocket_launcher, mine_layer, autocannon, etc.)
@export var weapon_type: String = "rocket_launcher"
## Visual color for the spawned pickup
@export var pickup_color: Color = Color(1.0, 0.5, 0.0, 1.0)
## Delay in seconds before respawning after pickup (tweakable)
@export var respawn_delay: float = 3.0
## Path to the weapon pickup scene
const WEAPON_PICKUP_SCENE: String = "res://scenes/pickups/weapon_pickup.tscn"

var _logger: Node
var _current_pickup: WeaponPickup = null
var _spawn_timer: Timer = null

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	
	# Get color from weapon registry if not explicitly set
	if pickup_color == Color(1.0, 0.5, 0.0, 1.0):  # Default orange
		pickup_color = WeaponRegistryClass.get_weapon_color(weapon_type)
	
	# Create spawn timer
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = respawn_delay
	_spawn_timer.one_shot = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)
	
	# Spawn initial pickup
	spawn_pickup()
	
	_logger.info("spawner", self, "🏭 weapon spawner ready: type=%s, respawn_delay=%.1fs, pos=%s" % [weapon_type, respawn_delay, position])

func spawn_pickup() -> void:
	# Don't spawn if there's already a pickup
	if _current_pickup != null and is_instance_valid(_current_pickup):
		_logger.debug("spawner", self, "⚠️ spawn blocked: pickup already exists")
		return
	
	# Load the weapon pickup scene
	var pickup_scene: PackedScene = load(WEAPON_PICKUP_SCENE)
	if pickup_scene == null:
		_logger.error("spawner", self, "❌ Failed to load weapon pickup scene: %s" % WEAPON_PICKUP_SCENE)
		return
	
	# Instantiate the pickup
	var pickup_instance: Node = pickup_scene.instantiate()
	if pickup_instance == null or not pickup_instance is WeaponPickup:
		_logger.error("spawner", self, "❌ Failed to instantiate weapon pickup")
		return
	
	var pickup: WeaponPickup = pickup_instance as WeaponPickup
	
	# Set weapon type and color
	pickup.weapon_type = weapon_type
	pickup.pickup_color = pickup_color
	
	# Connect to pickup signal to know when it's picked up
	pickup.weapon_picked_up.connect(_on_pickup_collected)
	
	# Add to scene tree FIRST (required before setting global_position)
	add_child(pickup)
	
	# Position the pickup at the spawner's position (after adding to tree)
	pickup.global_position = global_position
	
	# Connect the pickup to all mount controllers in the scene
	# This ensures dynamically spawned pickups are connected
	_connect_pickup_to_mounts(pickup)
	
	_current_pickup = pickup
	
	_logger.info("spawner", self, "✨ spawned pickup: type=%s, pos=%s" % [weapon_type, global_position])

func _on_pickup_collected(pickup: WeaponPickup, _mount: Node, collected_weapon_type: String) -> void:
	# Only handle if this is our current pickup
	if pickup != _current_pickup:
		return
	
	_logger.info("spawner", self, "📦 pickup collected: type=%s, starting respawn timer (%.1fs)" % [collected_weapon_type, respawn_delay])
	
	# Clear reference
	_current_pickup = null
	
	# Start respawn timer
	_spawn_timer.start()

func _update_timer_delay() -> void:
	if _spawn_timer != null:
		_spawn_timer.wait_time = respawn_delay

func _connect_pickup_to_mounts(pickup: WeaponPickup) -> void:
	# Find all mount controllers in the scene and connect the pickup to them
	var mounts: Array[Node] = []
	_find_mount_controllers_recursive(get_tree().root, mounts)
	
	_logger.debug("spawner", self, "🔍 found %d mount controllers to connect pickup to" % mounts.size())
	
	for mount in mounts:
		if mount is MountController:
			var mount_controller: MountController = mount as MountController
			if not pickup.weapon_picked_up.is_connected(mount_controller._on_weapon_picked_up):
				pickup.weapon_picked_up.connect(mount_controller._on_weapon_picked_up)
				_logger.debug("spawner", self, "🔌 connected pickup to mount: %s" % mount_controller.name)
			else:
				_logger.debug("spawner", self, "⚠️ pickup already connected to mount: %s" % mount_controller.name)

func _find_mount_controllers_recursive(node: Node, mounts: Array) -> void:
	if node is MountController:
		mounts.append(node)
	
	for child in node.get_children():
		_find_mount_controllers_recursive(child, mounts)

func _on_spawn_timer_timeout() -> void:
	_logger.debug("spawner", self, "⏰ respawn timer expired, spawning new pickup")
	spawn_pickup()
