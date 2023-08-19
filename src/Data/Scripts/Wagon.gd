extends Spatial

export (float) var length: float = 17.5
export (bool) var cabinMode: bool = false

var baked_route: Array
var complete_route_length: float = 0
var route_index: int = 0
var forward: bool
var currentRail
var distance_on_rail: float = 0
var distance_on_route: float = 0
var speed: float = 0

var door_left := DoorState.new()
var door_right := DoorState.new()

var leftDoors := []
var rightDoors := []

var seats_free := []
var attachedPersons := {} # Person -> occupied seat reference

var passengerPathNodes := []

var distanceToPlayer: float= -1

export var pantographEnabled: bool = false

onready var player: LTSPlayer
var world: Node


func initalize() -> void:
	assert(player != null)
	pause_mode = Node.PAUSE_MODE_PROCESS
	if cabinMode:
		length = 4
		return
	registerDoors()
	registerPassengerPathNodes()
	registerSeats()

	$MeshInstance.show()

	var personsNode := Spatial.new()
	personsNode.name = "Persons"
	add_child(personsNode)
	personsNode.owner = self

	initialize_outside_announcement_player()

	# Move wagon into correct start position
	if distanceToPlayer == -1:
		distanceToPlayer = abs(player.distance_on_rail - distance_on_rail)
	drive(0)
	set_transform_on_rail()

	# TODO: FIXME: Make Wagon child of Player/Train.
	# Player/Train is a WorldObject. RailLogin is a WorldObject.
	# Wagon is Spatial and not directly bound to Train and relies only on set_transform_on_rail() to set transform.
	# set_transform_on_rail() is only called during process()
	#
	# If there is an world shift happening, all world objects might be shifted, but Wagon will not be notified about it.
	# This might result in Wagon being in wrong world position, which affect all the calculations relying or global_transform.
	# This is a temporary fix to make sure that Wagon is always in correct position.
	Root.connect("world_origin_shifted", self, "_on_world_origin_shifted")

	# TODO: this is a performance hotfix, we should do a better implementation in 0.10
	if not ProjectSettings["game/graphics/enable_dynamic_lights"]:
		if get_node_or_null("Lights") != null:
			$Lights.queue_free()
		if get_node_or_null("InteriorLights") != null:
			$InteriorLights.queue_free()


# Temporary fix for Wagon not being notified about world origin shift
func _on_world_origin_shifted(new_origin: Vector3) -> void:
	set_transform_on_rail()


var initialSwitchCheck: bool = false
func _process(delta: float) -> void:
	_debug_passanger_state()

	if get_tree().paused:
		if player != null and not cabinMode:
			visible = player.wagonsVisible
		return

	if (player == null or player.despawning) and not cabinMode:
		queue_free()
		return

	if not initialSwitchCheck:
		updateSwitchOnNextChange()
		initialSwitchCheck = true

	speed = player.speed

	if cabinMode:
		drive(delta)
		return

	assert(get_parent().name == "Players")
	if get_parent().name != "Players":
		return
	if distanceToPlayer == -1:
		distanceToPlayer = abs(player.distance_on_rail - distance_on_rail)
	visible = player.wagonsVisible
	if speed != 0:
		drive(delta)
	set_transform_on_rail()

	if pantographEnabled:
		check_pantograph()

	if not visible:
		return

	if has_node("InsideLight"):
		$InsideLight.visible = player.insideLight


func set_transform_on_rail() -> void:
	if forward:
		self.transform = currentRail.get_transform_at_distance(distance_on_rail)
	else:
		self.transform = currentRail.get_transform_at_distance(distance_on_rail)
		rotate_object_local(Vector3(0,1,0), PI)


func drive(delta: float) -> void:
	if currentRail == player.currentRail:
		## It is IMPORTANT that the `distance > length` and `distance < 0` are SEPARATE!
		if player.forward:
			distance_on_rail = player.distance_on_rail - distanceToPlayer # possibly < 0 !
			distance_on_route = player.distance_on_route - distanceToPlayer
			if distance_on_rail > currentRail.length:
				change_to_next_rail()
		else:
			distance_on_rail = player.distance_on_rail + distanceToPlayer # possibly > currentRail.length !
			distance_on_route = player.distance_on_route + distanceToPlayer
			if distance_on_rail < 0:
				change_to_next_rail()
	else:
		## Real Driving - Only used, if wagon isn't at the same rail as his player.
		var driven_distance: float = speed * delta
		if player.reverser == ReverserState.REVERSE:
			driven_distance = -driven_distance
		distance_on_route += driven_distance

		if not forward:
			driven_distance = -driven_distance
		distance_on_rail += driven_distance

		if distance_on_rail > currentRail.length or distance_on_rail < 0:
			change_to_next_rail()


# TODO: this is almost 100% duplicate code also in Player.gd
#       can we have a single method that both of them use?
func change_to_next_rail() -> void:
	if forward and (player.reverser == ReverserState.FORWARD):
		distance_on_rail -= currentRail.length
	if not forward and (player.reverser == ReverserState.REVERSE):
		distance_on_rail -= currentRail.length

	if player.reverser == ReverserState.REVERSE:
		route_index -= 1
	else:
		route_index += 1

	if baked_route.size() == route_index or route_index == -1:
		if route_index == baked_route.size():
			route_index = 0
			distance_on_route = 0
		else:
			Logger.vlog(name + ": Route no more rail found, despawning me...", self)
			despawn()
			return

	currentRail = baked_route[route_index].rail
	forward = baked_route[route_index].forward

	updateSwitchOnNextChange()

	if not forward and (player.reverser == ReverserState.FORWARD):
		distance_on_rail += currentRail.length
	if forward and (player.reverser == ReverserState.REVERSE):
		distance_on_rail += currentRail.length


var lastPantograph: bool = false
var lastPantographUp: bool = false
func check_pantograph() -> void:
	if not self.has_node("Pantograph"):
		return
	if not lastPantographUp and player.pantographUp:
		Logger.vlog("Started Pantograph Animation")
		$Pantograph/AnimationPlayer.play("Up")
	if lastPantograph and not player.pantograph:
		$Pantograph/AnimationPlayer.play_backwards("Up")
	lastPantograph = player.pantograph
	lastPantographUp = player.pantographUp


func despawn() -> void:
	queue_free()


func registerDoors() -> void:
	for child in $Doors.get_children():
		if child.is_in_group("PassengerDoor"):
			if child.side == DoorSide.UNASSIGNED:
				# If Door side is not set explicitly, fallback to translation
				if child.translation[2] > 0:
					child.side = DoorSide.RIGHT
				else:
					child.side = DoorSide.LEFT
			
			match child.side:
				DoorSide.RIGHT:
					child.translation += Vector3(0,0,0.5)
					rightDoors.append(child)	
				DoorSide.LEFT:
					child.translation -= Vector3(0,0,0.5)
					leftDoors.append(child)
				_:
					assert(true, "Unsupported DoorSide. DoorSide.BOTH is not yet supported")

	# Connect door state to animations
	var _res = $Doors/DoorLeft.connect("animation_finished", door_left, "_on_animation_transition_finished")
	_res = $Doors/DoorRight.connect("animation_finished", door_right, "_on_animation_transition_finished")


func _animate_side_door(animation: AnimationPlayer, sound: AudioStreamPlayer3D, backwards: bool = false) -> bool:
	if not animation.is_playing():
		if backwards:
			animation.play_backwards("open")
		else:
			animation.play("open")
		# TODO: We should be able to blend left and right door opening sound
		if sound and not sound.playing:
			sound.play()
		return true
	assert(false, "Animations should be requested only when appropriate")
	return false


func _open_side_doors(doorState: DoorState, animation: AnimationPlayer) -> void:
	if doorState.is_closed():
		if _animate_side_door(animation, player.get_node("Sound/DoorsOpen")):
			doorState.open()


func _close_side_doors(doorState: DoorState, animation: AnimationPlayer) -> void:
	if doorState.is_opened():
		if _animate_side_door(animation, player.get_node("Sound/DoorsClose"), true):
			doorState.close()


func open_left_doors() -> void:
	_open_side_doors(door_left, $Doors/DoorLeft)


func open_right_doors() -> void:
	_open_side_doors(door_right,  $Doors/DoorRight)


func close_left_doors() -> void:
	_close_side_doors(door_left, $Doors/DoorLeft)


func close_right_doors() -> void:
	_close_side_doors(door_right, $Doors/DoorRight)


func force_close_doors() -> void:
	# There should be better way to handle this, i.e. queue action?
	door_left._set_state(DoorState.State.CLOSED)
	door_right._set_state(DoorState.State.CLOSED)


func is_any_doors_opened() -> bool:
	return door_left.is_opened() or door_right.is_opened()


# returns seat, and routePath to reach seat from the Door
func register_person(person: Spatial, door: Spatial) -> Array:
	var seat: Spatial = get_random_free_seat_index()
	if seat == null:
		# Person will ask for another wagon
		return []

	attachedPersons[person] = seat
	person.get_parent().remove_child(person)
	$Persons.add_child(person)
	person.owner = self
	person.translation = door.translation

	var passengerRoutePath: Array = get_path_from_to(door, seat)
	if passengerRoutePath == []:
		Logger.err("Some seats of "+ name + " are not reachable from every door!!", self)
		return []
	seats_free.erase(seat)

	# Wagon is full, notify train to update routing
	if seats_free.empty():
		player.update_vacant_wagons_doors()
	
	return [seat, passengerRoutePath]


func get_random_free_seat_index() -> Spatial:
	if seats_free.empty():
		return null
	var randIndex = int(rand_range(0, seats_free.size()))
	return seats_free[randIndex]


func get_path_from_to(from: Spatial, to: Spatial) -> Array:
	if from == to:
		return []

	var previous := {}
	var visited := []
	var stack := [from]
	while not stack.empty():
		var node = stack.pop_front()
		visited.append(node)
		if node == to:
			break
		for conn in node.connection_nodes:
			if not visited.has(conn):
				stack.append(conn)
				previous[conn] = node

	var path := [to.translation]
	var node := to
	while previous.has(node):
		node = previous[node]
		path.push_front(node.translation)
	return path


func registerPassengerPathNodes() -> void:
	for child in $PathNodes.get_children():
		if child.is_in_group("PassengerPathNode"):
			passengerPathNodes.append(child)


func registerSeats() -> void:
	for child in $Seats.get_children():
		if child.is_in_group("PassengerSeat"):
			seats_free.append(child)


## Called by the train when arriving to the station
## Randomly picks some attached persons
##
## TODO: At some point we will have to notify persons that train arrived
## and they will decide if they want to leave or not
## i.e. Person will have destination station set when spawned 
## (so Person can switch trains between NPC and Player)
func send_persons_to_station(proportion: float = 0.5) -> void:
	var persons: Array = _get_persons_to_unboard(proportion)
	for person in persons:
		person.arriving_to_station()


func _get_persons_to_unboard(proportion: float = 0.5) -> Array:
	# everyone will leave at the end of the line
	if player.current_station_table_entry.stop_type == StopType.END:
		return attachedPersons.keys()

	var persons := []
	randomize()
	for personNode in attachedPersons.keys():
		if rand_range(0, 1) < proportion:
			persons.append(personNode)
	return persons
	

func get_route_from_seat_to_door(seat: Spatial) -> Array:
	var possible_doors := []
	match player.current_station_node.platform_side:
		PlatformSide.LEFT:
			possible_doors.append_array(leftDoors)
		PlatformSide.RIGHT:
			possible_doors.append_array(rightDoors)
		PlatformSide.BOTH:
			possible_doors.append_array(leftDoors)
			possible_doors.append_array(rightDoors)

	var closest_index := player.get_closest_door_to_position(seat.global_transform.origin, possible_doors)
	var closest_door: Spatial = possible_doors[closest_index]
	var route: Array = get_path_from_to(seat, closest_door)
	if route.empty():
		Logger.err("Some doors are not reachable from every door! Check your Path configuration", self)
		assert(false)
		return []

	# Update position of door. (The Persons should stick inside the train while waiting ;)
	if closest_door.side == DoorSide.LEFT:
		route[route.size()-1].z += 1.3
	else:
		route[route.size()-1].z -= 1.3
	
	return [closest_door, route]


func is_person_registered(person: Spatial) -> bool:
	return attachedPersons.has(person)


func deregister_person(person_node: Spatial) -> void:
	assert(attachedPersons.has(person_node), "Trying to deregister unknown Person")
	seats_free.append(attachedPersons[person_node])
	attachedPersons.erase(person_node)
	
	# Wagon have free seats now, update train doors routes to allow boarding
	if seats_free.size() == 1:
		player.update_vacant_wagons_doors()


var outside_announcement_player: AudioStreamPlayer3D
func initialize_outside_announcement_player() -> void:
	var audioStreamPlayer := AudioStreamPlayer3D.new()

	audioStreamPlayer.unit_size = 10
	audioStreamPlayer.bus = "Game"
	outside_announcement_player = audioStreamPlayer

	add_child(audioStreamPlayer)


func play_outside_announcement(sound_path : String) -> void:
	if sound_path == "":
		return
	if cabinMode:
		return
	var stream: AudioStream = load(sound_path)
	if stream == null:
		return
	stream.loop = false
	if stream != null:
		outside_announcement_player.stream = stream
		outside_announcement_player.play()


var switch_on_next_change: bool = false
func updateSwitchOnNextChange(): ## Exact function also in player.gd. But these are needed: When the player drives over many small rails that could be inaccurate..
	if forward and currentRail.switch_part[1] != "":
		switch_on_next_change = true
		return
	elif not forward and currentRail.switch_part[0] != "":
		switch_on_next_change = true
		return

	if baked_route.size() > route_index+1:
		var nextRail: Spatial = baked_route[route_index+1].rail
		var nextForward: bool = baked_route[route_index+1].forward
		if nextForward and nextRail.switch_part[0] != "":
			switch_on_next_change = true
			return
		elif not nextForward and nextRail.switch_part[1] != "":
			switch_on_next_change = true
			return

	switch_on_next_change = false


func vacant_seats_count() -> int:
	return seats_free.size()


var _debug_passenger_state_label: Label = null
func _debug_passanger_state() -> void:
	if !ProjectSettings["game/debug/draw_labels/wagon"]:
		if _debug_passenger_state_label:
			_debug_passenger_state_label.queue_free()
			_debug_passenger_state_label = null
		return
	var total_seats := seats_free.size() + attachedPersons.size()
	if total_seats == 0:
		return
	if not _debug_passenger_state_label:
		_debug_passenger_state_label = DebugLabel.new(self, 50, Vector3(0, 5, 0))

	if _debug_passenger_state_label.is_visible():
		_debug_passenger_state_label.set_text( "W:%d\nPassenger: %d / %d" % [get_instance_id(), attachedPersons.size(), total_seats])
