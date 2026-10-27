@tool
extends EditorScenePostImport
## Asset import policy, used by the GLB outside the comparison lab too.


func _post_import(scene: Node) -> Object:
	var template := load("res://assets/hero/vegetation/proxy_canopy.tres") as ShaderMaterial
	for child in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var material := template.duplicate() as ShaderMaterial
		var bounds := mesh.mesh.get_aabb()
		material.set_shader_parameter("canopy_center", bounds.get_center())
		material.set_shader_parameter("canopy_extent", bounds.size.max(Vector3.ONE * 0.01))
		for surface in range(mesh.mesh.get_surface_count()):
			mesh.mesh.surface_set_material(surface, material)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	return scene
