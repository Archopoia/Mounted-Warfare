extends Node
class_name EventBus

# Global, typed signals for loose coupling
signal ammo_changed(actor_name: String, current: int)
signal weapon_fired(actor_name: String)
signal player_health_changed(mount_hp: float, rider_hp: float)
signal target_changed(target_name: String)
signal movement_intent(name: String, speed: float)
signal ai_decision(actor_name: String, intent: String)
signal ai_scores(actor_name: String, scores: Dictionary)

func emit_ammo_changed(actor: Node, current: int) -> void:
	var actor_name: String = "unknown"
	if actor != null:
		actor_name = String(actor.name)
	emit_signal("ammo_changed", actor_name, current)

func emit_weapon_fired(actor: Node) -> void:
	var actor_name: String = "unknown"
	if actor != null:
		actor_name = String(actor.name)
	emit_signal("weapon_fired", actor_name)

func emit_player_health_changed(mount_hp: float, rider_hp: float) -> void:
	emit_signal("player_health_changed", mount_hp, rider_hp)

func emit_target_changed(target_name: String) -> void:
	emit_signal("target_changed", target_name)

func emit_movement_intent(mover_name: String, speed: float) -> void:
	emit_signal("movement_intent", mover_name, speed)

func emit_ai_decision(actor_name: String, intent: String) -> void:
	emit_signal("ai_decision", actor_name, intent)

func emit_ai_scores(actor_name: String, scores: Dictionary) -> void:
	emit_signal("ai_scores", actor_name, scores)
