extends Node
class_name UtilityAI

## Simple needs-based utility AI core.
## Evaluates named needs and returns scores (0..1), then selects the best behavior.

const EPS: float = 0.0001

static func evaluate_scores(context: Dictionary) -> Dictionary:
	# context expects: {"mount": CharacterBody3D, "target": Node3D, "logger": Node, "bus": Node}
	var scores: Dictionary = {}
	var mount: CharacterBody3D = context.get("mount", null)
	var target: Node3D = context.get("target", null)
	if mount == null:
		return {"idle": 1.0}
	# Distance to target if any
	var dist: float = 9999.0
	if target != null:
		var mp: Vector3 = mount.global_transform.origin
		var tp: Vector3 = target.global_transform.origin
		var d: Vector3 = tp - mp
		d.y = 0.0
		dist = d.length()
	# Basic signals used by scoring
	var has_target: bool = target != null
	var has_ammo: bool = _has_any_ammo(mount)
	# Tunables
	var OPT_RANGE_MIN: float = 8.0
	var OPT_RANGE_MAX: float = 24.0
	var TOO_CLOSE: float = 5.0
	var TOO_FAR: float = 36.0
	# Needs
	var need_chase: float = 0.0
	if has_target:
		if dist > OPT_RANGE_MAX:
			# farther than optimal -> high chase pressure up to TOO_FAR
			need_chase = clamp((dist - OPT_RANGE_MAX) / max(TOO_FAR - OPT_RANGE_MAX, EPS), 0.0, 1.0)
		else:
			need_chase = 0.2 if dist > OPT_RANGE_MIN else 0.0
	scores["chase"] = need_chase
	var need_attack: float = 0.0
	if has_target and has_ammo and dist >= OPT_RANGE_MIN and dist <= OPT_RANGE_MAX:
		# Inside sweet spot, highest desire
		need_attack = 1.0
	elif has_target and has_ammo and dist < OPT_RANGE_MIN:
		# Slightly too close but still okay to fire sometimes
		need_attack = 0.5
	scores["attack"] = need_attack
	var need_strafe: float = 0.0
	if has_target and dist >= OPT_RANGE_MIN and dist <= OPT_RANGE_MAX:
		need_strafe = 0.6
	scores["strafe"] = need_strafe
	var need_evade: float = 0.0
	if has_target and (dist < TOO_CLOSE or (not has_ammo and dist < OPT_RANGE_MAX)):
		need_evade = 0.8
	scores["evade"] = need_evade
	# Fallback patrol/idle
	var base_idle: float = 0.1
	scores["patrol"] = base_idle if not has_target else 0.0
	scores["idle"] = 0.05
	return scores

static func select_best(scores: Dictionary) -> String:
	var best_name: String = "idle"
	var best_score: float = -1.0
	for k in scores.keys():
		var s: float = float(scores[k])
		if s > best_score:
			best_score = s
			best_name = String(k)
	return best_name

static func _has_any_ammo(mount: CharacterBody3D) -> bool:
	# Look for child Weapons and check ammo
	if mount == null:
		return false
	for c in mount.get_children():
		if c is Node and c.has_method("can_fire"):
			if c.call("can_fire"):
				return true
	return false


