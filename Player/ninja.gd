extends CharacterBody3D
## Isometric twin-stick controller: left stick moves, right stick (or aim_mode
## trigger) aims. Drives the AnimationTree blend tree on the Ninja model.
##
## Combo attacks (kick / hit / sword) są teraz sekwencjami zdefiniowanymi
## w AnimationTree jako zagnieżdżone State Machine (KickCombo / HitCombo /
## SwordCombo). Kolejność animacji ustala się w EDYTORZE (kolejność
## przejść między stanami), a skrypt tylko:
##   1) odpala outer OneShot (KickShot/HitShot/SwordShot),
##   2) w oknie bufora ustawia warunek "<x>_advance" na true, żeby
##      state machine poszedł do następnego ciosu zamiast wrócić do End.
##
## Wymagane w każdym zagnieżdżonym state machine (np. KickCombo):
##   Start -> Kick1
##   KickN -> Kick(N+1)  [Switch Mode: At End, Advance Condition: kick_advance]  (wyżej w priorytecie)
##   KickN -> End        [Switch Mode: At End, brak warunku]                      (fallback)

@export var MOVE_SPEED := 3.0
@export var AIM_MOVE_SPEED := 1.0
@export var ROTATE_SPEED := 12.0
@export var STICK_DEADZONE := 0.2
@export var JUMP_VELOCITY := 3.0
@export var COMBO_BUFFER_TIME := 0.3

## Definicja kategorii ataków: nazwa akcji inputu -> ścieżki parametrów w AnimationTree.
## To jedyne miejsce, które trzeba rozszerzyć, jeśli dojdzie nowy typ ataku.
## Nie ma tu żadnych nazw konkretnych animacji - te żyją wyłącznie w edytorze.
const COMBOS := {
	"kick": {"shot": "KickShot", "state_machine": "KickCombo", "advance_param": "kick_advance"},
	"hit": {"shot": "HitShot", "state_machine": "HitCombo", "advance_param": "hit_advance"},
	"sword": {"shot": "SwordShot", "state_machine": "SwordCombo", "advance_param": "sword_advance"},
}

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var _playback: AnimationNodeStateMachinePlayback = animation_tree["parameters/StateMachine/playback"]

var can_vault: bool = false
var current_vault = null

# Śledzi ostatni znany stan każdego combo state machine, żeby wykryć moment
# faktycznego przejścia (KickN -> Kick(N+1)) i skasować warunek "advance"
# zaraz po tym, jak zostanie skonsumowany - inaczej combo poleciałoby dalej
# samo, bez kolejnego wciśnięcia przycisku.
var _last_combo_state: Dictionary = {}


func _ready() -> void:
	print("groups: ", get_groups())


func _physics_process(delta: float) -> void:
	var active_combo := _get_active_combo()
	var is_melee_attacking: bool = active_combo != ""

	if is_melee_attacking:
		_consume_advance_condition_if_transitioned(active_combo)

	var is_shooting: bool = animation_tree.get("parameters/Shoot/active")

	var move_input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var aim_input: Vector2 = Input.get_vector("aim_stick_left", "aim_stick_right", "aim_stick_forward", "aim_stick_back")
	var is_aiming: bool = Input.is_action_pressed("aim_mode") or aim_input.length() > STICK_DEADZONE

	var move_dir: Vector3 = Vector3(move_input.x, 0.0, move_input.y)

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

	var active_combo := _get_active_combo()

	if active_combo != "":
		print("[COMBO DEBUG] aktywne combo: ", active_combo, " | current_node: ", _get_combo_playback(active_combo).get_current_node(), " | time_left: ", _time_left_in_current_hit(active_combo))
		# W trakcie combo: jeśli jesteśmy w oknie bufora i gracz wcisnął TĘ SAMĄ
		# kategorię ataku ponownie, poproś state machine o przejście dalej.
		if event.is_action_pressed(active_combo):
			var time_left := _time_left_in_current_hit(active_combo)
			if time_left <= COMBO_BUFFER_TIME:
				var path := _advance_condition_path(active_combo)
				animation_tree.set(path, true)
				print("[COMBO DEBUG] USTAWIAM ", path, " = true | odczyt zaraz po ustawieniu: ", animation_tree.get(path))
			else:
				print("[COMBO DEBUG] wciśnięto za wcześnie, poza oknem bufora (", time_left, " > ", COMBO_BUFFER_TIME, ")")
		return

	for category in COMBOS.keys():
		if event.is_action_pressed(category):
			_do_attack(category)
			break


func _do_attack(category: String) -> void:
	print("[COMBO DEBUG] _do_attack (świeży start) kategoria: ", category)
	var combo: Dictionary = COMBOS[category]
	# Świeży start combo - upewnij się, że warunek advance jest czysty,
	# a state machine wystartuje od Start -> pierwszy stan.
	animation_tree.set(_advance_condition_path(category), false)
	_last_combo_state.erase(category)
	animation_tree.set("parameters/%s/request" % combo["shot"], AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _get_active_combo() -> String:
	for category in COMBOS.keys():
		if animation_tree.get("parameters/%s/active" % COMBOS[category]["shot"]):
			return category
	return ""


func _get_combo_playback(category: String) -> AnimationNodeStateMachinePlayback:
	var state_machine: String = COMBOS[category]["state_machine"]
	return animation_tree.get("parameters/%s/playback" % state_machine)


func _time_left_in_current_hit(category: String) -> float:
	var pb := _get_combo_playback(category)
	if pb == null:
		return 0.0
	return pb.get_current_length() - pb.get_current_play_position()


func _consume_advance_condition_if_transitioned(category: String) -> void:
	var pb := _get_combo_playback(category)
	if pb == null:
		return
	var current_state: String = pb.get_current_node()
	if _last_combo_state.get(category, "") != current_state:
		print("[COMBO DEBUG] przejście stanu w ", category, ": '", _last_combo_state.get(category, ""), "' -> '", current_state, "' (kasuję warunek)")
		# State machine właśnie przeszedł do nowego ciosu (albo dopiero
		# wystartował) - skasuj warunek, żeby nie polecieć od razu dalej
		# bez kolejnego wciśnięcia przycisku.
		animation_tree.set(_advance_condition_path(category), false)
		_last_combo_state[category] = current_state


func _advance_condition_path(category: String) -> String:
	# Warunki przejść wewnątrz ZAGNIEŻDŻONEGO state machine (np. KickCombo,
	# który jest node'em w głównym drzewie, a nie jego rootem) mają prefiks
	# z nazwą tego state machine: "parameters/<StateMachineName>/conditions/<x>".
	# Sama ścieżka "parameters/conditions/<x>" działa tylko wtedy, gdy dany
	# state machine JEST rootem całego AnimationTree.
	var combo: Dictionary = COMBOS[category]
	return "parameters/%s/conditions/%s" % [combo["state_machine"], combo["advance_param"]]


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


func _process_moving(delta: float, move_dir: Vector3) -> void:
	if move_dir.length() > STICK_DEADZONE:
		var target_rot := atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot, ROTATE_SPEED * delta)
	velocity.x = move_dir.x * MOVE_SPEED
	velocity.z = move_dir.z * MOVE_SPEED


func _process_aiming(delta: float, move_dir: Vector3, aim_input: Vector2) -> void:
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
