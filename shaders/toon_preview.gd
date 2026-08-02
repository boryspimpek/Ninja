@tool
extends Node3D

@export var toon_base_material: ShaderMaterial = preload("res://materials/toon_base.tres"):
	set(v):
		_disconnect_material_signal(toon_base_material)
		toon_base_material = v
		_connect_material_signal(toon_base_material)
		_refresh()

@export var outline_base_material: ShaderMaterial = preload("res://materials/outline_base.tres"):
	set(v):
		_disconnect_material_signal(outline_base_material)
		outline_base_material = v
		_connect_material_signal(outline_base_material)
		_refresh()

@export var apply_now: bool = false:
	set(v):
		if v:
			_refresh()
		apply_now = false

const TARGET_GROUP := "toon_target"

func _ready() -> void:
	_connect_material_signal(toon_base_material)
	_connect_material_signal(outline_base_material)
	_refresh()

func _connect_material_signal(mat: ShaderMaterial) -> void:
	if mat and not mat.changed.is_connected(_refresh):
		mat.changed.connect(_refresh)

func _disconnect_material_signal(mat: ShaderMaterial) -> void:
	if mat and mat.changed.is_connected(_refresh):
		mat.changed.disconnect(_refresh)

func _refresh() -> void:
	if not is_inside_tree():
		return
	_apply_recursive(self)

func _apply_recursive(node: Node) -> void:
	if node is MeshInstance3D and _is_target(node):
		_apply(node)
	for child in node.get_children():
		_apply_recursive(child)

func _is_target(node: Node) -> bool:
	var current := node
	while current:
		if current.is_in_group(TARGET_GROUP):
			return true
		current = current.get_parent()
	return false

func _apply(mesh_inst: MeshInstance3D) -> void:
	if not mesh_inst.mesh:
		return
	for i in mesh_inst.mesh.get_surface_count():
		var orig_mat := mesh_inst.mesh.surface_get_material(i)

		var toon_mat := toon_base_material.duplicate() as ShaderMaterial
		if orig_mat is StandardMaterial3D and orig_mat.albedo_texture:
			toon_mat.set_shader_parameter("albedo_texture", orig_mat.albedo_texture)

		toon_mat.next_pass = outline_base_material.duplicate()
		mesh_inst.set_surface_override_material(i, toon_mat)
