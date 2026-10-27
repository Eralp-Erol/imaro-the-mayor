extends SceneTree
## T-057 imported geometry/material audit. All30 GLBs must share ONE real texture.


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/library/catalog.json"))
	var checked := 0
	var shared: Texture2D
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
					var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
					if mat == null or mat.albedo_texture == null:
						errors.append("missing textured material: " + entry["id"])
						continue
					if shared == null:
						shared = mat.albedo_texture
					if mat.albedo_texture != shared:
						errors.append("duplicate atlas Texture2D resource")
					if mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
						errors.append("foliage must be alpha-scissor, not blend")
					if mat.cull_mode != BaseMaterial3D.CULL_DISABLED:
						errors.append("leaf cards must be double sided")
					if absf(mat.alpha_scissor_threshold - 0.45) > 0.001:
						errors.append("alpha cutoff differs from0.45")
					if not mat.albedo_texture.get_image().has_mipmaps():
						errors.append("atlas mipmaps missing")
			if triangles != int(entry["triangles"][level]):
				errors.append("imported triangle mismatch: " + entry["id"])
			node.free()
			checked += 1
	if checked != 30:
		errors.append("expected30 imports, got %d" % checked)
	for error in errors:
		push_error(error)
	if errors.is_empty():
		print("VEGETATION_IMPORT_OK meshes=30 shared_texture=1 alpha=MASK double_sided=true mipmaps=true")
	quit(0 if errors.is_empty() else 1)
