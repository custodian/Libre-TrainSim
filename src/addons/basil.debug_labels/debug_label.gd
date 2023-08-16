# Debug labels to output debug information on top of objects
class_name DebugLabel
extends Label

var _visibility_threshold: float
var _mount_point: Spatial
var _mount_offset: Vector3

func _init(mount_point: Spatial, visibility_threshold: float = 50.0, offset: Vector3 = Vector3(0,0,0)):
	assert(visibility_threshold > 0, "Visibility Threshold should be positive")
	_visibility_threshold = visibility_threshold
	_mount_point = mount_point
	_mount_offset = offset
	mount_point.add_child(self)
	owner = mount_point


func _debug_get_camera():
	return Root.get_viewport().get_camera()
	

func is_visible() -> bool:
	var camera = _debug_get_camera()
	var test_point:Vector3 = _mount_point.global_transform.origin + _mount_offset

	if not camera.is_position_behind(test_point):
		if test_point.distance_to(camera.global_transform.origin) < _visibility_threshold:
			var cam_pos = camera.translation
			var x_offset = Vector2(get_size().x/2, 0)
			rect_position = camera.unproject_position(test_point) - x_offset
			visible = true
		else:
			visible = false
	else:
		visible = false
	return visible


# func _position_debug_label(point3D:Vector3):
#     var camera = _get_camera()
#     var cam_pos = camera.translation
#     var offset = Vector2(_debug_state_label.get_size().x/2, 0)
#     _debug_state_label.rect_position = camera.unproject_position(point3D) - offset

# func _debug_draw_state() -> void:
#     if !ProjectSettings["game/debug/draw_paths"]:
#         return
#     if _debug_state_label == null:
#         _debug_state_label = Label.new()
#         self.add_child(_debug_state_label)
#         _debug_state_label.owner = self

#     var cam = _get_camera()
#     var test_point:Vector3 = global_transform.origin + Vector3(0, 1.5, 0)
#     if not cam.is_position_behind(test_point):
#         if test_point.distance_to(cam.global_transform.origin) < 50.0:
#             _debug_state_label.visible = true
#             _position_debug_label(test_point)
#             _debug_state_label.set_text( "P:%d\n%s\n%s" % [get_instance_id(), Destination.keys()[destination], Action.keys()[action]])
#         else:
#             _debug_state_label.visible = false

	
