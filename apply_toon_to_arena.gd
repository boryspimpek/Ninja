@tool
extends EditorScript

func _run() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		push_error("Brak otwartej sceny w edytorze.")
		return

	# scene_root TO JEST "Arena" - nie trzeba go szukać, to sam root
	var toon_base: ShaderMaterial = load("res://materials/toon_base.tres")
	var outline_base: ShaderMaterial = load("res://materials/outline_base.tres")

	var count := _apply_recursive(scene_root, toon_base, outline_base)
	print("Zastosowano toon shader na %d meshach." % count)

func _apply_recursive(node: Node, toon_base: ShaderMaterial, outline_base: ShaderMaterial) -> int:
	var count := 0
	if node is MeshInstance3D:
		_apply(node, toon_base, outline_base)
		count += 1
	for child in node.get_children():
		count += _apply_recursive(child, toon_base, outline_base)
	return count

func _apply(mesh_inst: MeshInstance3D, toon_base: ShaderMaterial, outline_base: ShaderMaterial) -> void:
	if not mesh_inst.mesh:
		return
	for i in mesh_inst.mesh.get_surface_count():
		var orig_mat := mesh_inst.mesh.surface_get_material(i)

		var toon_mat := toon_base.duplicate() as ShaderMaterial
		if orig_mat is StandardMaterial3D and orig_mat.albedo_texture:
			toon_mat.set_shader_parameter("albedo_texture", orig_mat.albedo_texture)

		toon_mat.next_pass = outline_base.duplicate()
		mesh_inst.set_surface_override_material(i, toon_mat)
