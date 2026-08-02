@tool
extends EditorScenePostImport

const NO_LOOP_FILES = [
	"Standing Aim Shoot.fbx",
]

func _post_import(scene):
	var file_name = get_source_file().get_file()
	var should_loop = not NO_LOOP_FILES.has(file_name)
	_apply_loop(scene, should_loop)
	return scene

func _apply_loop(node: Node, should_loop: bool) -> void:
	if node is AnimationPlayer:
		for lib_name in node.get_animation_library_list():
			var lib: AnimationLibrary = node.get_animation_library(lib_name)
			for anim_name in lib.get_animation_list():
				var anim: Animation = lib.get_animation(anim_name)
				anim.loop_mode = Animation.LOOP_LINEAR if should_loop else Animation.LOOP_NONE
	for child in node.get_children():
		_apply_loop(child, should_loop)
