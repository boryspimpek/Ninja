extends CharacterBody3D
## Isometric twin-stick controller: left stick moves, right stick (or aim_mode
## trigger) aims. Drives the AnimationTree blend tree on the Ninja model.

const MOVE_SPEED := 3.0
const AIM_MOVE_SPEED := 1.0
const ROTATE_SPEED := 12.0
const STICK_DEADZONE := 0.2

const PUNCH_ANIMS: Array[StringName] = [
	&"Punch Quick Right/mixamo_com",
	&"Punch Long Left/mixamo_com",
	&"Punch Long Right/mixamo_com",
	&"Punch Quick Left/mixamo_com",
]

const KICK_ANIMS: Array[StringName] = [
	&"High Kick Left/mixamo_com",
	&"High Kick Right/mixamo_com",
	&"Low Kick Left/mixamo_com",
	&"Low Kick Right/mixamo_com",
	&"Mma Kick Left/mixamo_com",
	&"Mma Kick Right/mixamo_com",
]

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var _playback: AnimationNodeStateMachinePlayback = animation_tree["parameters/StateMachine/playback"]


func _physics_process(delta: float) -> void:
	var is_melee_attacking: bool = (
		animation_tree.get("parameters/PunchShot/active")
		or animation_tree.get("parameters/KickShot/active")
	)
	var is_shooting: bool = animation_tree.get("parameters/Shoot/active")

	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var aim_input := Input.get_vector("aim_stick_left", "aim_stick_right", "aim_stick_forward", "aim_stick_back")
	var is_aiming := Input.is_action_pressed("aim_mode") or aim_input.length() > STICK_DEADZONE

	var move_dir := Vector3(move_input.x, 0.0, move_input.y)

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * delta
	else:
		velocity.y = 0.0

	if is_melee_attacking:
		velocity.x = 0.0
		velocity.z = 0.0
	elif is_aiming:
		_process_aiming(delta, move_dir, aim_input)
	else:
		_process_moving(delta, move_dir)

	move_and_slide()

	if Input.is_action_just_pressed("shoot") and is_aiming and not is_melee_attacking and not is_shooting:
		_fire()

	if not is_melee_attacking:
		_update_animation(is_aiming, move_dir)


func _input(event: InputEvent) -> void:
	var is_melee_attacking: bool = (
		animation_tree.get("parameters/PunchShot/active")
		or animation_tree.get("parameters/KickShot/active")
	)
	var is_shooting: bool = animation_tree.get("parameters/Shoot/active")
	if is_melee_attacking or is_shooting:
		return

	if event.is_action_pressed("punch"):
		_do_attack("PunchAnim", "PunchShot", PUNCH_ANIMS)
	elif event.is_action_pressed("kick"):
		_do_attack("KickAnim", "KickShot", KICK_ANIMS)
		

func _do_attack(anim_node_name: String, shot_name: String, pool: Array[StringName]) -> void:
	var anim_node: AnimationNodeAnimation = animation_tree.tree_root.get_node(anim_node_name)
	anim_node.animation = pool.pick_random()
	animation_tree.set("parameters/" + shot_name + "/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _process_moving(delta: float, move_dir: Vector3) -> void:
	if move_dir.length() > STICK_DEADZONE:
		var target_rot := atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot, ROTATE_SPEED * delta)
	velocity.x = move_dir.x * MOVE_SPEED
	velocity.z = move_dir.z * MOVE_SPEED


func _process_aiming(delta: float, move_dir: Vector3, aim_input: Vector2) -> void:
	# Face the aim stick direction; keep last facing if the stick is centered.
	if aim_input.length() > STICK_DEADZONE:
		var aim_dir := Vector3(aim_input.x, 0.0, aim_input.y)
		var target_rot := atan2(aim_dir.x, -aim_dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot, ROTATE_SPEED * delta)
	velocity.x = move_dir.x * AIM_MOVE_SPEED
	velocity.z = move_dir.z * AIM_MOVE_SPEED


func _fire() -> void:
	if not animation_tree.get("parameters/Shoot/active"):
		animation_tree.set("parameters/Shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _update_animation(is_aiming: bool, move_dir: Vector3) -> void:
	if not is_aiming:
		_playback.travel("Run" if move_dir.length() > STICK_DEADZONE else "Idle")
		return

	# Aiming: pick the strafe animation matching movement relative to the
	# character's own facing. Forward/right are derived empirically from the
	# model (facing = (sin(rotation.y), 0, cos(rotation.y)) on this asset).
	if move_dir.length() <= STICK_DEADZONE:
		_playback.travel("AimIdle")
		return

	var forward_dir := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var right_dir := Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
	var local_z := move_dir.dot(forward_dir)
	var local_x := move_dir.dot(right_dir)
	if abs(local_x) > abs(local_z):
		_playback.travel("AimLeft" if local_x > 0.0 else "AimRight")
	else:
		_playback.travel("AimForward" if local_z > 0.0 else "AimBack")
