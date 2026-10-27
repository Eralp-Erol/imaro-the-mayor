extends SceneTree
## T-062 A0: the imported resources match data/library/game_*.json. Hero GLBs: triangle count equals the table, no
## engine-generated mesh LODs (generate_lods=false), AABB equals the table. Ground: imported texture has mipmaps.
## tools/godot.sh --headless --path . --script res://tools/library/check_game_set_import.gd


func _initialize() -> void:
	call_deferred("_check")


func _fail(msg: String) -> void:
	push_error("GAME_SET_IMPORT_FAIL " + msg)
	quit(1)


func _check() -> void:
	var b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/library/game_buildings.json"))
	var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/library/game_ground.json"))
	var meshes := 0
	for m: Dictionary in b["modules"]:
		for level: String in ["LOD0", "LOD1", "PROXY"]:
			var rec: Dictionary = m["lods"][level]
			var scene := load(rec["glb"]) as PackedScene
			if scene == null:
				_fail("not imported: " + rec["glb"])
				return
			var root := scene.instantiate()
			get_root().add_child(root)
			var tris := 0
			var cfg := ConfigFile.new()
			cfg.load(rec["glb"] + ".import")
			var lod_surfaces := 1 if str(cfg.get_value("params", "meshes/generate_lods", true)) != "false" else 0
			var box := AABB()
			var first := true
			for n in root.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				for s in mi.mesh.get_surface_count():
					tris += int(mi.mesh.surface_get_array_index_len(s) / 3)
				var bb := mi.global_transform * mi.mesh.get_aabb()
				box = bb if first else box.merge(bb)
				first = false
			root.free()
			if tris != int(rec["tris"]):
				_fail("%s %s tris %d != %d" % [m["id"], level, tris, int(rec["tris"])])
				return
			if lod_surfaces > 0:
				_fail("%s %s has generate_lods is not false in .import" % [m["id"], level])
				return
			var mn: Array = rec["aabb_m"]["min"]
			var mx: Array = rec["aabb_m"]["max"]
			if absf(box.position.x - mn[0]) > 0.01 or absf(box.end.y - mx[1]) > 0.01 or absf(box.end.z - mx[2]) > 0.01:
				_fail("%s %s aabb mismatch %s vs %s %s" % [m["id"], level, box, mn, mx])
				return
			meshes += 1
	var textures := 0
	for l: Dictionary in g["layers"]:
		var tex := load(l["png"]) as Texture2D
		if tex == null:
			_fail("not imported: " + l["png"])
			return
		var img := tex.get_image()
		if img == null or not img.has_mipmaps():
			_fail("no mipmaps: " + l["png"])
			return
		if img.get_mipmap_count() + 1 != int(l["import"]["mip_levels"]):
			_fail("%s mip levels %d != %d" % [l["id"], img.get_mipmap_count() + 1, int(l["import"]["mip_levels"])])
			return
		textures += 1
	print("GAME_SET_IMPORT_OK meshes=%d ground_textures=%d" % [meshes, textures])
	quit()
