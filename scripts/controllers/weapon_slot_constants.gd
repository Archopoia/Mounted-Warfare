extends RefCounted
class_name WeaponSlotConstants

## Weapon slot identifiers
enum Slot {
	LEFT = 1,
	RIGHT = 2
}

## Maximum number of weapon slots per mount
const MAX_SLOTS: int = 2

## Stack offset distance between stacked weapons (in units)
const STACK_OFFSET: float = 0.3

## Convert slot enum to string name
static func slot_to_name(slot: Slot) -> String:
	match slot:
		Slot.LEFT:
			return "left"
		Slot.RIGHT:
			return "right"
		_:
			return "unknown"

## Validate if a slot ID is valid
static func is_valid_slot(slot: int) -> bool:
	return slot == Slot.LEFT or slot == Slot.RIGHT

