class_name Station
extends RailLogic

var personsNode: PersonsNode

export (int) var length: int # Length of platform


export (PlatformSide.TypeHint) var platform_side: int = PlatformSide.NONE
export (bool) var personSystem: bool = true
export (float) var platformHeight: float = 1.2
export (float) var platformStart: float = 2.5
export (float) var platformEnd: float = 4.5

export var assigned_signal: String = ""

var waitingPersonCount: int = 5
var attachedPersons: Array = []


func _get_type() -> String:
	return RailLogicTypes.STATION


func _ready():
	set_to_rail()
	update_operation_mode_of_assigned_signal()

	if not Root.Editor:
		$Mesh.queue_free()
		$SelectCollider.queue_free()
		personSystem = personSystem and ProjectSettings["game/gameplay/enable_persons"] and not Root.mobile_version

	if Root.Editor or not personSystem or not is_instance_valid(rail):
		set_process(false)


func _process(_delta: float) -> void:
	handlePersons()


func spawnPersonsAtBeginning() -> void:
	if not personSystem:
		return
	if platform_side == PlatformSide.NONE:
		return
	while(rail.visible and attachedPersons.size() < waitingPersonCount):
		spawnRandomPerson()


func set_waiting_persons(count: int) -> void:
	waitingPersonCount = count
	spawnPersonsAtBeginning()


func handlePersons() -> void:
	if platform_side == PlatformSide.NONE:
		return
	assert(rail != null)

	if rail.visible and attachedPersons.size() < waitingPersonCount:
		spawnRandomPerson()


func spawnRandomPerson() -> void:
	randomize()
	var person: PackedScene = preload("res://Data/Modules/Person.tscn")
	var personVI: PackedScene = world.personVisualInstances[int(rand_range(0, world.personVisualInstances.size()))]
	var personI: Spatial = person.instance()
	personI.add_child(personVI.instance())
	personI.attachedStation = self
	personI.global_transform = getRandomTransformAtPlatform()
	personsNode.add_child(personI)
	personI.owner = world
	attachedPersons.append(personI)


func getRandomTransformAtPlatform() -> Transform:
	if forward:
		var randRailDistance = int(rand_range(on_rail_position, on_rail_position+length))
		if platform_side == PlatformSide.LEFT:
			return Transform(Basis( \
					Vector3(0, rail.get_rad_at_distance(randRailDistance), 0)), \
					rail.get_shifted_global_pos_at_distance( \
					randRailDistance, rand_range(-platformStart, -platformEnd)) \
					+ Vector3(0, platformHeight, 0))
		if platform_side == PlatformSide.RIGHT:
			return Transform(Basis(Vector3(0, \
					rail.get_rad_at_distance(randRailDistance)+PI, 0)), \
					rail.get_shifted_global_pos_at_distance( \
					randRailDistance, rand_range(platformStart, platformEnd)) \
					+ Vector3(0, platformHeight, 0))
	else:
		var randRailDistance = int(rand_range(on_rail_position, on_rail_position-length))
		if platform_side == PlatformSide.LEFT:
			return Transform(Basis(Vector3(0, \
					rail.get_rad_at_distance(randRailDistance)+PI, 0)), \
					rail.get_shifted_global_pos_at_distance(randRailDistance, \
					rand_range(platformStart, platformEnd)) + Vector3(0, platformHeight, 0))
		if platform_side == PlatformSide.RIGHT:
			return Transform(Basis(Vector3(0, \
					rail.get_rad_at_distance(randRailDistance), 0)), \
					rail.get_shifted_global_pos_at_distance(randRailDistance, \
					rand_range(-platformStart, -platformEnd)) + Vector3(0, platformHeight, 0))
	Logger.warn("Unsupported platform type %s" % platform_side, self)
	#assert(false) # Unsupported platform type. I don't wanna fix here
	return global_transform


func setDoorPositions(doors: Array, doorsWagon: Array) -> void: ## Called by the train
	if doors.size() == 0:
		return
	for person in attachedPersons:
		person.clear_destinations()
		var nearestDoorIndex = 0
		for i in range(doors.size()):
			if doors[i].global_transform.origin.distance_to(person.global_transform.origin) \
					< doors[nearestDoorIndex].global_transform.origin \
					.distance_to(person.global_transform.origin):
				nearestDoorIndex = i
		person.destinationPos.append(doors[nearestDoorIndex].global_transform.origin)
		person.transitionToWagon = true
		person.assignedDoor = doors[nearestDoorIndex]
		person.attachedWagon = doorsWagon[nearestDoorIndex]
		if ProjectSettings["game/debug/draw_paths"]:
			DebugDraw.draw_box(doors[nearestDoorIndex].global_transform.origin, \
					Vector3(2,2,2), person.debug_color)


func deregisterPerson(personToDelete: Spatial) -> void:
	if attachedPersons.has(personToDelete):
		attachedPersons.erase(personToDelete)
		waitingPersonCount -= 1


func registerPerson(personNode: Spatial) -> void:
	attachedPersons.append(personNode)
	personNode.get_parent().remove_child(personNode)
	personsNode.add_child(personNode)
	personNode.owner = world
	personNode.destinationPos.append(getRandomTransformAtPlatform().origin)


func update_operation_mode_of_assigned_signal():
	var signal_node: Node = world.get_signal(assigned_signal)
	if signal_node == null:
		return
	signal_node.operation_mode = SignalOperationMode.STATION


func get_perfect_halt_distance_on_rail(train_length: int):
	if forward:
		return on_rail_position + (length - (length-train_length)/2.0)
	else:
		return on_rail_position - (length - (length-train_length)/2.0)


func set_data(d: StationSettings) -> void:
	if not d.overwrite:
		return
	assigned_signal = d.assigned_signal_name
	personSystem = d.enable_person_system
