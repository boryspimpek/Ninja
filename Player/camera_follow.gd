extends Camera3D
## Follows the target (player) on the horizontal plane while keeping the
## camera's original height/offset and angle, with light smoothing.

@export var target_path: NodePath = "../Player"
@export var follow_speed: float = 6.0

var _offset: Vector3
var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path)
	if _target:
		_offset = global_position - _target.global_position


func _process(delta: float) -> void:
	if not _target:
		return
	var desired_position: Vector3 = _target.global_position + _offset
	global_position = global_position.lerp(desired_position, 1.0 - exp(-follow_speed * delta))
