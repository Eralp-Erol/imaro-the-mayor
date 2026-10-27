@tool
extends EditorScenePostImport


func _post_import(scene: Node) -> Object:
	var mat := (
		load("res://assets/hero/vegetation/normal_experiment/normal_proxy.tres").duplicate()
		as ShaderMaterial
	)
	var maps: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://experiments/t057-proxy-normals/projection_maps.json")
	)
	for i in range(3):
		var record: Dictionary = maps["maps"][i]
		for key in ["u", "v"]:
			var row: Array = record[key]
			mat.set_shader_parameter(
				"map_%s_%d" % [key, i], Vector4(row[0], row[1], row[2], row[3])
			)
		var bounds: Array = record["uv_bounds"]
		mat.set_shader_parameter(
			"bounds_%d" % i, Vector4(bounds[0], bounds[1], bounds[2], bounds[3])
		)
	var offset: Array = maps["normal_data_offset_px"]
	var size: Array = maps["normal_data_size_px"]
	mat.set_shader_parameter("normal_data_offset_px", Vector2(offset[0], offset[1]))
	mat.set_shader_parameter("normal_data_size_px", Vector2(size[0], size[1]))
	for child in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			mesh.mesh.surface_set_material(surface, mat)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	return scene
