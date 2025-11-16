extends CanvasLayer
class_name HUD

@onready var _mount_bar: ProgressBar = $MountHealth
@onready var _rider_bar: ProgressBar = $RiderHealth
@onready var _weapon_label: Label = $WeaponLabel
@onready var _lock_label: Label = $LockOnLabel
@onready var _speed_label: Label = $SpeedLabel
@onready var _controls_label: RichTextLabel = $ControlsPanel/Controls
var _weapon: Weapon = null
@onready var _services: Services = get_node_or_null("/root/Services")
@onready var _logger = _services.logger() if _services != null else get_node_or_null("/root/LoggerInstance")
@onready var _bus: EventBus = _services.bus() if _services != null else get_node_or_null("/root/EventBus")
var _player_name: String = ""

func _ready() -> void:
	_logger.info("scene", self, "🧭 HUD ready; binding to player and sub-systems…")
	# Visual defaults for clarity
	_mount_bar.add_theme_color_override("font_color", Color(1,1,1,1))
	_mount_bar.add_theme_color_override("fg", Color(0.9,0.2,0.2,1))
	_rider_bar.add_theme_color_override("font_color", Color(1,1,1,1))
	_rider_bar.add_theme_color_override("fg", Color(0.2,0.7,1.0,1))
	_weapon_label.modulate = Color(1,1,1,1)
	_lock_label.modulate = Color(1,1,0.3,1)
	_speed_label.modulate = Color(0.6,1,0.6,1)
	if is_instance_valid(_controls_label):
		_controls_label.bbcode_enabled = true
		_controls_label.text = "[b]Controls[/b]\nW/S: Accelerate/Brake\nA/D: Turn\nLMB: Fire\nR: Reset Camera\nEsc: Pause"
	var player: Node = get_tree().get_first_node_in_group("players")
	if player == null:
		_logger.warn("scene", self, "No node in group 'players' found; HUD will show defaults")
		return
	_player_name = String(player.name)
	# Health hookup
	var health: Node = player.get_node_or_null("Health")
	if health and health.has_signal("health_changed"):
		if not _logger.safe_connect_signal("scene", self, health, "health_changed", self, "_on_health_changed"):
			_logger.warn("scene", self, "Failed to connect health_changed; using current values only")
		# initialize bars with current values and max (assume Health script present)
		_mount_bar.max_value = float(health.mount_hp_max)
		_rider_bar.max_value = float(health.rider_hp_max)
		_mount_bar.value = float(health.mount_hp)
		_rider_bar.value = float(health.rider_hp)
		_mount_bar.show_percentage = true
		_rider_bar.show_percentage = true
	else:
		_logger.warn("scene", self, "No 'Health' node or missing 'health_changed' signal on player")
	# Global bus health as fallback if provided by game
	if _bus and _bus.has_signal("player_health_changed"):
		_bus.connect("player_health_changed", Callable(self, "_on_health_changed"))
	# Movement speed from global bus
	if _bus and _bus.has_signal("movement_intent"):
		_bus.connect("movement_intent", Callable(self, "_on_speed_intent"))
	else:
		_speed_label.text = "Speed: 0"
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
	var targeting: Node = player.get_node_or_null("Targeting")
	if targeting and targeting.has_signal("target_changed"):
		_logger.safe_connect_signal("combat", self, targeting, "target_changed", self, "_on_target_changed")
		_lock_label.text = "Lock: None"
	else:
		_logger.debug("combat", self, "No targeting system present; lock label stays 'None'")
		_lock_label.text = "Lock: None"
	# Global bus for decoupled targeting updates
	if _bus and _bus.has_signal("target_changed"):
		_bus.connect("target_changed", Callable(self, "_on_target_changed"))
	# Initialize labels
	_weapon_label.text = "Weapon: None | Ammo: 0"
	_lock_label.text = "Lock: None"
	_speed_label.text = "Speed: 0.0"

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

func _on_speed_intent(name: String, speed: float) -> void:
	if name != _player_name:
		return
	_speed_label.text = "Speed: %.1f" % speed
