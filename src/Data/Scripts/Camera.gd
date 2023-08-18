extends Camera

signal single_rightclick() # Rightclick without moving the mouse

# General purpose configurable camera script
# later getting things like "follow player" for camera at stations

export var flyspeed: float = 0.5
export var mouseSensitivity: float = 10
export var cameraFactor: float = 0.1 ## The Factor, how much the camera moves at acceleration and braking

var yaw: float = 0
var pitch: float = 0

onready var cameraY: float = rotation.y - (0.5 * PI)
onready var cameraX: float = -rotation.x

# whether the camera is tied to a point or can move around with wasd
export var fixed: bool = true

# whether to apply or not acceleration effect on camera
export var accel: bool = false

# whether to handle world origin shifts - enable if camera has no parent that handles this!
export var handleWorldOriginShifts: bool = false

# Saves the camera position at the beginning. The Camera Position will be changed, when the train is accelerating, or braking
onready var cameraZeroTransform: Transform = transform

# Reference delta at 60fps
const refDelta: float = 0.0167 # 1.0 / 60

var world: Node
var player: LTSPlayer

var mouseMotion: Vector2 = Vector2(0,0)
var saved_mouse_position: Vector2 = Vector2(0,0)
var mouse_moved: bool = true


func _ready() -> void:
	self.set_process_input(true)
	self.set_process(true)
	Root.connect("world_origin_shifted", self, "_on_world_origin_shifted")


func _on_world_origin_shifted(delta: Vector3):
	if handleWorldOriginShifts:
		translation += delta


func _input(event) -> void:
	if Root.Editor and get_parent().get_node("EditorHUD").mouse_over_ui:
		return

	if current and event is InputEventMouseMotion and (not Root.Editor or Input.is_mouse_button_pressed(BUTTON_RIGHT)) \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouseMotion = mouseMotion + event.relative
		mouse_moved = (event.relative != Vector2(0,0))

	if current and event is InputEventMouseButton and event.button_index == BUTTON_RIGHT and event.pressed == true:
		saved_mouse_position = get_viewport().get_mouse_position()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_moved = false

	if current and event is InputEventMouseButton and event.button_index == BUTTON_RIGHT and event.pressed == false and Root.Editor:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_viewport().warp_mouse(saved_mouse_position)

	if current and event is InputEventMouseButton and event.button_index == BUTTON_RIGHT and event.pressed == false and not mouse_moved:
		emit_signal("single_rightclick")


func _process(delta: float) -> void:
	if get_tree().paused and not (Root.game_pause["ingame_pause"] and Root.game_pause.values().count(true) == 1):
		return
	if not current:
		pass
	if not world:
		world = find_parent("World")
	if not player and world != null:
		player = world.find_node("Player")

	cameraY = rotation.y - (0.5 * PI)
	cameraX = -rotation.x

	if not Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not Root.mobile_version and not Root.Editor and not Root.pause_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if mouseMotion.length() > 0 and (not Root.Editor or Input.is_mouse_button_pressed(BUTTON_RIGHT)):
		var motionFactor: float = (refDelta / delta * refDelta) * mouseSensitivity * deg2rad(1)
		cameraY += -mouseMotion.x * motionFactor
		cameraX += +mouseMotion.y * motionFactor
		cameraX = clamp(cameraX, deg2rad(-85), deg2rad(85))
		rotation.y = cameraY + (0.5 * PI)
		rotation.x = -cameraX
		mouseMotion = Vector2(0,0)

	if accel and player:
		var currentRealAcceleration = player.currentRealAcceleration
		var speed = player.speed
		var sollCameraPosition = cameraZeroTransform.origin.x + (currentRealAcceleration * -cameraFactor)
		if speed == 0:
			sollCameraPosition = cameraZeroTransform.origin.x
		var missingCameraPosition = translation.x - sollCameraPosition
		translation.x -= missingCameraPosition * delta

	if not fixed and (not Root.Editor or Input.is_mouse_button_pressed(BUTTON_RIGHT)):
		# Handle the camera speed toggle
		if(Input.is_action_pressed("shift")):
			flyspeed = 2.0
		else:
			flyspeed = 0.5

		# Account for delta time
		var deltaFlyspeed: float = (delta / refDelta) * flyspeed

		# Only apply movement if CTRL isn't pressed
		# (Workaround for CTRL+A "Autopilot" overlapping with A "move left")
		if not Input.is_key_pressed(KEY_CONTROL):
			# Get current analog input direction
			var direction_2d := Input.get_vector("left", "right", "forward", "backward")
			var direction := Vector3(direction_2d[0], 0.0, direction_2d[1])

			# Apply the movement
			if direction.length() != 0.0:
				self.translate(direction * deltaFlyspeed)
