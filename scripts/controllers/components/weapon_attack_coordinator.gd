extends Node
class_name WeaponAttackCoordinator

## Coordinates weapon attacks, handling stacked weapons and ammo consumption
## Works with WeaponManager to perform attacks

var _mount_controller: MountController = null
var _weapon_manager: WeaponManager = null
var _logger: Node = null

func initialize(mount_controller: MountController, weapon_manager: WeaponManager, logger: Node) -> void:
	_mount_controller = mount_controller
	_weapon_manager = weapon_manager
	_logger = logger
	
	if _logger:
		_logger.debug("weapon", self, "🔧 WeaponAttackCoordinator initialized")

## Perform primary attack with slot's stacked weapons
func attack_with_slot(slot: int) -> void:
	var stacked_weapons: Array = _weapon_manager.get_stacked_weapons(slot)
	if stacked_weapons.is_empty():
		if _logger:
			_logger.debug("weapon", self, "⚠️ cannot attack: no weapons in slot %d" % slot)
		return
	
	# Create a copy of weapons to fire BEFORE iterating (stack may be modified during attack)
	var weapons_to_fire: Array[WeaponAttachment] = []
	for weapon in stacked_weapons:
		if is_instance_valid(weapon):
			weapons_to_fire.append(weapon)
	
	if weapons_to_fire.is_empty():
		if _logger:
			_logger.debug("weapon", self, "⚠️ no valid weapons to fire in slot %d" % slot)
		return
	
	var base_weapon: WeaponAttachment = weapons_to_fire[0]
	var stack_count: int = weapons_to_fire.size()
	
	# Calculate total ammo consumption (projectile_count per weapon in stack)
	var projectile_count_per_weapon: int = WeaponRegistry.get_projectile_count(base_weapon.weapon_type)
	var total_projectiles_needed: int = projectile_count_per_weapon * stack_count
	
	if _logger:
		_logger.info("weapon", self, "🎯 attacking with %d stacked weapons in slot %d (will consume %d ammo: %d per weapon × %d weapons)" % [stack_count, slot, total_projectiles_needed, projectile_count_per_weapon, stack_count])
	
	# Check if we have 0 ammo - detach weapon completely
	if base_weapon.current_ammo <= 0:
		if _logger:
			_logger.info("weapon", self, "🔓 weapon has 0 ammo - detaching all weapons from slot %d" % slot)
		_weapon_manager.detach_weapon_slot(slot)
		return
	
	# Check if we have enough ammo for all weapons
	if base_weapon.current_ammo < total_projectiles_needed:
		if _logger:
			_logger.info("weapon", self, "⚠️ insufficient ammo: have %d, need %d (for %d weapons)" % [base_weapon.current_ammo, total_projectiles_needed, stack_count])
		# Don't fire if we don't have enough ammo
		return
	
	# Consume ammo based on stack count
	var old_ammo: int = base_weapon.current_ammo
	base_weapon.current_ammo -= total_projectiles_needed
	# Clamp ammo to prevent negative values
	base_weapon.current_ammo = max(0, base_weapon.current_ammo)
	if _logger:
		_logger.info("weapon", self, "🔋 consumed %d ammo (%d per weapon × %d weapons): %d -> %d" % [total_projectiles_needed, projectile_count_per_weapon, stack_count, old_ammo, base_weapon.current_ammo])
	
	# Fire all weapons
	for i in range(weapons_to_fire.size()):
		var weapon: WeaponAttachment = weapons_to_fire[i]
		if not is_instance_valid(weapon):
			if _logger:
				_logger.warn("weapon", self, "⚠️ weapon at index %d became invalid during attack" % i)
			continue
		
		if not weapon.is_inside_tree():
			if _logger:
				_logger.debug("weapon", self, "⚠️ weapon at index %d not in scene tree, skipping" % i)
			continue
		
		# Visual feedback for all weapons
		if slot == 2:  # Right slot only (left slot doesn't have visual feedback in original code)
			weapon._flicker_weapon_red()
		
		# Fire without consuming ammo (ammo already consumed above)
		weapon.fire_without_consuming_ammo()
	
	# Emit ammo changed signal after all weapons have fired
	base_weapon.ammo_changed.emit(base_weapon.current_ammo, base_weapon.max_ammo)
	
	# Check if ammo is depleted
	if base_weapon.current_ammo <= 0:
		base_weapon.ammo_depleted.emit(base_weapon.weapon_type)

## Start secondary attack for a slot
func start_secondary_attack(slot: int) -> void:
	var stacked_weapons: Array = _weapon_manager.get_stacked_weapons(slot)
	if stacked_weapons.is_empty():
		return
	
	# Start secondary attack for base weapon only (it will track charge levels)
	var base_weapon: WeaponAttachment = stacked_weapons[0]
	if is_instance_valid(base_weapon):
		base_weapon.start_secondary_attack()
		# Start flickering the first weapon (level 1)
		base_weapon._start_charging_visual_feedback()
		if _logger:
			_logger.info("weapon", self, "⚡ started secondary attack charge for slot %d" % slot)

## Update secondary charge for a slot
func update_secondary_charge(slot: int, delta: float) -> void:
	var stacked_weapons: Array = _weapon_manager.get_stacked_weapons(slot)
	if stacked_weapons.is_empty():
		return
	
	# Update charge for base weapon (consumes ammo and calculates levels)
	var base_weapon: WeaponAttachment = stacked_weapons[0]
	if is_instance_valid(base_weapon):
		base_weapon.update_secondary_charge(delta)

## Release secondary attack for a slot
func release_secondary_attack(slot: int) -> void:
	var stacked_weapons: Array = _weapon_manager.get_stacked_weapons(slot)
	if stacked_weapons.is_empty():
		return
	
	var stack_count: int = stacked_weapons.size()
	
	# Release secondary attack with stack count multiplier
	var base_weapon: WeaponAttachment = stacked_weapons[0]
	if is_instance_valid(base_weapon):
		base_weapon.release_secondary_attack(stack_count)
		
		# Stop visual feedback for all weapons
		for i in range(stack_count):
			var weapon: WeaponAttachment = stacked_weapons[i]
			if is_instance_valid(weapon):
				weapon._stop_charging_visual_feedback()
		if _logger:
			_logger.info("weapon", self, "⚡ released secondary attack with %d stacked weapons in slot %d" % [stack_count, slot])

## Handle charge level update from weapon
func update_secondary_charge_level(weapon: WeaponAttachment, charge_level: int) -> void:
	# Find which slot this weapon belongs to
	var slot: int = 0
	for s in [1, 2]:
		var stacked: Array = _weapon_manager.get_stacked_weapons(s)
		for i in range(stacked.size()):
			if stacked[i] == weapon:
				slot = s
				break
		if slot > 0:
			break
	
	if slot == 0:
		return
	
	# Get the stack for this slot
	var stack: Array = _weapon_manager.get_stacked_weapons(slot)
	
	# Flicker ALL weapons up to and including the current charge level
	for level in range(1, charge_level + 1):
		var weapon_index: int = level - 1  # Convert 1-indexed level to 0-indexed array
		
		if weapon_index >= 0 and weapon_index < stack.size():
			var weapon_to_flicker: WeaponAttachment = stack[weapon_index]
			if is_instance_valid(weapon_to_flicker):
				# Stop any existing flicker (in case it was already flickering)
				weapon_to_flicker._stop_charging_visual_feedback()
				# Start flickering this weapon
				weapon_to_flicker._start_charging_visual_feedback()
	
	if _logger:
		_logger.info("weapon", self, "⚡ charge level %d reached - flickering weapons 0-%d in slot %d" % [charge_level, charge_level - 1, slot])

