extends SceneTree
## T-057 (Karar 5) imported geometry/material/import/shadow audit of the hero vegetation chains.
## Non-palm species: LOD0 + LOD1 only. Palms: LOD0 + LOD1 + PROXY. Every GLB shares ONE real atlas
## texture, imports with meshes/generate_lods=false, uses the GLB material as-is (no ShaderMaterial,
## no post-import script) and casts/receives normal shadows. No retired cross-card proxy may remain.

const VEG_DIR := "res://assets/hero/vegetation/"
const LEGACY_SHARED := [
	"proxy_bakes.json",
	"proxy_canopy.gdshader",
	"proxy_canopy.tres",
	"proxy_import.gd",
]
const EXPECTED_MESHES := 22


func _initialize() -> void:
	call_deferred("_check")


func _expected_levels(family: String) -> Array:
	return ["LOD0", "LOD1", "PROXY"] if family.begins_with("hero_palm") else ["LOD0", "LOD1"]


func _scene_transform(item: Node3D, root: Node) -> Transform3D:
	# The instantiated scene is not in the tree, so global_transform is unavailable.
	var result := Transform3D.IDENTITY
	var current: Node = item
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	if root is Node3D:
		result = (root as Node3D).transform * result
	return result


func _check() -> void:
	var catalog: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/library/catalog.json")
	)
	var checked := 0
	var shared: Texture2D
	var errors: Array[String] = []
	for name in LEGACY_SHARED:
		if FileAccess.file_exists(VEG_DIR + name):
			errors.append("retired proxy policy file still present: " + name)
	for entry in catalog["entries"]:
		if entry.get("source", {}).get("kind") != "hero_vegetation":
			continue
		var ident: String = entry["id"]
		var levels: Dictionary = entry["lod_chain"]["levels"]
		var want := _expected_levels(entry["family"])
		var got := levels.keys()
		got.sort()
		var want_sorted := want.duplicate()
		want_sorted.sort()
		if got != want_sorted:
			errors.append("%s: LOD chain levels %s, expected %s" % [ident, got, want])
		if not entry["family"].begins_with("hero_palm"):
			var legacy := VEG_DIR + "veg_hero_%s_a_proxy.glb" % entry["family"].trim_prefix("hero_")
			if FileAccess.file_exists(legacy) or FileAccess.file_exists(legacy + ".import"):
				errors.append("%s: retired proxy asset still present" % ident)
		for level in levels.keys():
			var glb: String = levels[level]["glb"]
			var tag := "%s %s" % [ident, level]
			# Import settings (a post-import script or generated LODs would silently change the asset).
			var config := ConfigFile.new()
			if config.load(glb + ".import") != OK:
				errors.append(tag + ": missing .import")
			else:
				if config.get_value("params", "meshes/generate_lods", true) != false:
					errors.append(tag + ": meshes/generate_lods must be false")
				if str(config.get_value("params", "import_script/path", "x")) != "":
					errors.append(tag + ": post-import script not allowed")
			var packed := load(glb) as PackedScene
			if packed == null:
				errors.append(tag + ": missing scene")
				continue
			var node := packed.instantiate()
			var triangles := 0
			var surfaces := 0
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			for child in node.find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				var bounds := _scene_transform(mesh, node) * mesh.mesh.get_aabb()
				lo = lo.min(bounds.position)
				hi = hi.max(bounds.end)
				if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
					errors.append(tag + ": must cast normal shadows")
				for surface in range(mesh.mesh.get_surface_count()):
					surfaces += 1
					triangles += int(mesh.mesh.surface_get_array_index_len(surface) / 3)
					var rid := mesh.mesh.get_rid()
					var data: Dictionary = RenderingServer.mesh_get_surface(rid, surface)
					if not (data.get("lods", []) as Array).is_empty():
						errors.append(tag + ": generated mesh LODs present")
					var material := mesh.mesh.surface_get_material(surface)
					if material is ShaderMaterial or material == null:
						errors.append(tag + ": expected the GLB StandardMaterial3D, not a shader")
						continue
					var mat := material as BaseMaterial3D
					if mat == null:
						errors.append(tag + ": non-base material")
						continue
					var texture := mat.albedo_texture
					if texture == null:
						errors.append(tag + ": missing textured material")
						continue
					if shared == null:
						shared = texture
					if texture != shared:
						errors.append(tag + ": duplicate atlas Texture2D resource")
					if not texture.get_image().has_mipmaps():
						errors.append(tag + ": atlas mipmaps missing")
					if mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
						errors.append(tag + ": foliage must be alpha-scissor, not blend")
					if mat.cull_mode != BaseMaterial3D.CULL_DISABLED:
						errors.append(tag + ": leaf cards must be double sided")
					if absf(mat.alpha_scissor_threshold - 0.45) > 0.001:
						errors.append(tag + ": alpha cutoff differs from 0.45")
					if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
						errors.append(tag + ": must stay lit")
					if mat.disable_receive_shadows:
						errors.append(tag + ": must receive normal shadows")
			if surfaces != 1:
				errors.append("%s: expected 1 surface, got %d" % [tag, surfaces])
			if triangles != int(entry["triangles"][level]):
				errors.append("%s: imported triangle mismatch %d vs %d" % [tag, triangles, entry["triangles"][level]])
			# Catalog bbox is glTF +Y up metres (same frame as the imported scene).
			var cat_lo: Array = levels[level]["bbox_min"]
			var cat_hi: Array = levels[level]["bbox_max"]
			if lo.distance_to(Vector3(cat_lo[0], cat_lo[1], cat_lo[2])) > 0.01 or hi.distance_to(Vector3(cat_hi[0], cat_hi[1], cat_hi[2])) > 0.01:
				errors.append("%s: imported bounds differ from catalog" % tag)
			node.free()
			checked += 1
	if checked != EXPECTED_MESHES:
		errors.append("expected %d imports, got %d" % [EXPECTED_MESHES, checked])
	for error in errors:
		push_error(error)
	if errors.is_empty():
		print(
			"VEGETATION_IMPORT_OK meshes=%d shared_texture=1 alpha=MASK double_sided=true mipmaps=true" % checked
			+ " generate_lods=false shader_materials=0 post_import_scripts=0 casts_and_receives_shadow=true"
			+ " nonpalm_chain=LOD0/LOD1 palm_chain=LOD0/LOD1/PROXY legacy_proxy=absent"
		)
	quit(0 if errors.is_empty() else 1)
