extends Label3D
class_name BotDebugLabel3D

@export var actor_name: String = ""
@export var target_path: NodePath = NodePath("")
@onready var _services: Node = get_node_or_null("/root/Services")
@onready var _bus: Node = _services.bus() if _services != null else get_node_or_null("/root/EventBus")
@onready var _target: Node3D = get_node_or_null(target_path)

var _last_behavior: String = "idle"
var _scores: Dictionary = {}

func _ready() -> void:
	visible = true
	# Default actor name to our owner's name
	if actor_name == "":
		actor_name = get_parent().name
	# Improve readability in world
	pixel_size = 0.004
	modulate = Color(0.2, 0.8, 1.0, 1.0)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Try resolve target to the player if not set
	if _target == null:
		var p := get_tree().get_first_node_in_group("players")
		if p and p is Node3D:
			_target = p
	# Subscribe to AI bus events
	if _bus and _bus.has_signal("ai_decision"):
		_bus.connect("ai_decision", Callable(self, "_on_ai_decision"))
	if _bus and _bus.has_signal("ai_scores"):
		_bus.connect("ai_scores", Callable(self, "_on_ai_scores"))
	_update_text()

func _process(_delta: float) -> void:
	_update_text()

func _on_ai_decision(name_in: String, intent: String) -> void:
	if name_in != actor_name:
		return
	_last_behavior = intent
	_update_text()

func _on_ai_scores(name_in: String, scores: Dictionary) -> void:
	if name_in != actor_name:
		return
	_scores = scores
	_update_text()

func _update_text() -> void:
	var owner_3d: CharacterBody3D = get_parent() as CharacterBody3D
	var dist: float = -1.0
	var speed: float = 0.0
	if owner_3d:
		var forward: Vector3 = -owner_3d.transform.basis.z
		speed = owner_3d.velocity.dot(forward)
		if _target:
			dist = (owner_3d.global_transform.origin - _target.global_transform.origin).length()
	# Top needs (up to 3)
	var top := []
	for k in _scores.keys():
		top.append([k, float(_scores[k])])
	top.sort_custom(func(a, b): return a[1] > b[1])
	if top.size() > 3:
		top = top.slice(0, 3)
	var needs_str := ""
	for pair in top:
		needs_str += "%s:%.2f " % [String(pair[0]), float(pair[1])]
	text = "[%s]\n📏dist=%.1f  🚀spd=%.1f\n%s" % [_last_behavior, dist, speed, needs_str.strip_edges()] 
