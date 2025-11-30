@tool
extends Node3D
class_name WeaponSpawner

const WeaponRegistryClass = preload("res://scripts/core/weapon_registry.gd")
const WeaponPoolEntryClass = preload("res://scripts/pickups/weapon_pool_entry.gd")

## Pool of weapon entries to randomly spawn from. Each entry contains a weapon type and level.
## Available weapon types are automatically detected from the weapon registry.
## You can add the same weapon multiple times at different levels for varied spawn chances.
## If only one entry is in the pool, it will always spawn that weapon.
## If multiple entries are in the pool, it will randomly pick one each respawn.
## Colors are automatically set from the weapon registry based on the weapon type.
## Level determines how many weapons are stacked (1 = single, 2 = two stacked, 3 = three stacked, etc.)
@export var weapon_pool: Array[WeaponPoolEntry] = []
## Delay in seconds before respawning after pickup (tweakable)
@export var respawn_delay: float = 3.0
## Path to the weapon pickup scene
const WEAPON_PICKUP_SCENE: String = "res://scenes/pickups/weapon_pickup.tscn"

var _logger: Node
var _current_pickup: WeaponPickup = null
var _spawn_timer: Timer = null
var _current_weapon_type: String = ""
var _current_weapon_level: int = 1

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	
	# Don't run game logic in editor (tool mode)
	if Engine.is_editor_hint():
		return
	
	# Validate and filter weapon pool
	_validate_weapon_pool()
	
	# Ensure weapon pool is not empty
	if weapon_pool.is_empty():
		if _logger:
			_logger.error("spawner", self, "❌ no valid weapons in spawn pool! Adding default rocket_launcher")
		var default_entry: WeaponPoolEntry = WeaponPoolEntryClass.new()
		default_entry.weapon_type = "rocket_launcher"
		default_entry.level = 1
		weapon_pool = [default_entry]
	
	# Create spawn timer
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = respawn_delay
	_spawn_timer.one_shot = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)
	
	# Spawn initial pickup
	spawn_pickup()
	
	if _logger:
		_logger.info("spawner", self, "🏭 weapon spawner ready: pool_size=%d, respawn_delay=%.1fs, pos=%s" % [weapon_pool.size(), respawn_delay, position])

## Get list of available weapon types for editor reference
## Returns array of weapon type strings that can be added to the pool
## This is automatically populated from the weapon registry
func get_available_weapon_types() -> Array[String]:
	return WeaponRegistryClass.get_all_weapon_types()

## Validate and filter the weapon pool to ensure only valid weapon entries are included
## Removes invalid weapon types and logs warnings for debugging
func _validate_weapon_pool() -> void:
	var valid_weapon_types: Array[String] = WeaponRegistryClass.get_all_weapon_types()
	var filtered_pool: Array[WeaponPoolEntry] = []
	
	for entry in weapon_pool:
		if entry == null or not entry is WeaponPoolEntry:
			if _logger:
				_logger.warn("spawner", self, "⚠️ invalid entry in pool (not a WeaponPoolEntry), ignored")
			continue
		
		var pool_entry: WeaponPoolEntry = entry as WeaponPoolEntry
		
		# Validate weapon type
		if WeaponRegistryClass.is_valid_weapon_type(pool_entry.weapon_type):
			# Validate level
			if pool_entry.level < 1:
				if _logger:
					_logger.warn("spawner", self, "⚠️ invalid level (%d) for weapon '%s', setting to 1" % [pool_entry.level, pool_entry.weapon_type])
				pool_entry.level = 1
			
			filtered_pool.append(pool_entry)
		else:
			if _logger:
				_logger.warn("spawner", self, "⚠️ invalid weapon type in pool: '%s' (ignored). Valid types: %s" % [pool_entry.weapon_type, valid_weapon_types])
	
	weapon_pool = filtered_pool
	if _logger:
		_logger.debug("spawner", self, "🔧 validated weapon pool: %d entries" % weapon_pool.size())

## Select a random weapon entry from the weapon pool
## Returns a Dictionary with "weapon_type" and "level"
func _select_random_weapon() -> Dictionary:
	if weapon_pool.is_empty():
		if _logger:
			_logger.error("spawner", self, "❌ weapon_pool is empty, using default rocket_launcher")
		return {"weapon_type": "rocket_launcher", "level": 1}
	
	# If only one entry in pool, always return it
	if weapon_pool.size() == 1:
		var entry: WeaponPoolEntry = weapon_pool[0]
		return {"weapon_type": entry.weapon_type, "level": entry.level}
	
	# Randomly select from the pool
	var random_index: int = randi() % weapon_pool.size()
	var selected_entry: WeaponPoolEntry = weapon_pool[random_index]
	if _logger:
		_logger.debug("spawner", self, "🎲 randomly selected weapon from pool: %s level %d (index %d of %d)" % [selected_entry.weapon_type, selected_entry.level, random_index, weapon_pool.size()])
	return {"weapon_type": selected_entry.weapon_type, "level": selected_entry.level}

func spawn_pickup() -> void:
	# Don't spawn if there's already a pickup
	if _current_pickup != null and is_instance_valid(_current_pickup):
		if _logger:
			_logger.debug("spawner", self, "⚠️ spawn blocked: pickup already exists")
		return
	
	# Select a random weapon entry from the pool
	var selected: Dictionary = _select_random_weapon()
	_current_weapon_type = selected.get("weapon_type", "rocket_launcher")
	_current_weapon_level = selected.get("level", 1)
	
	# Load the weapon pickup scene
	var pickup_scene: PackedScene = load(WEAPON_PICKUP_SCENE)
	if pickup_scene == null:
		if _logger:
			_logger.error("spawner", self, "❌ Failed to load weapon pickup scene: %s" % WEAPON_PICKUP_SCENE)
		return
	
	# Instantiate the pickup
	var pickup_instance: Node = pickup_scene.instantiate()
	if pickup_instance == null or not pickup_instance is WeaponPickup:
		if _logger:
			_logger.error("spawner", self, "❌ Failed to instantiate weapon pickup")
		return
	
	var pickup: WeaponPickup = pickup_instance as WeaponPickup
	
	# Set weapon type, level, and color - always use weapon registry color for consistency
	var weapon_color: Color = WeaponRegistryClass.get_weapon_color(_current_weapon_type)
	
	pickup.weapon_type = _current_weapon_type
	pickup.weapon_level = _current_weapon_level
	pickup.pickup_color = weapon_color
	
	# Add to scene tree FIRST (required before setting global_position and connecting signals)
	add_child(pickup)
	
	# Connect to pickup signal to know when it's picked up (after adding to tree)
	if pickup.has_signal("weapon_picked_up"):
		pickup.weapon_picked_up.connect(_on_pickup_collected)
	else:
		if _logger:
			_logger.error("spawner", self, "❌ pickup does not have weapon_picked_up signal!")
	
	# Position the pickup at the spawner's position (after adding to tree)
	pickup.global_position = global_position
	
	# Connect the pickup to all mount controllers in the scene
	# This ensures dynamically spawned pickups are connected
	_connect_pickup_to_mounts(pickup)
	
	_current_pickup = pickup
	
	if _logger:
		_logger.info("spawner", self, "✨ spawned pickup: type=%s, level=%d, pos=%s" % [_current_weapon_type, _current_weapon_level, global_position])

func _on_pickup_collected(pickup: WeaponPickup, _mount: Node, collected_weapon_type: String, collected_weapon_level: int = 1) -> void:
	# Only handle if this is our current pickup
	if pickup != _current_pickup:
		return
	
	if _logger:
		_logger.info("spawner", self, "📦 pickup collected: type=%s, level=%d, starting respawn timer (%.1fs)" % [collected_weapon_type, collected_weapon_level, respawn_delay])
	
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
	
	if _logger:
		_logger.debug("spawner", self, "🔍 found %d mount controllers to connect pickup to" % mounts.size())
	
	for mount in mounts:
		if mount is MountController:
			var mount_controller: MountController = mount as MountController
			if pickup.has_signal("weapon_picked_up"):
				if not pickup.weapon_picked_up.is_connected(mount_controller._on_weapon_picked_up):
					pickup.weapon_picked_up.connect(mount_controller._on_weapon_picked_up)
					if _logger:
						_logger.debug("spawner", self, "🔌 connected pickup to mount: %s" % mount_controller.name)
				else:
					if _logger:
						_logger.debug("spawner", self, "⚠️ pickup already connected to mount: %s" % mount_controller.name)

func _find_mount_controllers_recursive(node: Node, mounts: Array) -> void:
	if node is MountController:
		mounts.append(node)
	
	for child in node.get_children():
		_find_mount_controllers_recursive(child, mounts)

func _on_spawn_timer_timeout() -> void:
	if _logger:
		_logger.debug("spawner", self, "⏰ respawn timer expired, spawning new pickup")
	spawn_pickup()
