extends SceneTree
## T-056: verify imported meshes/materials actually use the declared source/derived textures.


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/library/catalog.json"))
	var checked := 0
	var textures := {}
	for entry in catalog["entries"]:
		if not entry.has("lod_chain"):
			continue
		var chain: Dictionary = entry["lod_chain"]
		var original := (load(chain["levels"]["LOD0"]["glb"]) as PackedScene).instantiate()
		var original_texture: Texture2D
		for original_child in original.find_children("*", "MeshInstance3D", true, false):
			var original_mesh := original_child as MeshInstance3D
			var original_mat := original_mesh.mesh.surface_get_material(0) as BaseMaterial3D
			original_texture = original_mat.albedo_texture
		original.free()
		for level in ["LOD1", "PROXY"]:
			var asset := load(chain["levels"][level]["glb"]) as PackedScene
			if asset == null:
				_fail("missing imported scene: " + entry["id"])
				return
			var node := asset.instantiate()
			var tris := 0
			var expected: String = chain["proxy_atlas" if level == "PROXY" else "atlas"]["path"]
			for child in node.find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				for surface in range(mesh.mesh.get_surface_count()):
					var indices: int = mesh.mesh.surface_get_array_index_len(surface)
					tris += int(indices / 3)
					var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
					if material == null or material.albedo_texture == null:
						_fail("missing textured material: " + entry["id"])
						return
					if material.albedo_texture.resource_path != expected:
						_fail("texture mismatch: " + material.albedo_texture.resource_path + " vs " + expected)
						return
					if level == "LOD1" and material.albedo_texture != original_texture:
						_fail("LOD1 must reuse the actual LOD0 imported texture resource")
						return
					if level == "PROXY" and material.albedo_texture.get_width() != 256:
						_fail("proxy atlas width is not 256")
						return
					textures[material.albedo_texture.resource_path] = material.albedo_texture.get_instance_id()
			if tris != int(chain["levels"][level]["triangles"]):
				_fail("imported triangle mismatch: " + entry["id"])
				return
			node.free()
			checked += 1
	if checked != 42:
		_fail("expected 42 reduced imports, got %s" % checked)
	else:
		print("HERO_LOD_IMPORT_OK meshes=42 declared_texture_resources=", textures.size())
		quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
