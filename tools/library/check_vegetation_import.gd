extends SceneTree
## T-057 imported geometry/material audit. All30 GLBs must share ONE real texture.


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var catalog: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/library/catalog.json")
	)
	var checked := 0
	var shared: Texture2D
	var canopy_checked := 0
	var errors: Array[String] = []
	for entry in catalog["entries"]:
		if entry.get("source", {}).get("kind") != "hero_vegetation":
			continue
		for level in ["LOD0", "LOD1", "PROXY"]:
			var packed := load(entry["lod_chain"]["levels"][level]["glb"]) as PackedScene
			if packed == null:
				errors.append("missing scene: " + entry["id"])
				continue
			var node := packed.instantiate()
			var triangles := 0
			for child in node.find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				for surface in range(mesh.mesh.get_surface_count()):
					triangles += int(mesh.mesh.surface_get_array_index_len(surface) / 3)
					var material := mesh.mesh.surface_get_material(surface)
					var texture: Texture2D
					var is_canopy: bool = (
						level == "PROXY" and not entry["family"].begins_with("hero_palm")
					)
					if is_canopy:
						var canopy := material as ShaderMaterial
						if (
							canopy == null
							or (
								canopy.shader.resource_path
								!= "res://assets/hero/vegetation/proxy_canopy.gdshader"
							)
						):
							errors.append("missing imported canopy policy: " + entry["id"])
							continue
						texture = canopy.get_shader_parameter("atlas") as Texture2D
						var code := canopy.shader.code
						for required in [
							"cull_disabled",
							"shadows_disabled",
							"diffuse_lambert",
							"ALPHA_SCISSOR_THRESHOLD = 0.45",
							"AO = 0.55",
							"AO_LIGHT_AFFECT = 0.75",
							"local_position - canopy_center"
						]:
							if not code.contains(required):
								errors.append("canopy shader policy drift: " + required)
						if code.contains("unshaded") or code.contains("EMISSION"):
							errors.append("canopy must remain relightable")
						if (
							canopy.get_shader_parameter("canopy_center")
							!= mesh.mesh.get_aabb().get_center()
						):
							errors.append("canopy normal bounds drift")
						if (
							mesh.cast_shadow
							!= GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
						):
							errors.append("canopy ground-shadow policy drift")
						canopy_checked += 1
					else:
						var mat := material as BaseMaterial3D
						if mat == null:
							errors.append("missing source material: " + entry["id"])
							continue
						texture = mat.albedo_texture
						if mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
							errors.append("foliage must be alpha-scissor, not blend")
						if mat.cull_mode != BaseMaterial3D.CULL_DISABLED:
							errors.append("leaf cards must be double sided")
						if absf(mat.alpha_scissor_threshold - 0.45) > 0.001:
							errors.append("alpha cutoff differs from0.45")
					if texture == null:
						errors.append("missing textured material: " + entry["id"])
						continue
					if shared == null:
						shared = texture
					if texture != shared:
						errors.append("duplicate atlas Texture2D resource")
					if not texture.get_image().has_mipmaps():
						errors.append("atlas mipmaps missing")
			if triangles != int(entry["triangles"][level]):
				errors.append("imported triangle mismatch: " + entry["id"])
			node.free()
			checked += 1
	if canopy_checked != 8:
		errors.append("expected8 imported canopy policies")
	if checked != 30:
		errors.append("expected30 imports, got %d" % checked)
	for error in errors:
		push_error(error)
	if errors.is_empty():
		print(
			"VEGETATION_IMPORT_OK meshes=30 shared_texture=1 alpha=MASK double_sided=true mipmaps=true"
			+ " canopy_policies=8 relightable=true received_shadow=false casts_ground_shadow=true"
		)
	quit(0 if errors.is_empty() else 1)
