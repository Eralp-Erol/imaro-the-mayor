extends SceneTree
## T-058 imported geometry/material/import/shadow audit of the hero street-furniture chains (real Godot import).
## Every GLB is LOD0 or LOD1 only (no proxy), imports with meshes/generate_lods=false and no post-import script, uses
## the GLB StandardMaterial3D as-is (opaque, single-sided, roughness 1, metallic 0, lit) and ONE shared atlas Texture2D.

const FUR_DIR := "res://assets/hero/furniture/"
const LEVELS: Array[String] = ["LOD0", "LOD1"]
const EXPECTED_MESHES := 16


func _initialize() -> void:
	call_deferred("_check")


func _scene_transform(item: Node3D, root: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = item
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	if root is Node3D:
		result = (root as Node3D).transform * result
	return result


func _check_material(tag: String, material: Material, state: Dictionary, errors: Array[String]) -> void:
	var mat := material as BaseMaterial3D
	if material == null or material is ShaderMaterial or mat == null:
		errors.append(tag + ": expected the GLB StandardMaterial3D, not a shader")
		return
	var texture := mat.albedo_texture
	if texture == null:
		errors.append(tag + ": missing textured material")
		return
	if state["shared"] == null:
		state["shared"] = texture
	if texture != state["shared"]:
		errors.append(tag + ": duplicate atlas Texture2D resource")
	if not texture.get_image().has_mipmaps():
		errors.append(tag + ": atlas mipmaps missing")
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		errors.append(tag + ": furniture material must be opaque")
	if mat.cull_mode != BaseMaterial3D.CULL_BACK:
		errors.append(tag + ": furniture must be single sided")
	if absf(mat.roughness - 1.0) > 0.001 or absf(mat.metallic) > 0.001:
		errors.append(tag + ": must be matte (roughness 1, metallic 0)")
	if mat.emission_enabled:
		errors.append(tag + ": no emission allowed (no night-light decision)")
	if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		errors.append(tag + ": must stay lit")
	if mat.disable_receive_shadows:
		errors.append(tag + ": must receive normal shadows")


func _check() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/library/catalog.json"))
	var checked := 0
	var state := {"shared": null}
	var errors: Array[String] = []
	for entry in catalog["entries"]:
		if entry.get("source", {}).get("kind") != "hero_furniture":
			continue
		var ident: String = entry["id"]
		var levels: Dictionary = entry["lod_chain"]["levels"]
		var got := levels.keys()
		got.sort()
		if got != LEVELS:
			errors.append("%s: LOD chain levels %s, expected %s" % [ident, got, LEVELS])
		if FileAccess.file_exists(FUR_DIR + ident + "_proxy.glb"):
			errors.append("%s: far proxy asset present (small furniture is culled instead)" % ident)
		for level in levels.keys():
			var glb: String = levels[level]["glb"]
			var tag := "%s %s" % [ident, level]
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
			var named := false
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			for child in node.find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				named = named or String(mesh.name).begins_with("%s_%s" % [ident, level])
				var bounds := _scene_transform(mesh, node) * mesh.mesh.get_aabb()
				lo = lo.min(bounds.position)
				hi = hi.max(bounds.end)
				if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
					errors.append(tag + ": must cast normal shadows")
				for surface in range(mesh.mesh.get_surface_count()):
					surfaces += 1
					triangles += int(mesh.mesh.surface_get_array_index_len(surface) / 3)
					var data: Dictionary = RenderingServer.mesh_get_surface(mesh.mesh.get_rid(), surface)
					if not (data.get("lods", []) as Array).is_empty():
						errors.append(tag + ": generated mesh LODs present")
					_check_material(tag, mesh.mesh.surface_get_material(surface), state, errors)
			if not named:
				errors.append(tag + ": mesh node must be named " + ident + "_" + level)
			if surfaces != 1:
				errors.append("%s: expected 1 surface, got %d" % [tag, surfaces])
			if triangles != int(entry["triangles"][level]):
				errors.append("%s: imported triangle mismatch %d vs %d" % [tag, triangles, entry["triangles"][level]])
			var cat_lo: Array = levels[level]["bbox_min"]
			var cat_hi: Array = levels[level]["bbox_max"]
			if lo.distance_to(Vector3(cat_lo[0], cat_lo[1], cat_lo[2])) > 0.01 \
					or hi.distance_to(Vector3(cat_hi[0], cat_hi[1], cat_hi[2])) > 0.01:
				errors.append("%s: imported bounds differ from catalog" % tag)
			if absf(lo.y) > 0.001:
				errors.append("%s: not ground-origin (min y %.4f)" % [tag, lo.y])
			node.free()
			checked += 1
	if checked != EXPECTED_MESHES:
		errors.append("expected %d imports, got %d" % [EXPECTED_MESHES, checked])
	for error in errors:
		push_error(error)
	if errors.is_empty():
		print(
			"FURNITURE_IMPORT_OK meshes=%d shared_texture=1 opaque=true single_sided=true mipmaps=true" % checked
			+ " generate_lods=false shader_materials=0 post_import_scripts=0 casts_and_receives_shadow=true"
			+ " chain=LOD0/LOD1 proxy=absent emission=none"
		)
	quit(0 if errors.is_empty() else 1)
