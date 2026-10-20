extends SceneTree
## Headless import check for the Blender-generated block.
## Run: Godot --headless --path experiments/asset-pipeline-smoke -s check_import.gd -- [--floors N --width W --depth D --glb res://...]
## Exit 0 only if the AABB matches the requested size within 5% and mat_wall/mat_trim exist.

const FLOOR_H := 3.0
const PARAPET_H := 0.9
const TOL := 0.05


func _arg(name: String, default: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(name)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else default


func _initialize() -> void:
	var floors := int(_arg("--floors", "5"))
	var want := Vector3(float(_arg("--width", "14")), floors * FLOOR_H + PARAPET_H, float(_arg("--depth", "10")))
	var path := _arg("--glb", "res://assets/bld_smoke_5f.glb")
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("FAIL: cannot load %s as PackedScene" % path)
		quit(1)
		return
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame  # let the node enter the tree so global_transform is valid
	var tris := 0
	var aabb := AABB()
	var first := true
	var mats := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var m := mi.mesh
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
				var mat := m.surface_get_material(s)
				if mat != null:
					mats[mat.resource_name] = true
			var wa := mi.global_transform * mi.get_aabb()
			aabb = wa if first else aabb.merge(wa)
			first = false
	var size := aabb.size
	print("glb: %s" % path)
	print("triangles: %d" % tris)
	print("AABB position (m): %s  size (m): %s  (expected size %s)" % [aabb.position, size, want])
	print("materials: %s" % str(mats.keys()))
	var ok := true
	for ax in 3:
		if absf(size[ax] - want[ax]) > want[ax] * TOL:
			push_error("FAIL: axis %d size %.3f vs expected %.3f (>5%%)" % [ax, size[ax], want[ax]])
			ok = false
	for need in ["mat_wall", "mat_trim"]:
		if not mats.has(need):
			push_error("FAIL: material %s missing" % need)
			ok = false
	# Origin at ground centre: min y ~ 0, x/z centred.
	if absf(aabb.position.y) > 0.05 or absf(aabb.get_center().x) > 0.05 or absf(aabb.get_center().z) > 0.05:
		push_error("FAIL: origin is not ground-centre (aabb %s)" % aabb)
		ok = false
	print("RESULT: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
