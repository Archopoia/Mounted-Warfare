extends Node
class_name Services

var _logger: Node = null
var _event_bus: EventBus = null
var _config: GameConfig = null

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	_event_bus = get_node_or_null("/root/EventBus")
	_config = get_node_or_null("/root/GameConfig")

func logger() -> Node:
	if _logger == null:
		_logger = get_node_or_null("/root/LoggerInstance")
	return _logger

func bus() -> EventBus:
	if _event_bus == null:
		_event_bus = get_node_or_null("/root/EventBus")
	return _event_bus

func config() -> GameConfig:
	if _config == null:
		_config = get_node_or_null("/root/GameConfig")
	return _config


