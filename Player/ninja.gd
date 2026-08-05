extends CharacterBody3D
## Isometric twin-stick controller: left stick moves, right stick (or aim_mode
## trigger) aims. Drives the AnimationTree blend tree on the Ninja model.

@export var MOVE_SPEED := 3.0
@export var AIM_MOVE_SPEED := 1.0
@export var ROTATE_SPEED := 12.0
@export var STICK_DEADZONE := 0.2
@export var JUMP_VELOCITY := 3.0

const KICK_ANIMS: Array[StringName] = [
	# &"Attacks/mma_kick",
	# &"Attacks/mma_kick_2",
	# &"Attacks/mma_kick_3",
	&"Attacks/mma_kick_4",
]

const HIT_ANIMS: Array[StringName] = [
	&"Punch Left/mixamo_com",
	# &"Punch Right/mixamo_com",
	# &"Punch Cross/mixamo_com",
]

const AttackSpeedData = preload("res://Player/AttackSpeedData.gd")

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var _playback: AnimationNodeStateMachinePlayback = animation_tree["parameters/StateMachine/playback"]

var can_vault: bool = false
var current_vault = null

@export var kick_speed_settings: Array[AttackSpeedData] = []
@export var hit_speed_settings: Array[AttackSpeedData] = []
@export var default_attack_duration: float = 0.7

var attack_timer: float = 0.0
var attack_active: bool = false
var attack_speed_curve: Curve = Curve.new()
var attack_duration: float = default_attack_duration
var default_attack_curve: Curve = Curve.new()

func _ready() -> void:
	default_attack_curve.add_point(Vector2(0.0, 1.0))
	default_attack_curve.add_point(Vector2(1.0, 1.0))
	attack_speed_curve = default_attack_curve
	print("groups: ", get_groups())


func _physics_process(delta: float) -> void:
	var is_melee_attacking: bool = (
		animation_tree.get("parameters/KickShot/active")
		or animation_tree.get("parameters/HitShot/active")
	)
	var is_shooting: bool = animation_tree.get("parameters/Shoot/active")

	var move_input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var aim_input: Vector2 = Input.get_vector("aim_stick_left", "aim_stick_right", "aim_stick_forward", "aim_stick_back")
	var is_aiming: bool = Input.is_action_pressed("aim_mode") or aim_input.length() > STICK_DEADZONE

	var move_dir: Vector3 = Vector3(move_input.x, 0.0, move_input.y)

	if attack_active:
		attack_timer += delta
		var t: float = clamp(attack_timer / attack_duration, 0.0, 1.0)
		var speed: float = attack_speed_curve.sample(t)
		animation_tree.set("parameters/KickScale/scale", speed)

		if t >= 1.0:
			attack_active = false
			animation_tree.set("parameters/KickScale/scale", 1.0)

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * delta
	else:
		velocity.y = 0.0
		if Input.is_action_just_pressed("jump") and not is_melee_attacking:
			if can_vault:
				velocity.y = JUMP_VELOCITY
				_do_vault()
			else:
				velocity.y = JUMP_VELOCITY
				_do_jump()

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
	var is_shooting: bool = animation_tree.get("parameters/Shoot/active")

	if is_shooting:
		return

	var is_melee_attacking: bool = (
		animation_tree.get("parameters/KickShot/active")
		or animation_tree.get("parameters/HitShot/active")
	)

	if is_melee_attacking:
		return

	if event.is_action_pressed("kick"):
		_do_attack("KickAnim", "KickShot", KICK_ANIMS)

	if event.is_action_pressed("hit"):
		_do_attack("HitAnim", "HitShot", HIT_ANIMS)


func _do_jump() -> void:
	animation_tree.set("parameters/JumpShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	print("JUMP WYKONANY")


func _do_vault() -> void:
	set_collision_mask_value(5, false)
	animation_tree.set("parameters/VaultShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	print("VAULT WYKONANY")
	await get_tree().create_timer(1.0).timeout

	set_collision_mask_value(5, true)
	print("MASKA 5 PRZYWRÓCONA")


func _do_attack(anim_node_name: String, shot_name: String, pool: Array[StringName]) -> void:
	var anim_node: AnimationNodeAnimation = animation_tree.tree_root.get_node(anim_node_name)
	var chosen_anim: StringName = pool.pick_random()
	anim_node.animation = chosen_anim
	_set_attack_curve(shot_name, chosen_anim)
	attack_timer = 0.0
	attack_active = true
	animation_tree.set("parameters/KickScale/scale", attack_speed_curve.sample(0.0))
	animation_tree.set("parameters/" + shot_name + "/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _set_attack_curve(shot_name: String, animation_name: StringName) -> void:
	var key: String = String(animation_name)
	attack_speed_curve = default_attack_curve
	attack_duration = default_attack_duration

	var settings: Array[AttackSpeedData]
	if shot_name == "KickShot":
		settings = kick_speed_settings
	else:
		settings = hit_speed_settings
	for setting in settings:
		if setting.animation_name == key:
			attack_speed_curve = setting.speed_curve
			if setting.duration > 0.0:
				attack_duration = setting.duration
			return


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


func _on_area_3d_body_entered(body: Node3D) -> void:
	print("Area entered: ", body.name)
	if body.is_in_group("player"):
		body.can_vault = true
		print("VAULT ON: ", body.can_vault)
		body.current_vault = self


func _on_area_3d_body_exited(body: Node3D) -> void:
	print("Area exited: ", body.name)
	if body.is_in_group("player"):
		body.can_vault = false
		print("VAULT OFF: ", body.can_vault)
		body.current_vault = null
