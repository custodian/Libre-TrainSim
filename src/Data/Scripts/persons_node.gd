class_name PersonsNode
extends Spatial

func _init(_owner: Node) -> void:
	name = "Persons"
	owner = _owner
	pause_mode = Node.PAUSE_MODE_STOP
