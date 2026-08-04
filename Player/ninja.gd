extends CharacterBody3D
## Isometric twin-stick controller: left stick moves, right stick (or aim_mode
## trigger) aims. Drives the AnimationTree blend tree on the Ninja model.

@export var MOVE_SPEED := 3.0
@export var AIM_MOVE_SPEED := 1.0
@export var ROTATE_SPEED := 12.0
@export var STICK_DEADZONE := 0.2
@export var JUMP_VELOCITY := 3.0

@export var COMBO_WINDOW := 0.6  # fallback, gdy nie uda się odczytać długości animacji
@export var PUNCH_FADEOUT := 0.15  # fadeout do Idle po zakończeniu comba

const KICK_ANIMS: Array[StringName] = [
	&"High Kick Left/mixamo_com",
	&"High Kick Right/mixamo_com",
	&"Low Kick Left/mixamo_com",
	&"Low Kick Right/mixamo_com",
	&"Mma Kick Left/mixamo_com",
	&"Mma Kick Right/mixamo_com",
]

const PUNCH_COMBO_ORDER: Array[String] = ["Punch_L", "Punch_R", "Punch_L2", "Punch_Cross"]

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var _playback: AnimationNodeStateMachinePlayback = animation_tree["parameters/StateMachine/playback"]

# Wewnętrzna state machine ciosów - to osobny węzeł BlendTree (nazwa jak w edytorze!),
# NIE podścieżka wewnątrz PunchShot. Podmień "PunchCombo" jeśli nazwałeś węzeł inaczej.
@onready var punch_combo_playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/PunchCombo/playback")
@onready var punch_combo_state_machine: AnimationNodeStateMachine = animation_tree.tree_root.get_node("PunchCombo")
# Sam węzeł OneShot, żeby móc sterować fadeout_time z kodu
@onready var punch_one_shot: AnimationNodeOneShot = animation_tree.tree_root.get_node("PunchShot")

@onready var combo_timer: Timer = $ComboWindowTimer  # one_shot = true

var can_vault: bool = false
var current_vault = null

var combo_index := -1  # -1 = poza combem (nic nie kolejkujemy)
var _pending_target := ""  # cel, który już zakolejkowaliśmy i czeka na start
var _last_combo_state := ""  # ostatni stan, dla którego wystartował combo_timer


func _ready() -> void:
	print("groups: ", get_groups())


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


func _process(_delta: float) -> void:
	# Kluczowa sztuczka: aktualizujemy fadeout_time co klatkę, na podstawie
	# tego czy combo wciąż trwa (combo_index != -1) czy się zakończyło.
	# Dzięki temu w momencie faktycznego zakończenia animacji OneShot
	# używa aktualnej wartości, a nie tej ustawionej na starcie ataku.
	punch_one_shot.fadeout_time = 0.0 if combo_index != -1 else PUNCH_FADEOUT

	if combo_index == -1:
		_last_combo_state = ""
		_pending_target = ""
		return

	# Timer na okno combo NIE startuje w momencie kliknięcia, tylko w
	# momencie gdy state machine faktycznie zacznie grać dany stan
	# (przy Switch Mode "At End" to może nastąpić z opóźnieniem względem
	# kliknięcia - klik tylko KOLEJKUJE przejście). Dzięki temu okno zawsze
	# odpowiada realnemu czasowi trwania animacji, która się właśnie gra.
	var current_playing := String(punch_combo_playback.get_current_node())
	if current_playing != _last_combo_state and current_playing in PUNCH_COMBO_ORDER:
		_last_combo_state = current_playing
		combo_timer.start(_get_combo_window(current_playing))

	if current_playing == _pending_target:
		# Zakolejkowany cios właśnie faktycznie ruszył - zwalniamy bufor,
		# żeby kolejny klik gracza mógł zakolejkować następny cios.
		_pending_target = ""


func _input(event: InputEvent) -> void:
	var is_shooting: bool = animation_tree.get("parameters/Shoot/active")

	if is_shooting:
		return

	if event.is_action_pressed("punch") and not event.is_echo():
		_on_attack_input()
		return

	var is_melee_attacking: bool = (
		animation_tree.get("parameters/PunchShot/active")
		or animation_tree.get("parameters/KickShot/active")
	)

	if is_melee_attacking:
		return

	if event.is_action_pressed("kick"):
		_do_attack("KickAnim", "KickShot", KICK_ANIMS)


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
	anim_node.animation = pool.pick_random()
	animation_tree.set("parameters/" + shot_name + "/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _on_attack_input() -> void:
	combo_timer.stop()

	if combo_index == -1:
		# Pierwszy cios w serii - odpalamy zewnętrzny OneShot.
		combo_index = 0
		_pending_target = PUNCH_COMBO_ORDER[combo_index]
		punch_combo_playback.travel(_pending_target)
		animation_tree.set("parameters/PunchShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		return

	if _pending_target != "":
		# Mamy już jeden zakolejkowany cios, który jeszcze się nie zaczął
		# odtwarzać - bufor pełny, dodatkowe kliknięcia ignorujemy (zamiast
		# pozwolić graczowi "namashować" długą, niekontrolowaną serię ciosów).
		return

	combo_index = (combo_index + 1) % PUNCH_COMBO_ORDER.size()
	_pending_target = PUNCH_COMBO_ORDER[combo_index]
	punch_combo_playback.travel(_pending_target)


func _get_combo_window(state_name: String) -> float:
	# Okno na kolejny klik = długość animacji aktualnego ciosu (+ mały zapas),
	# zamiast jednej sztywnej wartości dla wszystkich ciosów. Dzięki temu przy
	# długich hakach gracz ma tyle czasu ile trwa animacja, a nie tylko 0.6s.
	var anim_node := punch_combo_state_machine.get_node(state_name) as AnimationNodeAnimation
	if anim_node == null:
		return COMBO_WINDOW
	var anim := animation_player.get_animation(anim_node.animation)
	if anim == null:
		return COMBO_WINDOW
	var window := anim.length + 0.1
	print(state_name, " -> okno na klik: ", window, "s")
	return window


func _on_combo_window_timer_timeout() -> void:
	combo_index = -1
	# PunchCombo (state machine) nie ma jednoznacznego "końca" jak zwykła
	# animacja - zatrzymuje się na ostatnim stanie i czeka. Musimy więc
	# jawnie kazać zewnętrznemu OneShotowi się zakończyć, inaczej "active"
	# zostanie true na zawsze i postać nigdy nie wróci do ruchu/skoku.
	punch_one_shot.fadeout_time = PUNCH_FADEOUT
	animation_tree.set("parameters/PunchShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


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
