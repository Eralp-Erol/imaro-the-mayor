@tool
extends EditorScenePostImport
## Actual asset policy: use exported linear COLOR_0, no texture/tint/alpha path.


func _post_import(scene: Node) -> Object:
	for child in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var material := (
				mesh.mesh.surface_get_material(surface).duplicate() as StandardMaterial3D
			)
			material.vertex_color_use_as_albedo = true
			material.vertex_color_is_srgb = false
			material.disable_receive_shadows = false
			material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
			material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			mesh.mesh.surface_set_material(surface, material)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return scene
