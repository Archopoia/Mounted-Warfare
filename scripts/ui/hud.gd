extends CanvasLayer
class_name HUD

@onready var _mount_bar: ProgressBar = $MountHealth
@onready var _rider_bar: ProgressBar = $RiderHealth
@onready var _weapon_label: Label = $WeaponLabel
@onready var _lock_label: Label = $LockOnLabel
var _weapon: Weapon = null
@onready var _logger = get_node("/root/LoggerInstance")

func _ready() -> void:
	_logger.info("scene", self, "🧭 HUD ready; binding to player and sub-systems…")
	var player := get_tree().get_first_node_in_group("players")
	if player == null:
		_logger.warn("scene", self, "No node in group 'players' found; HUD will show defaults")
		return
	# Health hookup
	var health := player.get_node_or_null("Health")
	if health and health.has_signal("health_changed"):
		if not _logger.safe_connect_signal("scene", self, health, "health_changed", self, "_on_health_changed"):
			_logger.warn("scene", self, "Failed to connect health_changed; using current values only")
		_on_health_changed(health.mount_hp, health.rider_hp)
	else:
		_logger.warn("scene", self, "No 'Health' node or missing 'health_changed' signal on player")
	# Weapon hookup (first child in group "weapons" if any)
	var weapon_node: Node = get_tree().get_first_node_in_group("weapons")
	if weapon_node == null:
		# fallback: search under player for a node of class Weapon
		for child in player.get_children():
			if child is Weapon:
				weapon_node = child
				break
	_weapon = weapon_node as Weapon
	if _weapon and _weapon.has_signal("ammo_changed"):
		_logger.safe_connect_signal("combat", self, _weapon, "ammo_changed", self, "_on_ammo_changed")
		_update_weapon_label()
	else:
		if _weapon == null:
			_logger.warn("combat", self, "No Weapon found; HUD will display 'None'")
		else:
			_logger.warn("combat", self, "Weapon missing 'ammo_changed' signal; label may not update")
		_weapon_label.text = "Weapon: None | Ammo: 0"
	# Lock-on hookup (optional Targeting node emitting target_changed(name: String))
	var targeting := player.get_node_or_null("Targeting")
	if targeting and targeting.has_signal("target_changed"):
		_logger.safe_connect_signal("combat", self, targeting, "target_changed", self, "_on_target_changed")
		_lock_label.text = "Lock: None"
	else:
		_logger.debug("combat", self, "No targeting system present; lock label stays 'None'")
		_lock_label.text = "Lock: None"

func _on_health_changed(mount_hp: float, rider_hp: float) -> void:
	_mount_bar.value = mount_hp
	_rider_bar.value = rider_hp

func _on_ammo_changed(_current: int) -> void:
	_update_weapon_label()

func _update_weapon_label() -> void:
	if _weapon == null:
		_weapon_label.text = "Weapon: None | Ammo: 0"
		return
	var weapon_name := _weapon.name
	var ammo := int(_weapon.ammo_current)
	_weapon_label.text = "Weapon: %s | Ammo: %d" % [weapon_name, ammo]

func _on_target_changed(target_name: String) -> void:
	_lock_label.text = "Lock: %s" % target_name
