extends RefCounted
class_name WeaponSlotManager

# Preload constants
const WeaponSlotConstantsClass = preload("res://scripts/controllers/weapon_slot_constants.gd")

## Represents a weapon slot with its marker and stacked weapons
class SlotData:
	var slot_id: int
	var marker: Marker3D
	var weapons: Array[WeaponAttachment] = []
	
	func _init(p_slot_id: int, p_marker: Marker3D) -> void:
		slot_id = p_slot_id
		marker = p_marker
	
	func get_base_weapon() -> WeaponAttachment:
		if weapons.is_empty():
			return null
		var base: WeaponAttachment = weapons[0]
		if not is_instance_valid(base):
			return null
		return base
	
	func is_empty() -> bool:
		return weapons.is_empty() or get_base_weapon() == null
	
	func has_weapon_type(weapon_type: String) -> bool:
		var base: WeaponAttachment = get_base_weapon()
		return base != null and base.weapon_type == weapon_type

var _logger: Node
var _slots: Dictionary = {}  # Maps slot_id to SlotData
var _mount_controller: Node = null

func _init(mount_controller: Node, left_marker: Marker3D, right_marker: Marker3D, logger: Node) -> void:
	_mount_controller = mount_controller
	_logger = logger
	
	# Initialize slot data
	_slots[WeaponSlotConstantsClass.Slot.LEFT] = SlotData.new(WeaponSlotConstantsClass.Slot.LEFT, left_marker)
	_slots[WeaponSlotConstantsClass.Slot.RIGHT] = SlotData.new(WeaponSlotConstantsClass.Slot.RIGHT, right_marker)
	
	if _logger:
		_logger.debug("weapon", _mount_controller, "🔧 WeaponSlotManager initialized")

## Get slot data for a given slot ID
func get_slot(slot_id: int) -> SlotData:
	if not _slots.has(slot_id):
		if _logger:
			_logger.error("weapon", _mount_controller, "❌ Invalid slot ID: %d" % slot_id)
		return null
	return _slots[slot_id]

## Get all slots
func get_all_slots() -> Array[SlotData]:
	var result: Array[SlotData] = []
	for slot_data in _slots.values():
		result.append(slot_data)
	return result

## Find a slot containing a specific weapon type
func find_slot_with_weapon_type(weapon_type: String) -> SlotData:
	for slot_data in _slots.values():
		if slot_data.has_weapon_type(weapon_type):
			return slot_data
	return null

## Find an empty slot
func find_empty_slot() -> SlotData:
	for slot_data in _slots.values():
		if slot_data.is_empty():
			return slot_data
	return null

## Get weapon at a slot (returns base weapon)
func get_weapon_at_slot(slot_id: int) -> WeaponAttachment:
	var slot_data: SlotData = get_slot(slot_id)
	if slot_data == null:
		return null
	return slot_data.get_base_weapon()

## Add weapon to a slot's stack
func add_weapon_to_slot(slot_id: int, weapon: WeaponAttachment) -> void:
	var slot_data: SlotData = get_slot(slot_id)
	if slot_data == null:
		return
	
	if not slot_data.weapons.has(weapon):
		slot_data.weapons.append(weapon)
		if _logger:
			_logger.debug("weapon", _mount_controller, "➕ Added weapon to slot %d stack (size=%d)" % [slot_id, slot_data.weapons.size()])

## Remove weapon from a slot's stack
func remove_weapon_from_slot(slot_id: int, weapon: WeaponAttachment) -> void:
	var slot_data: SlotData = get_slot(slot_id)
	if slot_data == null:
		return
	
	var index: int = slot_data.weapons.find(weapon)
	if index >= 0:
		slot_data.weapons.remove_at(index)
		if _logger:
			_logger.debug("weapon", _mount_controller, "➖ Removed weapon from slot %d stack (size=%d)" % [slot_id, slot_data.weapons.size()])

## Clear all weapons from a slot
func clear_slot(slot_id: int) -> void:
	var slot_data: SlotData = get_slot(slot_id)
	if slot_data == null:
		return
	
	slot_data.weapons.clear()
	if _logger:
		_logger.debug("weapon", _mount_controller, "🗑️ Cleared slot %d" % slot_id)

## Get stack count for a slot
func get_stack_count(slot_id: int) -> int:
	var slot_data: SlotData = get_slot(slot_id)
	if slot_data == null:
		return 0
	return slot_data.weapons.size()

## Check if all slots are full
func all_slots_full() -> bool:
	for slot_data in _slots.values():
		if slot_data.is_empty():
			return false
	return true
