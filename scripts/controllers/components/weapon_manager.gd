extends Node
class_name WeaponManager

## Manages all weapon operations: attachment, upgrade, replacement, and dropping
## This component handles the complexity of weapon stacking, ammo management, and weapon lifecycle

# Preload helper classes
const WeaponSlotConstantsClass = preload("res://scripts/controllers/weapon_slot_constants.gd")
const WeaponSlotManagerClass = preload("res://scripts/controllers/weapon_slot_manager.gd")

## Signal emitted when a weapon slot needs HUD update
signal hud_update_needed(slot: int)
## Signal emitted when a weapon should be dropped
signal weapon_dropped(weapon: WeaponAttachment, slot: int)

var _mount_controller: MountController = null
var _logger: Node = null
var _slot_manager: WeaponSlotManagerClass = null
var _weapon_marker_left: Marker3D = null
var _weapon_marker_right: Marker3D = null
var _attached_weapons: Array[WeaponAttachment] = []
# Track stacked weapons per slot: {slot: [WeaponAttachment, ...]}
var _stacked_weapons: Dictionary = {}  # {1: [weapon1, weapon2, ...], 2: [weapon1, weapon2, ...]}

func initialize(mount_controller: MountController, slot_manager: WeaponSlotManagerClass, logger: Node) -> void:
	_mount_controller = mount_controller
	_slot_manager = slot_manager
	_logger = logger
	
	# Get weapon markers from mount
	_weapon_marker_left = mount_controller.get_node_or_null("WeaponMarkerLeft")
	_weapon_marker_right = mount_controller.get_node_or_null("WeaponMarkerRight")
	
	if _logger:
		_logger.debug("weapon", self, "🔧 WeaponManager initialized")

## Attach a weapon at a specific level (creates stacked weapons)
func attach_weapon_at_level(weapon_type: String, weapon_color: Color, marker: Marker3D, level: int = 1, stored_current_ammo: int = -1, stored_max_ammo: int = -1) -> void:
	# Validate level
	if level < 1:
		level = 1
		if _logger:
			_logger.warn("weapon", self, "⚠️ weapon level was < 1, setting to 1")
	
	# Attach multiple weapons to create the stack
	for i in range(level):
		if i == 0:
			# First weapon - attach normally
			_attach_weapon(weapon_type, weapon_color, marker, stored_current_ammo, stored_max_ammo)
		else:
			# Additional weapons - upgrade the stack
			var slot: int = WeaponSlotConstantsClass.Slot.LEFT if marker == _weapon_marker_left else WeaponSlotConstantsClass.Slot.RIGHT
			upgrade_weapon_in_slot(slot, weapon_type, weapon_color)
	
	if _logger:
		_logger.info("weapon", self, "⚔️ weapon stack attached: type=%s, level=%d, marker=%s" % [weapon_type, level, marker.name])

func _attach_weapon(weapon_type: String, weapon_color: Color, marker: Marker3D, stored_current_ammo: int = -1, stored_max_ammo: int = -1) -> void:
	var attach_start: int = Time.get_ticks_msec()
	if _logger:
		_logger.info("weapon", self, "⏱️ [TIMING START] _attach_weapon: type=%s" % weapon_type)
	
	# Load the appropriate weapon scene for this weapon type
	var weapon_scene_path: String = WeaponRegistry.get_weapon_scene_path(weapon_type)
	var weapon_scene: PackedScene = load(weapon_scene_path)
	
	if weapon_scene == null:
		if _logger:
			_logger.error("weapon", self, "❌ Failed to load weapon scene: %s" % weapon_scene_path)
		return
	
	# Instantiate the weapon
	var weapon_instance: Node = weapon_scene.instantiate()
	if weapon_instance == null or not weapon_instance is WeaponAttachment:
		if _logger:
			_logger.error("weapon", self, "❌ Failed to instantiate weapon attachment")
		return
	
	var weapon: WeaponAttachment = weapon_instance as WeaponAttachment
	weapon.weapon_type = weapon_type
	# Use color from registry if not provided
	if weapon_color == Color.WHITE:
		weapon.weapon_color = WeaponRegistry.get_weapon_color(weapon_type)
	else:
		weapon.weapon_color = weapon_color
	
	# Initialize ammo: use stored ammo if provided (from dropped weapon), otherwise use registry default
	if stored_current_ammo >= 0 and stored_max_ammo >= 0:
		weapon.max_ammo = stored_max_ammo
		weapon.current_ammo = stored_current_ammo
		if _logger:
			_logger.info("weapon", self, "📥 restoring weapon ammo from pickup: %d/%d" % [stored_current_ammo, stored_max_ammo])
	else:
		# Initialize ammo to full capacity (new pickup)
		weapon.max_ammo = WeaponRegistry.get_max_ammo(weapon_type)
		weapon.current_ammo = weapon.max_ammo
	
	# Add to scene tree first (required for reparenting)
	get_tree().root.add_child(weapon)
	
	# Attach to the marker
	weapon.attach_to_mount(_mount_controller, marker)
	
	# Determine which slot this marker belongs to
	var slot: int = WeaponSlotConstantsClass.Slot.LEFT if marker == _weapon_marker_left else WeaponSlotConstantsClass.Slot.RIGHT
	
	# Initialize stack array for this slot if needed
	if not _stacked_weapons.has(slot):
		_stacked_weapons[slot] = []
	
	# Clear existing weapons in slot before adding new one (shouldn't happen, but safety check)
	if _stacked_weapons[slot].size() > 0:
		if _logger:
			_logger.warn("weapon", self, "⚠️ WARNING: slot %d already has %d weapons! Clearing before adding new weapon." % [slot, _stacked_weapons[slot].size()])
		for existing_weapon in _stacked_weapons[slot]:
			if is_instance_valid(existing_weapon):
				# Remove from slot manager first
				if _slot_manager != null:
					_slot_manager.remove_weapon_from_slot(slot, existing_weapon)
				if marker.is_ancestor_of(existing_weapon):
					marker.remove_child(existing_weapon)
				existing_weapon.detach_from_mount()
				_attached_weapons.erase(existing_weapon)
		_stacked_weapons[slot].clear()
		# Sync slot manager - clear the slot completely
		if _slot_manager != null:
			_slot_manager.clear_slot(slot)
	
	# Add as first weapon in stack
	_stacked_weapons[slot].append(weapon)
	
	# Sync with slot manager
	if _slot_manager != null:
		_slot_manager.add_weapon_to_slot(slot, weapon)
	
	# Track the weapon
	_attached_weapons.append(weapon)
	
	# Connect ammo_changed signal to check for upgrade drops
	var slot_capture: int = slot
	var callable: Callable = func(new_ammo: int, max_ammo: int): check_upgrade_drops(slot_capture, new_ammo, max_ammo)
	if not weapon.ammo_changed.is_connected(callable):
		weapon.ammo_changed.connect(callable)
		if _logger:
			_logger.debug("weapon", self, "🔌 connected ammo_changed to check_upgrade_drops for slot %d using lambda" % slot)
	
	# Signal HUD update needed
	hud_update_needed.emit(slot)
	
	if _logger:
		_logger.info("weapon", self, "⚔️ weapon attached: type=%s, color=%s, marker=%s, ammo=%d/%d, slot=%d" % [weapon_type, weapon.weapon_color, marker.name, weapon.current_ammo, weapon.max_ammo, slot])

## Replace weapon in a slot
func replace_weapon_in_slot(slot: int, weapon_type: String, weapon_color: Color, weapon_level: int = 1) -> void:
	if _logger:
		_logger.info("weapon", self, "🔄 REPLACE_WEAPON_START: slot=%d, type=%s, level=%d" % [slot, weapon_type, weapon_level])
	
	var marker: Marker3D = null
	if slot == WeaponSlotConstantsClass.Slot.LEFT:
		marker = _weapon_marker_left
	elif slot == WeaponSlotConstantsClass.Slot.RIGHT:
		marker = _weapon_marker_right
	else:
		if _logger:
			_logger.error("weapon", self, "❌ Invalid weapon slot: %d" % slot)
		return
	
	if marker == null:
		if _logger:
			_logger.error("weapon", self, "❌ Marker for slot %d is null" % slot)
		return
	
	# Remove all stacked weapons at this marker (clear the stack)
	if _stacked_weapons.has(slot):
		var stack: Array = _stacked_weapons[slot]
		if _logger:
			_logger.info("weapon", self, "🗑️ REMOVING_STACK: slot=%d, stack_size=%d" % [slot, stack.size()])
		
		for weapon in stack:
			if is_instance_valid(weapon):
				# Remove from marker
				if marker.is_ancestor_of(weapon):
					marker.remove_child(weapon)
				weapon.detach_from_mount()
				_attached_weapons.erase(weapon)
		
		# Clear the stack
		_stacked_weapons[slot] = []
		if _logger:
			_logger.debug("weapon", self, "✅ stack cleared for slot %d" % slot)
		
		# Sync slot manager - clear the slot
		if _slot_manager != null:
			_slot_manager.clear_slot(slot)
	
	# Signal HUD update needed (clear cache)
	hud_update_needed.emit(slot)
	
	# Attach new weapon at the specified level
	if _logger:
		_logger.info("weapon", self, "➕ ATTACHING_NEW_WEAPON: slot=%d, type=%s, level=%d" % [slot, weapon_type, weapon_level])
	attach_weapon_at_level(weapon_type, weapon_color, marker, weapon_level)
	
	if _logger:
		_logger.info("weapon", self, "✅ REPLACE_WEAPON_COMPLETE: slot=%d" % slot)

## Upgrade weapon in a slot
func upgrade_weapon_in_slot(slot: int, weapon_type: String, weapon_color: Color) -> void:
	var upgrade_start: int = Time.get_ticks_msec()
	if _logger:
		_logger.info("weapon", self, "⏱️ [TIMING START] UPGRADING weapon in slot %d with: %s" % [slot, weapon_type])
	
	var marker: Marker3D = null
	if slot == WeaponSlotConstantsClass.Slot.LEFT:
		marker = _weapon_marker_left
	elif slot == WeaponSlotConstantsClass.Slot.RIGHT:
		marker = _weapon_marker_right
	else:
		if _logger:
			_logger.error("weapon", self, "❌ Invalid slot for upgrade: %d" % slot)
		return
	
	if marker == null:
		if _logger:
			_logger.error("weapon", self, "❌ Marker for slot %d is null" % slot)
		return
	
	# Get current stack count for this slot
	var stack_count: int = 0
	if _stacked_weapons.has(slot):
		stack_count = _stacked_weapons[slot].size()
	
	# Load and instantiate the new weapon
	var weapon_scene_path: String = WeaponRegistry.get_weapon_scene_path(weapon_type)
	var weapon_scene: PackedScene = load(weapon_scene_path)
	if weapon_scene == null:
		if _logger:
			_logger.error("weapon", self, "❌ Failed to load weapon scene: %s" % weapon_scene_path)
		return
	
	var weapon_instance: Node = weapon_scene.instantiate()
	if weapon_instance == null or not weapon_instance is WeaponAttachment:
		if _logger:
			_logger.error("weapon", self, "❌ Failed to instantiate weapon attachment")
		return
	
	var new_weapon: WeaponAttachment = weapon_instance as WeaponAttachment
	new_weapon.weapon_type = weapon_type
	if weapon_color == Color.WHITE:
		new_weapon.weapon_color = WeaponRegistry.get_weapon_color(weapon_type)
	else:
		new_weapon.weapon_color = weapon_color
	
	var base_max_ammo: int = WeaponRegistry.get_max_ammo(weapon_type)
	new_weapon.max_ammo = base_max_ammo
	new_weapon.current_ammo = base_max_ammo
	
	# Add to scene tree
	get_tree().root.add_child(new_weapon)
	
	# Attach to marker with vertical offset for stacking
	new_weapon.attach_to_mount(_mount_controller, marker)
	
	# Apply vertical offset based on stack count (stack weapons on top of each other)
	var stack_offset: float = 0.3 * stack_count  # 0.3 units per stack level
	new_weapon.position.y += stack_offset
	
	# Track in stacked weapons array
	if not _stacked_weapons.has(slot):
		_stacked_weapons[slot] = []
	_stacked_weapons[slot].append(new_weapon)
	
	# Sync with slot manager
	if _slot_manager != null:
		_slot_manager.add_weapon_to_slot(slot, new_weapon)
	
	_attached_weapons.append(new_weapon)
	
	# Merge ammo: add the new weapon's ammo to the base weapon
	var base_weapon: WeaponAttachment = _stacked_weapons[slot][0]
	if not is_instance_valid(base_weapon):
		if _logger:
			_logger.error("weapon", self, "❌ base_weapon is not valid during upgrade")
		return
	
	var old_max_ammo: int = base_weapon.max_ammo
	var old_current_ammo: int = base_weapon.current_ammo
	
	base_weapon.max_ammo += base_max_ammo
	base_weapon.current_ammo += base_max_ammo
	# Clamp ammo to ensure no negative values
	base_weapon.current_ammo = max(0, base_weapon.current_ammo)
	base_weapon.max_ammo = max(base_max_ammo, base_weapon.max_ammo)
	
	if _logger:
		_logger.info("weapon", self, "⬆️ MERGING AMMO: base_weapon.max_ammo %d -> %d (+%d)" % [old_max_ammo, base_weapon.max_ammo, base_max_ammo])
		_logger.info("weapon", self, "⬆️ MERGING AMMO: base_weapon.current_ammo %d -> %d (+%d)" % [old_current_ammo, base_weapon.current_ammo, base_max_ammo])
		_logger.info("weapon", self, "⬆️ UPGRADE COMPLETE: slot %d now has %d stacked weapons, total ammo=%d/%d" % [slot, _stacked_weapons[slot].size(), base_weapon.current_ammo, base_weapon.max_ammo])
	
	# Connect ammo_changed signal to check for upgrade drops
	var slot_capture: int = slot
	var callable: Callable = func(new_ammo: int, max_ammo: int): check_upgrade_drops(slot_capture, new_ammo, max_ammo)
	var signal_connected: bool = base_weapon.ammo_changed.is_connected(callable)
	if _logger:
		_logger.debug("weapon", self, "🔌 ammo_changed signal connected to check_upgrade_drops: %s" % str(signal_connected))
	if not signal_connected:
		base_weapon.ammo_changed.connect(callable)
		if _logger:
			_logger.info("weapon", self, "🔌 connected ammo_changed signal to check_upgrade_drops for slot %d using lambda" % slot)
	
	# Emit ammo changed signal to update HUD and trigger drop check
	if _logger:
		_logger.debug("weapon", self, "📡 emitting ammo_changed after upgrade: current_ammo=%d, max_ammo=%d" % [base_weapon.current_ammo, base_weapon.max_ammo])
	base_weapon.ammo_changed.emit(base_weapon.current_ammo, base_weapon.max_ammo)

## Check if ammo has dropped below thresholds that would cause upgrade drops
func check_upgrade_drops(slot: int, new_ammo: int, max_ammo: int) -> void:
	# Validate slot parameter
	if slot != 1 and slot != 2:
		if _logger:
			_logger.error("weapon", self, "❌ INVALID SLOT PARAMETER: slot=%d (expected 1 or 2). Signal binding issue detected!" % slot)
		return
	
	# Check if ammo has dropped below thresholds that would cause upgrade drops
	if not _stacked_weapons.has(slot):
		if _logger:
			_logger.debug("weapon", self, "🔍 no stack array for slot %d" % slot)
		return
	
	var stack: Array = _stacked_weapons[slot]
	
	# Skip upgrade drops if ammo is invalid (negative or zero max)
	if new_ammo < 0 or max_ammo <= 0:
		if _logger:
			_logger.debug("weapon", self, "⏭️ skipping upgrade drop check: invalid ammo (current=%d, max=%d)" % [new_ammo, max_ammo])
		return
	
	if stack.size() <= 1:
		return  # No upgrades to drop
	
	var base_weapon: WeaponAttachment = stack[0]
	if not is_instance_valid(base_weapon):
		if _logger:
			_logger.error("weapon", self, "❌ base weapon is not valid")
		return
	
	var base_max_ammo: int = WeaponRegistry.get_max_ammo(base_weapon.weapon_type)
	
	# Calculate how many upgrades should remain based on current ammo
	var expected_stack_size: int = 1  # Base weapon always remains
	if base_max_ammo > 0:
		var calculated_size: float = float(new_ammo) / float(base_max_ammo)
		var rounded_size: int = ceili(calculated_size)  # Round up
		expected_stack_size = max(1, min(rounded_size, stack.size()))  # Between 1 and current stack size
	else:
		expected_stack_size = 1
	
	# If we have more upgrades than we should, drop the excess
	if stack.size() > expected_stack_size:
		if _logger:
			_logger.info("weapon", self, "⬇️ NEED TO DROP UPGRADES: stack_size=%d > expected=%d (ammo=%d/%d)" % [stack.size(), expected_stack_size, new_ammo, max_ammo])
	
	while stack.size() > expected_stack_size:
		var top_weapon: WeaponAttachment = stack[stack.size() - 1]
		if _logger:
			_logger.info("weapon", self, "⬇️ DROPPING UPGRADE: slot %d, ammo=%d/%d, stack_size=%d -> %d, top_weapon_type=%s" % [slot, new_ammo, max_ammo, stack.size(), expected_stack_size, top_weapon.weapon_type])
		
		if not is_instance_valid(top_weapon):
			if _logger:
				_logger.error("weapon", self, "❌ top_weapon is not valid, removing from stack")
			stack.erase(top_weapon)
			continue
		
		# Remove from stack
		stack.erase(top_weapon)
		_attached_weapons.erase(top_weapon)
		if _logger:
			_logger.info("weapon", self, "✅ removed from stack and _attached_weapons")
		
		# Update base weapon ammo (subtract the dropped weapon's ammo)
		var old_max_ammo: int = base_weapon.max_ammo
		base_weapon.max_ammo -= base_max_ammo
		# Clamp max_ammo to at least base_max_ammo
		if base_weapon.max_ammo < base_max_ammo:
			base_weapon.max_ammo = base_max_ammo
		if _logger:
			_logger.info("weapon", self, "🔧 updated base_weapon.max_ammo: %d -> %d (subtracted %d)" % [old_max_ammo, base_weapon.max_ammo, base_max_ammo])
		
		# Clamp current_ammo to valid range [0, max_ammo]
		var old_current_ammo: int = base_weapon.current_ammo
		base_weapon.current_ammo = max(0, min(base_weapon.current_ammo, base_weapon.max_ammo))
		if old_current_ammo != base_weapon.current_ammo and _logger:
			_logger.info("weapon", self, "🔧 adjusted base_weapon.current_ammo: %d -> %d (clamped to [0, %d])" % [old_current_ammo, base_weapon.current_ammo, base_weapon.max_ammo])
		
		# Emit signal for dropping the weapon
		weapon_dropped.emit(top_weapon, slot)
		
		# Remove from scene
		var marker: Marker3D = _weapon_marker_left if slot == 1 else _weapon_marker_right
		if marker != null:
			if marker.is_ancestor_of(top_weapon):
				if _logger:
					_logger.info("weapon", self, "🗑️ removing top_weapon from marker children")
				marker.remove_child(top_weapon)
			elif _logger:
				_logger.warn("weapon", self, "⚠️ top_weapon is not a child of marker")
		elif _logger:
			_logger.error("weapon", self, "❌ marker is null for slot %d" % slot)
		
		if is_instance_valid(top_weapon):
			top_weapon.queue_free()
			if _logger:
				_logger.info("weapon", self, "🗑️ queued top_weapon for deletion")
		
		# Update HUD
		if _logger:
			_logger.info("weapon", self, "📺 emitting ammo_changed and updating HUD")
		base_weapon.ammo_changed.emit(base_weapon.current_ammo, base_weapon.max_ammo)
		hud_update_needed.emit(slot)
		
		if _logger:
			_logger.info("weapon", self, "✅ UPGRADE DROP COMPLETE: new stack_size=%d" % stack.size())

## Get weapon at a marker
func get_weapon_at_marker(marker: Marker3D) -> WeaponAttachment:
	# Get the base weapon (first in stack) for this marker
	var slot: int = 0
	if marker == _weapon_marker_left:
		slot = WeaponSlotConstantsClass.Slot.LEFT
	elif marker == _weapon_marker_right:
		slot = WeaponSlotConstantsClass.Slot.RIGHT
	
	if slot > 0 and _stacked_weapons.has(slot) and _stacked_weapons[slot].size() > 0:
		var base_weapon: WeaponAttachment = _stacked_weapons[slot][0]
		if is_instance_valid(base_weapon):
			return base_weapon
	
	return null

## Get stacked weapons for a slot
func get_stacked_weapons(slot: int) -> Array:
	if _stacked_weapons.has(slot):
		return _stacked_weapons[slot].duplicate()
	return []

## Detach all weapons from a slot (drop them as pickups)
func detach_weapon_slot(slot: int) -> void:
	if _logger:
		_logger.info("weapon", self, "🔓 DETACHING weapon slot %d (0 ammo click)" % slot)
	
	var marker: Marker3D = null
	if slot == WeaponSlotConstantsClass.Slot.LEFT:
		marker = _weapon_marker_left
	elif slot == WeaponSlotConstantsClass.Slot.RIGHT:
		marker = _weapon_marker_right
	else:
		if _logger:
			_logger.error("weapon", self, "❌ Invalid slot for detachment: %d" % slot)
		return
	
	if marker == null:
		if _logger:
			_logger.error("weapon", self, "❌ Marker for slot %d is null" % slot)
		return
	
	# Drop all weapons in the stack as pickups
	if _stacked_weapons.has(slot):
		var stack: Array = _stacked_weapons[slot]
		if _logger:
			_logger.info("weapon", self, "🔓 dropping %d weapons from slot %d as pickups" % [stack.size(), slot])
		
		# Drop weapons starting from the top (reverse order)
		for i in range(stack.size() - 1, -1, -1):
			var weapon: WeaponAttachment = stack[i]
			if is_instance_valid(weapon):
				# Emit signal for dropping
				weapon_dropped.emit(weapon, slot)
				
				# Remove from marker
				if marker.is_ancestor_of(weapon):
					marker.remove_child(weapon)
				
				# Remove from tracking arrays
				_attached_weapons.erase(weapon)
				
				# Queue for deletion
				weapon.queue_free()
				if _logger:
					_logger.debug("weapon", self, "🗑️ queued weapon %d for deletion" % i)
		
		# Clear the stack
		_stacked_weapons[slot] = []
		if _logger:
			_logger.info("weapon", self, "✅ all weapons detached from slot %d" % slot)
		
		# Signal HUD update needed
		hud_update_needed.emit(slot)
	else:
		if _logger:
			_logger.debug("weapon", self, "🔍 no weapons in slot %d to detach" % slot)

## Refill weapon in a slot
func refill_weapon_in_slot(slot: int) -> void:
	var marker: Marker3D = null
	if slot == WeaponSlotConstantsClass.Slot.LEFT:
		marker = _weapon_marker_left
	elif slot == WeaponSlotConstantsClass.Slot.RIGHT:
		marker = _weapon_marker_right
	
	var weapon: WeaponAttachment = get_weapon_at_marker(marker)
	if weapon == null:
		if _logger:
			_logger.error("weapon", self, "❌ Cannot refill: no weapon in slot %d" % slot)
		return
	
	if weapon.current_ammo >= weapon.max_ammo:
		if _logger:
			_logger.debug("weapon", self, "ℹ️ weapon in slot %d is already at full ammo" % slot)
		return
	
	if _logger:
		_logger.info("weapon", self, "🔋 refilling weapon in slot %d: %d/%d -> %d/%d" % [slot, weapon.current_ammo, weapon.max_ammo, weapon.max_ammo, weapon.max_ammo])
	weapon.current_ammo = weapon.max_ammo
	weapon.ammo_changed.emit(weapon.current_ammo, weapon.max_ammo)
	hud_update_needed.emit(slot)

