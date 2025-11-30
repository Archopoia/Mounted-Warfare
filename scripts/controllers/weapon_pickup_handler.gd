extends RefCounted
class_name WeaponPickupHandler

# Preload helper classes
const WeaponSlotConstantsClass = preload("res://scripts/controllers/weapon_slot_constants.gd")
const WeaponSlotManagerClass = preload("res://scripts/controllers/weapon_slot_manager.gd")

## Result of processing a weapon pickup
enum PickupResult {
	ATTACHED_TO_EMPTY_SLOT,
	REFILLED_EXISTING,
	UPGRADED_EXISTING,
	NEEDS_PLAYER_CHOICE,  # Player must choose replace/upgrade/etc.
	AUTO_REPLACED,
	AUTO_UPGRADED
}

## Decision context for pickup processing
class PickupDecision:
	var result: PickupResult
	var target_slot: int = 0
	var weapon_level: int = 1  # Store the weapon level for upgrades
	var can_refill: bool = false
	var can_upgrade: bool = false
	var can_replace: bool = false
	var can_attach_to_free: bool = false
	var upgrade_slots: Array[int] = []
	var free_slot: int = 0
	
	func _init() -> void:
		upgrade_slots = []

var _logger: Node
var _mount_controller: Node = null
var _slot_manager: WeaponSlotManagerClass = null

func _init(mount_controller: Node, slot_manager: WeaponSlotManagerClass, logger: Node) -> void:
	_mount_controller = mount_controller
	_slot_manager = slot_manager
	_logger = logger
	
	if _logger:
		_logger.debug("weapon", _mount_controller, "🔧 WeaponPickupHandler initialized")

## Process a weapon pickup and return decision context
func process_pickup(weapon_type: String, weapon_level: int, _pickup_color: Color, _stored_current_ammo: int = -1, _stored_max_ammo: int = -1) -> PickupDecision:
	var decision: PickupDecision = PickupDecision.new()
	decision.weapon_level = weapon_level  # Store weapon level in decision
	
	# Find existing weapon of same type
	var existing_slot: WeaponSlotManagerClass.SlotData = _slot_manager.find_slot_with_weapon_type(weapon_type)
	var empty_slot: WeaponSlotManagerClass.SlotData = _slot_manager.find_empty_slot()
	
	# Check if we have matching weapon type
	if existing_slot != null:
		var base_weapon: WeaponAttachment = existing_slot.get_base_weapon()
		if base_weapon == null:
			if _logger:
				_logger.error("weapon", _mount_controller, "❌ Existing slot has no base weapon")
			return decision
		
		# Check if weapon needs refill
		var needs_refill: bool = base_weapon.current_ammo < base_weapon.max_ammo
		
		if needs_refill:
			# Can refill and potentially upgrade
			decision.can_refill = true
			decision.target_slot = existing_slot.slot_id
			
			if weapon_level > 1:
				decision.can_upgrade = true
			
			# For non-player mounts, auto-refill and upgrade
			if not _mount_controller.is_player:
				if weapon_level > 1:
					decision.result = PickupResult.UPGRADED_EXISTING
				else:
					decision.result = PickupResult.REFILLED_EXISTING
				return decision
			
			# Player mounts need choice if level > 1
			if weapon_level > 1:
				decision.result = PickupResult.NEEDS_PLAYER_CHOICE
				decision.upgrade_slots.append(existing_slot.slot_id)
			else:
				decision.result = PickupResult.REFILLED_EXISTING
			
			return decision
		
		# Weapon is at full ammo - check for upgrade or free slot
		decision.can_upgrade = true
		decision.upgrade_slots.append(existing_slot.slot_id)
		
		# Check if there's a free slot for the same weapon type
		if empty_slot != null:
			decision.can_attach_to_free = true
			decision.free_slot = empty_slot.slot_id
		
		# For non-player mounts, auto-upgrade
		if not _mount_controller.is_player:
			decision.result = PickupResult.AUTO_UPGRADED
			decision.target_slot = existing_slot.slot_id
			return decision
		
		# Player mounts need choice
		decision.result = PickupResult.NEEDS_PLAYER_CHOICE
		return decision
	
	# No matching weapon type - check for empty slot
	if empty_slot != null:
		decision.can_attach_to_free = true
		decision.target_slot = empty_slot.slot_id
		
		if not _mount_controller.is_player:
			decision.result = PickupResult.ATTACHED_TO_EMPTY_SLOT
		else:
			# Even for players, attach to empty slot automatically if available
			decision.result = PickupResult.ATTACHED_TO_EMPTY_SLOT
		
		return decision
	
	# All slots are full - must replace
	if _slot_manager.all_slots_full():
		decision.can_replace = true
		
		# Mark all slots as replaceable
		for slot_data in _slot_manager.get_all_slots():
			if slot_data.slot_id != 0:  # Valid slot
				decision.upgrade_slots.append(slot_data.slot_id)
		
		# For non-player mounts, auto-replace left slot
		if not _mount_controller.is_player:
			decision.result = PickupResult.AUTO_REPLACED
			decision.target_slot = WeaponSlotConstantsClass.Slot.LEFT
			return decision
		
		# Player mounts need choice
		decision.result = PickupResult.NEEDS_PLAYER_CHOICE
		return decision
	
	if _logger:
		_logger.warn("weapon", _mount_controller, "⚠️ Unexpected state in pickup processing")
	
	return decision

## Apply pickup decision (called after decision is made)
func apply_decision(decision: PickupDecision, weapon_type: String, weapon_level: int, pickup_color: Color, stored_current_ammo: int = -1, stored_max_ammo: int = -1) -> void:
	match decision.result:
		PickupResult.ATTACHED_TO_EMPTY_SLOT:
			_attach_to_slot(decision.target_slot, weapon_type, weapon_level, pickup_color, stored_current_ammo, stored_max_ammo)
		
		PickupResult.REFILLED_EXISTING:
			_refill_and_upgrade_slot(decision.target_slot, weapon_type, weapon_level, pickup_color, stored_current_ammo, stored_max_ammo, false)
		
		PickupResult.UPGRADED_EXISTING:
			_refill_and_upgrade_slot(decision.target_slot, weapon_type, weapon_level, pickup_color, stored_current_ammo, stored_max_ammo, true)
		
		PickupResult.AUTO_REPLACED:
			_replace_slot(decision.target_slot, weapon_type, weapon_level, pickup_color)
		
		PickupResult.AUTO_UPGRADED:
			_upgrade_slot_multiple(decision.target_slot, weapon_type, weapon_level, pickup_color)
		
		PickupResult.NEEDS_PLAYER_CHOICE:
			# This should be handled by UI prompt, but store pending data
			if _logger:
				_logger.debug("weapon", _mount_controller, "📋 Player choice needed for pickup")
			# Store pending data in mount controller (will be handled there)

func _attach_to_slot(slot_id: int, weapon_type: String, weapon_level: int, weapon_color: Color, stored_current_ammo: int, stored_max_ammo: int) -> void:
	if _mount_controller.has_method("_attach_weapon_at_level"):
		var slot_data: WeaponSlotManagerClass.SlotData = _slot_manager.get_slot(slot_id)
		if slot_data == null or slot_data.marker == null:
			return
		_mount_controller._attach_weapon_at_level(weapon_type, weapon_color, slot_data.marker, weapon_level, stored_current_ammo, stored_max_ammo)

func _refill_and_upgrade_slot(slot_id: int, weapon_type: String, weapon_level: int, weapon_color: Color, _stored_current_ammo: int, _stored_max_ammo: int, apply_upgrades: bool = true) -> void:
	var base_weapon: WeaponAttachment = _slot_manager.get_weapon_at_slot(slot_id)
	if base_weapon == null:
		return
	
	var old_ammo: int = base_weapon.current_ammo
	
	# Refill missing ammo first (if any)
	var missing_ammo: int = base_weapon.max_ammo - base_weapon.current_ammo
	if missing_ammo > 0:
		base_weapon.current_ammo = base_weapon.max_ammo
		base_weapon.ammo_changed.emit(base_weapon.current_ammo, base_weapon.max_ammo)
		if _logger:
			_logger.info("weapon", _mount_controller, "🔋 Refilled weapon in slot %d: %d -> %d/%d" % [slot_id, old_ammo, base_weapon.current_ammo, base_weapon.max_ammo])
	
	# Apply upgrades if requested and level > 1
	if apply_upgrades and weapon_level > 1:
		# First upgrade uses 1 level (after refill), remaining levels for additional upgrades
		# Upgrade once first (uses 1 level)
		_upgrade_slot_multiple(slot_id, weapon_type, 1, weapon_color)
		
		# Get updated weapon after first upgrade
		base_weapon = _slot_manager.get_weapon_at_slot(slot_id)
		if base_weapon == null:
			return
		
		# Apply remaining upgrades (weapon_level - 2, since 1 was used for refill logic above and 1 for first upgrade)
		var remaining_levels: int = max(0, weapon_level - 2)
		if remaining_levels > 0:
			if _logger:
				_logger.info("weapon", _mount_controller, "⬆️ Applying %d additional upgrades to slot %d" % [remaining_levels, slot_id])
			_upgrade_slot_multiple(slot_id, weapon_type, remaining_levels, weapon_color)
			
			# Get final weapon state
			base_weapon = _slot_manager.get_weapon_at_slot(slot_id)
			if base_weapon != null and _logger:
				_logger.info("weapon", _mount_controller, "✅ Final weapon state: slot %d, ammo %d/%d" % [slot_id, base_weapon.current_ammo, base_weapon.max_ammo])

func _upgrade_slot_multiple(slot_id: int, weapon_type: String, levels: int, weapon_color: Color) -> void:
	if _mount_controller.has_method("_upgrade_weapon_in_slot"):
		for i in range(levels):
			_mount_controller._upgrade_weapon_in_slot(slot_id, weapon_type, weapon_color)

func _replace_slot(slot_id: int, weapon_type: String, weapon_level: int, weapon_color: Color) -> void:
	if _mount_controller.has_method("replace_weapon_in_slot"):
		_mount_controller.replace_weapon_in_slot(slot_id, weapon_type, weapon_color, weapon_level)

