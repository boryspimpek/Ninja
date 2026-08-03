@tool
extends Node3D
class_name VFXControllerBB

var materials : Array[ShaderMaterial]:
	get():
		if !materials.is_empty():
			return materials
		
		var result : Array[ShaderMaterial]
		for c in get_children():
			if c is GPUParticles3D || c is MeshInstance3D:
				if c.material_override:
					result.append(c.material_override)
		if !Engine.is_editor_hint():
			materials = result
		return result

var particles : Array[GPUParticles3D]:
	get():
		if !particles.is_empty():
			return particles
		
		var result : Array[GPUParticles3D]
		for c in get_children():
			if c is GPUParticles3D:
				result.append(c)
		if !Engine.is_editor_hint():
			particles = result
		return result

var anim : AnimationPlayer:
	get():
		if get_node("AnimationPlayer"):
			if !Engine.is_editor_hint() && anim:
				return anim
			return $AnimationPlayer
		else:
			return null

@export var one_shot : bool = false
@export var autoplay : bool = false

@export_range(0.0, 8.0, 0.01) var speed_scale : float = 1.0:
	set(v):
		speed_scale = v
		for p in particles:
			p.speed_scale = speed_scale
		anim.speed_scale = speed_scale

@export var emitting : bool:
	set(v):
		play();

@export_tool_button("Play", "Play") var play_button = func(): 
	play()
@export_tool_button("Stop", "Stop") var stop_button = func(): 
	stop()

signal finished
signal stopped

var _vfx_playing: bool = false
var _instance_materials_ready: bool = false

func _ready() -> void:
	_ensure_instance_materials()
	if autoplay:
		play()

func _process(_delta: float) -> void:
	if _vfx_playing:
		_apply_smoke_decay_tracks()

func play() -> void:
	if anim == null:
		return

	_ensure_instance_materials()
	_vfx_playing = true
	anim.play("main")
	anim.seek(0.0, true)
	_prepare_smoke_effects()
	_apply_smoke_decay_tracks()

	await anim.animation_finished
	_vfx_playing = false
	finished.emit()

	if !one_shot:
		anim.advance(0.0)
		play()

func _ensure_instance_materials() -> void:
	if _instance_materials_ready or Engine.is_editor_hint():
		return
	_duplicate_instance_materials(self)
	_instance_materials_ready = true


func _duplicate_instance_materials(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			if mesh.material_override:
				mesh.material_override = mesh.material_override.duplicate()
		elif child is GPUParticles3D:
			var gpu_particles := child as GPUParticles3D
			if gpu_particles.material_override:
				gpu_particles.material_override = gpu_particles.material_override.duplicate()
		_duplicate_instance_materials(child)


func _is_smoke_material(mat: ShaderMaterial) -> bool:
	if mat == null or mat.shader == null:
		return false
	var path := mat.shader.resource_path
	return path.ends_with("explosion_smoke.gdshader")

func _prepare_smoke_effects() -> void:
	for node in get_children():
		if node is GPUParticles3D:
			var mat := (node as GPUParticles3D).material_override as ShaderMaterial
			if _is_smoke_material(mat):
				(node as GPUParticles3D).restart()
				(node as GPUParticles3D).emitting = true

func _apply_smoke_decay_tracks() -> void:
	if anim == null or anim.current_animation.is_empty():
		return

	var animation := anim.get_animation(anim.current_animation)
	if animation == null:
		return

	var time := anim.current_animation_position
	for track_idx in animation.get_track_count():
		var path := animation.track_get_path(track_idx)
		var path_str := str(path)
		if not path_str.contains("shader_parameter/effect_decay"):
			continue

		var node_path := NodePath(path_str.get_slice(":", 0))
		var node := get_node_or_null(node_path)
		if node == null:
			continue

		var value := _sample_track_value(animation, track_idx, time)
		var mat: ShaderMaterial = null
		if node is MeshInstance3D:
			mat = (node as MeshInstance3D).material_override as ShaderMaterial
		elif node is GPUParticles3D:
			mat = (node as GPUParticles3D).material_override as ShaderMaterial

		if _is_smoke_material(mat):
			mat.set_shader_parameter("effect_decay", value)

func _sample_track_value(animation: Animation, track_idx: int, time: float) -> float:
	var key_count := animation.track_get_key_count(track_idx)
	if key_count == 0:
		return 0.0

	var times := PackedFloat32Array()
	var values := PackedFloat32Array()
	for key_idx in key_count:
		times.append(animation.track_get_key_time(track_idx, key_idx))
		values.append(animation.track_get_key_value(track_idx, key_idx))

	if time <= times[0]:
		return values[0]
	if time >= times[key_count - 1]:
		return values[key_count - 1]

	for key_idx in key_count - 1:
		var t0 := times[key_idx]
		var t1 := times[key_idx + 1]
		if time >= t0 and time <= t1:
			var blend := (time - t0) / maxf(t1 - t0, 0.00001)
			return lerpf(values[key_idx], values[key_idx + 1], blend)

	return values[key_count - 1]

func stop() -> void:
	anim.play("stop")
	anim.stop()
	stopped.emit()

func _restart_particles() -> void:
	print("AA")
	for p in particles:
		p.restart()

func _set_shader_param(key : String, value : Variant) -> void:
	var mats : Array[ShaderMaterial] = materials
	for m in mats:
		m.set_shader_parameter(key, value)
