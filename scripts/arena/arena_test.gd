extends Node3D
class_name ArenaTestController

@onready var _logger = get_node("/root/LoggerInstance")
@export var player_scene: PackedScene = preload("res://scenes/mounts/player_mastodont.tscn")
@export var bot_scene: PackedScene = preload("res://scenes/mounts/mastodont.tscn")

func _ready() -> void:
	_logger.info("scene", name, "🚩 arena ready: %s" % scene_file_path)
	# log key children
	for n in get_children():
		_logger.info("scene", name, "📍 child: %s (%s)" % [n.name, n.get_class()])
	# ensure actors exist
	_ensure_actors()
	# log actors
	var player := get_tree().get_first_node_in_group("players")
	if player:
		_logger.info("scene", name, "🎯 player at %s" % str((player as Node3D).global_transform.origin))
	else:
		_logger.error("scene", name, "❌ still no player in group 'players'")
	var bots := get_tree().get_nodes_in_group("bots")
	if bots.size() == 0:
		_logger.error("scene", name, "❌ still no bots in group 'bots'")
	for b in bots:
		if b is Node3D:
			_logger.info("scene", name, "🤖 bot %s at %s" % [b.name, str(b.global_transform.origin)])

func _ensure_actors() -> void:
	var player := get_tree().get_first_node_in_group("players")
	var sp: Marker3D = $SpawnPoints.get_node_or_null("PlayerSpawn") as Marker3D
	if player == null and player_scene != null:
		var p := player_scene.instantiate()
		p.name = "Player"
		# position at PlayerSpawn if present
		if sp:
			(p as Node3D).global_transform = sp.global_transform
		add_child(p)
		_logger.info("scene", name, "🧍 spawned Player at %s" % str((p as Node3D).global_transform.origin))
	# bots: ensure two
	var bot_markers := []
	var sp1 := $SpawnPoints.get_node_or_null("BotSpawn1")
	if sp1 and sp1 is Marker3D:
		bot_markers.append(sp1)
	# fallback: use PlayerSpawn if not enough markers
	if bot_markers.size() == 0 and sp:
		bot_markers.append(sp)
	for i in range(2):
		if get_tree().get_nodes_in_group("bots").size() > i:
			continue
		if bot_scene == null:
			_logger.error("scene", name, "❌ bot_scene not configured; cannot spawn bot %d" % i)
			break
		var b := bot_scene.instantiate()
		b.name = "Bot1" if i == 0 else "Bot"
		(b as Node).add_to_group("bots")
		(b as Node).set("is_player", false)
		# attach BotDriver and TeamColor
		var bd := Node.new()
		bd.name = "BotDriver"
		bd.set_script(load("res://scripts/ai/bot_driver.gd"))
		b.add_child(bd)
		var tc := Node.new()
		tc.name = "TeamColor"
		tc.set_script(load("res://scripts/appearance/team_color.gd"))
		b.add_child(tc)
		tc.set("color", Color(1,0.1,0.1,1) if i == 0 else Color(0.1,0.3,1,1))
		# position
		if i < bot_markers.size():
			(b as Node3D).global_transform = (bot_markers[i] as Marker3D).global_transform
		else:
			(b as Node3D).global_transform.origin = Vector3(0,0,10 + i * 3)
		add_child(b)
		_logger.info("scene", name, "🤖 spawned %s at %s" % [b.name, str((b as Node3D).global_transform.origin)])
