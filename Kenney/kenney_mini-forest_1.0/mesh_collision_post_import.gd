@tool
extends EditorScenePostImport
## Post-import script for static Kenney mini-forest props.
## Adds a StaticBody3D + trimesh CollisionShape3D as a child of every
## MeshInstance3D found in the imported scene, so every instance of the model
## already carries collision before being baked into a MultiMeshInstance3D
## for rendering.

func _post_import(scene: Node) -> Object:
	_add_collision_recursive(scene, scene)
	return scene

func _add_collision_recursive(node: Node, root: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		var trimesh_shape: Shape3D = mesh.create_trimesh_shape()
		if trimesh_shape != null:
			var body := StaticBody3D.new()
			body.name = "StaticBody3D"
			var collision := CollisionShape3D.new()
			collision.name = "CollisionShape3D"
			collision.shape = trimesh_shape
			node.add_child(body)
			body.owner = root
			body.add_child(collision)
			collision.owner = root
	for child in node.get_children():
		_add_collision_recursive(child, root)
