@tool
extends EditorScenePostImport

# Nazwa kości niosącej translację (root/Hips). Dopasuj jeśli u Ciebie
# nazywa się inaczej — sprawdź w Skeleton3D dokładną nazwę kości.
const ROOT_BONE_NAME := "mixamorig_Hips"


func _post_import(scene: Node) -> Object:
	var anim_player := _find_animation_player(scene)
	if anim_player == null:
		push_warning("strip_root_motion_xz: nie znaleziono AnimationPlayer w scenie.")
		return scene

	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			var anim := lib.get_animation(anim_name)
			_zero_track_xz(anim, anim_name)

	return scene


func _zero_track_xz(anim: Animation, anim_name: String) -> void:
	for track_idx in anim.get_track_count():
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue

		var path := str(anim.track_get_path(track_idx))
		if not path.ends_with(ROOT_BONE_NAME):
			continue

		var key_count := anim.track_get_key_count(track_idx)
		if key_count == 0:
			continue

		# Wartość pierwszej klatki jako punkt odniesienia — mesh nie "przeskoczy"
		var base: Vector3 = anim.track_get_key_value(track_idx, 0)

		for key_idx in key_count:
			var val: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			val.x = base.x
			val.z = base.z
			# val.y zostaje bez zmian (np. naturalne podbicie biodra przy skoku)
			anim.track_set_key_value(track_idx, key_idx, val)

		print("strip_root_motion_xz: wyzerowano XZ na torze '%s' w animacji '%s'" % [path, anim_name])


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null