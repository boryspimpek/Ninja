@tool
extends EditorScript

func _run() -> void:
	var models_dir = "res://Kenney/MiniForest"
	var output_dir = "res://MiniForestScenes"
	
	# Tworzenie folderu wyjściowego jeśli nie istnieje
	DirAccess.make_dir_absolute(output_dir)
	
	print("Rozpoczynam generowanie dziedziczonych scen z folderu: ", models_dir)
	
	var dir = DirAccess.open(models_dir)
	if not dir:
		push_error("Nie można otworzyć folderu: " + models_dir)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var created_count = 0
	
	while file_name != "":
		if file_name.ends_with(".fbx"):
			var base_name = file_name.get_basename()
			var fbx_path = models_dir.path_join(file_name)
			var output_path = output_dir.path_join(base_name + ".tscn")
			
			print("Przetwarzam: ", file_name, " -> ", output_path)
			
			# Generowanie nowego UID dla dziedziczonej sceny
			var new_uid = ResourceUID.create_id()
			
			# Tworzenie zawartości pliku .tscn z dziedziczeniem
			var scene_content = "[gd_scene format=3 uid=\"uid://" + str(new_uid) + "\"]\n\n"
			scene_content += "[ext_resource type=\"PackedScene\" path=\"" + fbx_path + "\" id=\"1_base\"]\n\n"
			scene_content += "[node name=\"" + base_name + "\" type=\"Node3D\" instance=ExtResource(\"1_base\")]"
			
			# Zapisywanie pliku
			var file = FileAccess.open(output_path, FileAccess.WRITE)
			if file:
				file.store_string(scene_content)
				file.close()
				print("Utworzono dziedziczoną scenę: ", output_path)
				created_count += 1
			else:
				push_error("Nie można utworzyć pliku: " + output_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	print("\nZakończono! Utworzono ", created_count, " dziedziczonych scen w folderze: ", output_dir)
