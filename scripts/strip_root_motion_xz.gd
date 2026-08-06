@tool
extends EditorScenePostImport

# Nazwa kości niosącej translację (root/Hips). Dopasuj jeśli u Ciebie
# nazywa się inaczej — sprawdź w Skeleton3D dokładną nazwę kości.
const ROOT_BONE_NAME := "mixamorig_Hips"

# Ustaw na false, żeby wyłączyć gadatliwe logi po zdiagnozowaniu problemu.
const DEBUG := true


func _post_import(scene: Node) -> Object:
	print("========== strip_root_motion_xz: START _post_import ==========")

	var anim_player := _find_animation_player(scene)
	if anim_player == null:
		push_warning("strip_root_motion_xz: nie znaleziono AnimationPlayer w scenie.")
		return scene

	print("strip_root_motion_xz: znaleziono AnimationPlayer: ", anim_player.get_path())

	var lib_list := anim_player.get_animation_library_list()
	print("strip_root_motion_xz: liczba bibliotek animacji: ", lib_list.size(), " -> ", lib_list)

	if lib_list.is_empty():
		push_warning("strip_root_motion_xz: AnimationPlayer nie ma żadnych bibliotek animacji.")

	for lib_name in lib_list:
		var lib := anim_player.get_animation_library(lib_name)
		var anim_list := lib.get_animation_list()
		print("strip_root_motion_xz: biblioteka '%s' zawiera %d animacji: %s" % [lib_name, anim_list.size(), anim_list])

		for anim_name in anim_list:
			var anim := lib.get_animation(anim_name)
			print("strip_root_motion_xz: --- przetwarzam animację '%s' (resource_path='%s', tracks=%d) ---" % [anim_name, anim.resource_path, anim.get_track_count()])
			_zero_track_xz(anim, anim_name)

			# Jeśli animacja jest zapisywana jako osobny plik .tres (opcja
			# "Save to File" w imporcie), trzeba to jawnie zapisać —
			# post_import nie robi tego samo, bo zapis do .tres dzieje się
			# ZANIM ten skrypt się wykona.
			var anim_path: String = anim.resource_path
			if anim_path != "" and anim_path.ends_with(".tres"):
				var err := ResourceSaver.save(anim, anim_path)
				if err != OK:
					push_warning("strip_root_motion_xz: nie udało się zapisać '%s' (err %d)" % [anim_path, err])
				else:
					print("strip_root_motion_xz: zapisano zmiany do '%s'" % anim_path)
			else:
				print("strip_root_motion_xz: animacja '%s' nie ma zewnętrznej resource_path (embedded) — pomijam ResourceSaver.save" % anim_name)

	print("========== strip_root_motion_xz: KONIEC _post_import ==========")
	return scene


func _zero_track_xz(anim: Animation, anim_name: String) -> void:
	var matched_any := false

	for track_idx in anim.get_track_count():
		var track_type := anim.track_get_type(track_idx)
		var path := str(anim.track_get_path(track_idx))

		if DEBUG:
			print("strip_root_motion_xz:   tor #%d | typ=%s | ścieżka='%s'" % [track_idx, track_type, path])

		if track_type != Animation.TYPE_POSITION_3D:
			if DEBUG:
				print("strip_root_motion_xz:     -> pomijam, to nie jest TYPE_POSITION_3D")
			continue

		if not path.ends_with(ROOT_BONE_NAME):
			if DEBUG:
				print("strip_root_motion_xz:     -> pomijam, ścieżka nie kończy się na '%s'" % ROOT_BONE_NAME)
			continue

		matched_any = true

		var key_count := anim.track_get_key_count(track_idx)
		print("strip_root_motion_xz:     -> DOPASOWANO tor root bone, key_count=%d" % key_count)

		if key_count == 0:
			push_warning("strip_root_motion_xz: tor '%s' w '%s' ma 0 kluczy — pomijam" % [path, anim_name])
			continue

		# Wartość pierwszej klatki jako punkt odniesienia — mesh nie "przeskoczy"
		var base: Vector3 = anim.track_get_key_value(track_idx, 0)
		if DEBUG:
			print("strip_root_motion_xz:     base (klatka 0) = ", base)

		for key_idx in key_count:
			var val: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			val.x = base.x
			val.z = base.z
			# val.y zostaje bez zmian (np. naturalne podbicie biodra przy skoku)
			anim.track_set_key_value(track_idx, key_idx, val)

		print("strip_root_motion_xz: wyzerowano XZ na torze '%s' w animacji '%s'" % [path, anim_name])

	if not matched_any:
		push_warning("strip_root_motion_xz: w animacji '%s' NIE znaleziono toru pasującego do ROOT_BONE_NAME='%s' (sprawdź listę torów powyżej i nazwę kości w Skeleton3D)" % [anim_name, ROOT_BONE_NAME])


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null