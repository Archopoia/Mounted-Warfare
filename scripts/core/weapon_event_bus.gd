extends Node

## Global event bus for weapon-related signals
## Use this to decouple weapon pickup, upgrade, and replacement logic
class_name WeaponEventBus

## Emitted when a weapon pickup is collected (before processing)
## pickup: The WeaponPickup that was collected
## mount: The MountController that collected it
## weapon_type: Type of weapon collected
## weapon_level: Level of weapon collected
signal weapon_pickup_collected(pickup: WeaponPickup, mount: MountController, weapon_type: String, weapon_level: int)

## Emitted when a weapon is attached to a slot
## mount: The MountController
## slot: Slot ID (1 = left, 2 = right)
## weapon: The WeaponAttachment that was attached
signal weapon_attached(mount: MountController, slot: int, weapon: WeaponAttachment)

## Emitted when a weapon is detached from a slot
## mount: The MountController
## slot: Slot ID
## weapon: The WeaponAttachment that was detached
signal weapon_detached(mount: MountController, slot: int, weapon: WeaponAttachment)

## Emitted when a weapon is refilled
## mount: The MountController
## slot: Slot ID
## weapon: The WeaponAttachment that was refilled
## ammo_before: Ammo count before refill
## ammo_after: Ammo count after refill
signal weapon_refilled(mount: MountController, slot: int, weapon: WeaponAttachment, ammo_before: int, ammo_after: int)

## Emitted when a weapon is upgraded
## mount: The MountController
## slot: Slot ID
## weapon: The WeaponAttachment that was upgraded
## level_before: Stack level before upgrade
## level_after: Stack level after upgrade
signal weapon_upgraded(mount: MountController, slot: int, weapon: WeaponAttachment, level_before: int, level_after: int)

## Emitted when a weapon is replaced
## mount: The MountController
## slot: Slot ID
## old_weapon_type: Type of weapon that was replaced
## new_weapon_type: Type of weapon that replaced it
signal weapon_replaced(mount: MountController, slot: int, old_weapon_type: String, new_weapon_type: String)

# Singleton instance (set in autoload)
static var instance: WeaponEventBus = null

func _ready() -> void:
	WeaponEventBus.instance = self

func _exit_tree() -> void:
	if WeaponEventBus.instance == self:
		WeaponEventBus.instance = null

