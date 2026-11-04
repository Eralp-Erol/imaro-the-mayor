extends SceneTree


func _initialize() -> void:
	call_deferred("_audit")


func _audit() -> void:
	var errors: Array[String] = []
	var proof: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://experiments/t057-proxy-shell/provenance.json")
	)
	var scene := (
		load("res://assets/hero/vegetation/shell_experiment/plane_shell.glb") as PackedScene
	)
	var node := scene.instantiate()
	var triangles := 0
	var material_ids := {}
	var max_color_error := 0.0
	var max_position_error := 0.0
	var mesh_buffer_bytes := 0
	var vertex_count := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			errors.append("real geometry must cast normal shadows")
		for surface in range(mesh.mesh.get_surface_count()):
			var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat == null:
				errors.append("missing opaque source material")
				continue
			material_ids[mat.get_instance_id()] = true
			if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				errors.append("shell must be opaque")
			if mat.albedo_texture != null or mat.normal_enabled or mat.emission_enabled:
				errors.append("shell must not sample texture/normal/emission")
			if not mat.vertex_color_use_as_albedo or mat.get("vertex_color_is_srgb") != false:
				errors.append("linear source vertex color policy drift")
			if mat.roughness != 1.0 or mat.metallic != 0.0:
				errors.append("opaque matte policy drift")
			if mat.disable_receive_shadows:
				errors.append("shell must receive normal shadows")
			if RenderingServer.has_method("mesh_get_surface"):
				var stored: Dictionary = RenderingServer.call(
					"mesh_get_surface", mesh.mesh.get_rid(), surface
				)
				for key in ["vertex_data", "attribute_data", "skin_data", "index_data"]:
					if stored.has(key):
						mesh_buffer_bytes += stored[key].size()
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			vertex_count += positions.size()
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
			for i in range(0, indices.size(), 3):
				var center := (
					(positions[indices[i]] + positions[indices[i + 1]] + positions[indices[i + 2]])
					/ 3.0
				)
				var nearest: Dictionary = {}
				var distance := INF
				for face in proof["faces"]:
					var expected := Vector3.ZERO
					for point in face["points"]:
						expected += Vector3(point[0], point[1], point[2]) / 3.0
					if expected.distance_to(center) < distance:
						distance = expected.distance_to(center)
						nearest = face
				max_position_error = maxf(max_position_error, distance)
				for j in range(3):
					var index := indices[i + j]
					if absf(normals[index].length() - 1.0) > 0.001:
						errors.append("imported geometric normal missing")
					var rgb: Array = nearest["linear_rgb"]
					var actual := colors[index]
					var error := maxf(
						absf(actual.r - rgb[0]),
						maxf(absf(actual.g - rgb[1]), absf(actual.b - rgb[2]))
					)
					max_color_error = maxf(max_color_error, error)
	if (
		triangles != 36
		or material_ids.size() != 1
		or max_color_error > 0.004
		or max_position_error > 0.001
	):
		errors.append("triangle/material/linear-color import drift")
	print(
		"IMPORT_DIAGNOSTIC max_pos_error=", max_position_error, " raw_color_error=", max_color_error
	)
	print(
		"SHELL_BUFFER vertices=", vertex_count, " native_surface_buffer_bytes=", mesh_buffer_bytes
	)
	for error in errors:
		push_error(error)
	if errors.is_empty():
		print(
			"SHELL_IMPORT_OK triangles=36 materials=1 samplers=0 opaque=true shadows=receive+cast linear_color_error=",
			max_color_error,
			" max_position_error_m=",
			max_position_error
		)
	node.free()
	quit(0 if errors.is_empty() else 1)
