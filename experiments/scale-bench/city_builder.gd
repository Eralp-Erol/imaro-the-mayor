extends RefCounted
## Disposable benchmark scene builder: terrain, sea, chunked MultiMesh buildings + per-chunk HLOD proxies.

const WORLD := 40000.0
const HALF := WORLD * 0.5
const RES := 256
const STEP := WORLD / float(RES - 1)
const CHUNK := 1000.0
const NCH := 40
const CELL := 30.0  # building grid cell (m)
const PCELL := 250.0  # proxy block cell (m), 4x4 per chunk
const FLOOR_H := 3.0
const SKIRT := 2.5  # buildings are sunk this far below ground
const PALETTE: Array[Color] = [
	Color(0.95, 0.94, 0.90), Color(0.93, 0.88, 0.76), Color(0.90, 0.82, 0.60),
	Color(0.85, 0.66, 0.52), Color(0.72, 0.81, 0.88), Color(0.78, 0.78, 0.76),
]


class MeshBuf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	## p0..p3 are counter-clockwise seen from outside; emitted clockwise (Godot front face).
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color) -> void:
		var nrm := (p1 - p0).cross(p3 - p0).normalized()
		var b := v.size()
		for p in [p0, p1, p2, p3]:
			v.push_back(p)
			n.push_back(nrm)
			c.push_back(col)
		idx.append_array(PackedInt32Array([b, b + 2, b + 1, b, b + 3, b + 2]))

	func tri(p0: Vector3, p1: Vector3, p2: Vector3, col: Color) -> void:
		var nrm := (p1 - p0).cross(p2 - p0).normalized()
		var b := v.size()
		for p in [p0, p1, p2]:
			v.push_back(p)
			n.push_back(nrm)
			c.push_back(col)
		idx.append_array(PackedInt32Array([b, b + 2, b + 1]))

	func box(mn: Vector3, mx: Vector3, wall: Color, top: Color) -> void:
		quad(Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mx.y, mn.z), Vector3(mn.x, mx.y, mn.z), top)
		quad(Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z), wall)
		quad(Vector3(mx.x, mn.y, mn.z), Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), wall)
		quad(Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), wall)
		quad(Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3(mn.x, mx.y, mn.z), wall)

	func to_mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


var detail_end := 3000.0
var cast_shadows := true
var seed_value := 1234
var n_shore := FastNoiseLite.new()
var n_hill := FastNoiseLite.new()
var n_roll := FastNoiseLite.new()
var heights := PackedFloat32Array()
var material := StandardMaterial3D.new()
var variant_meshes: Array[ArrayMesh] = []
var stats := {}
var p_cnt := PackedInt32Array()
var p_f := PackedFloat32Array()
var focus := Vector3.ZERO  # ground point at centre of the densest chunk
var street_x := 0.0  # x of a street line (cell boundary) near focus


func _init() -> void:
	n_shore.seed = seed_value
	n_shore.frequency = 0.00015
	n_hill.seed = seed_value + 1
	n_hill.frequency = 0.00012
	n_hill.fractal_octaves = 3
	n_roll.seed = seed_value + 2
	n_roll.frequency = 0.0004
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	variant_meshes = _make_variants()
	for j in RES:
		for i in RES:
			heights.push_back(height_at(-HALF + i * STEP, -HALF + j * STEP))


func shore_x(z: float) -> float:
	return -6000.0 + 2500.0 * n_shore.get_noise_1d(z)


func height_at(x: float, z: float) -> float:
	var d := x - shore_x(z)
	var roll := n_roll.get_noise_2d(x, z) * 15.0
	if d < 0.0:
		return d * 0.03 + roll * 0.3
	var east := smoothstep(0.35, 0.9, (x + HALF) / WORLD)
	var hills := maxf(0.0, n_hill.get_noise_2d(x, z)) * 700.0 * east
	return d * 0.008 + (hills + roll) * clampf(d / 2000.0, 0.0, 1.0)


## Height of the actual terrain mesh (two triangles per quad) at x,z.
func mesh_height(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / STEP, 0.0, RES - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, RES - 1.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var h00 := heights[j * RES + i]
	var h10 := heights[j * RES + i + 1]
	var h01 := heights[(j + 1) * RES + i]
	var h11 := heights[(j + 1) * RES + i + 1]
	if u + v <= 1.0:
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	return h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)


func make_terrain() -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	var ix := PackedInt32Array()
	for j in RES:
		for i in RES:
			var h := heights[j * RES + i]
			vs.push_back(Vector3(-HALF + i * STEP, h, -HALF + j * STEP))
			var hl := heights[j * RES + maxi(i - 1, 0)]
			var hr := heights[j * RES + mini(i + 1, RES - 1)]
			var hu := heights[maxi(j - 1, 0) * RES + i]
			var hd := heights[mini(j + 1, RES - 1) * RES + i]
			ns.push_back(Vector3(hl - hr, 2.0 * STEP, hu - hd).normalized())
			cs.push_back(_terrain_color(h))
	for j in RES - 1:
		for i in RES - 1:
			var a := j * RES + i
			ix.append_array(PackedInt32Array([a, a + 1, a + RES, a + 1, a + RES + 1, a + RES]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vs
	arrays[Mesh.ARRAY_NORMAL] = ns
	arrays[Mesh.ARRAY_COLOR] = cs
	arrays[Mesh.ARRAY_INDEX] = ix
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	root.add_child(mi)
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD * 1.6, WORLD * 1.6)
	sea.mesh = plane
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.13, 0.42, 0.58)
	sm.roughness = 0.5
	sea.material_override = sm
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sea)
	return root


func _terrain_color(h: float) -> Color:
	if h < 3.0:
		return Color(0.80, 0.74, 0.55)
	if h < 150.0:
		return Color(0.46, 0.58, 0.31).lerp(Color(0.56, 0.52, 0.34), clampf(h / 150.0, 0.0, 1.0))
	return Color(0.56, 0.52, 0.34).lerp(Color(0.62, 0.59, 0.54), clampf((h - 150.0) / 400.0, 0.0, 1.0))


func _make_variants() -> Array[ArrayMesh]:
	var white := Color.WHITE
	var grey := Color(0.7, 0.7, 0.7)
	var out: Array[ArrayMesh] = []
	var a := MeshBuf.new()  # 0: apartment block, flat roof
	a.box(Vector3(-0.5, 0, -0.5), Vector3(0.5, 1, 0.5), white, grey)
	out.append(a.to_mesh())
	var b := MeshBuf.new()  # 1: apartment block with two balcony bands
	b.box(Vector3(-0.5, 0, -0.5), Vector3(0.5, 1, 0.5), white, grey)
	for y in [0.40, 0.70]:
		b.box(Vector3(-0.56, y, -0.56), Vector3(0.56, y + 0.05, 0.56), Color(0.8, 0.8, 0.8), Color(0.8, 0.8, 0.8))
	out.append(b.to_mesh())
	var h := MeshBuf.new()  # 2: house with gable roof (prism)
	var roof := Color(0.78, 0.45, 0.33)
	h.box(Vector3(-0.5, 0, -0.5), Vector3(0.5, 0.7, 0.5), white, roof)
	h.quad(Vector3(-0.5, 0.7, 0.5), Vector3(0.5, 0.7, 0.5), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0), roof)
	h.quad(Vector3(0.5, 0.7, -0.5), Vector3(-0.5, 0.7, -0.5), Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0), roof)
	h.tri(Vector3(0.5, 0.7, 0.5), Vector3(0.5, 0.7, -0.5), Vector3(0.5, 1, 0), white)
	h.tri(Vector3(-0.5, 0.7, -0.5), Vector3(-0.5, 0.7, 0.5), Vector3(-0.5, 1, 0), white)
	out.append(h.to_mesh())
	var w := MeshBuf.new()  # 3: warehouse with roof slab
	w.box(Vector3(-0.5, 0, -0.5), Vector3(0.5, 0.9, 0.5), white, grey)
	w.box(Vector3(-0.52, 0.9, -0.52), Vector3(0.52, 1.0, 0.52), Color(0.85, 0.85, 0.85), Color(0.6, 0.6, 0.6))
	out.append(w.to_mesh())
	return out


## Generates n buildings and returns a Node3D with chunked MultiMeshes + proxies.
func make_city(n: int) -> Node3D:
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var centers: Array[Vector2] = [Vector2(shore_x(0.0) + 3500.0, 0.0)]
	var sigmas: Array[float] = [3200.0]
	var weights: Array[float] = [0.45]
	for k in 5:
		centers.append(Vector2(rng.randf_range(-2000.0, 9000.0), rng.randf_range(-12000.0, 12000.0)))
		sigmas.append(rng.randf_range(1200.0, 2500.0))
		weights.append(0.11)
	var taken := {}
	var per_chunk := {}  # chunk*4+variant -> PackedInt32Array of building ids
	var bx := PackedVector3Array()  # local-to-chunk x,y(ground),z
	var bs := PackedVector3Array()  # scale w,h,d
	var bc := PackedColorArray()
	var bang := PackedFloat32Array()
	_reset_proxy()
	var chunk_count := PackedInt32Array()
	chunk_count.resize(NCH * NCH)
	var made := 0
	var tries := 0
	while made < n and tries < n * 60:
		tries += 1
		var r := rng.randf()
		var ci := 0
		var acc := 0.0
		for k in weights.size():
			acc += weights[k]
			if r <= acc or k == weights.size() - 1:
				ci = k
				break
		var x := centers[ci].x + rng.randfn(0.0, sigmas[ci])
		var z := centers[ci].y + rng.randfn(0.0, sigmas[ci])
		if absf(x) > HALF - 500.0 or absf(z) > HALF - 500.0:
			continue
		var gx := int((x + HALF) / CELL)
		var gz := int((z + HALF) / CELL)
		var key := gx * 4096 + gz
		if taken.has(key):
			continue
		x = (gx + 0.5) * CELL - HALF + rng.randf_range(-2.0, 2.0)
		z = (gz + 0.5) * CELL - HALF + rng.randf_range(-2.0, 2.0)
		var g := mesh_height(x, z)
		if g < 4.0 or absf(mesh_height(x + 40.0, z) - mesh_height(x - 40.0, z)) > 8.0 or absf(mesh_height(x, z + 40.0) - mesh_height(x, z - 40.0)) > 8.0:
			continue
		taken[key] = true
		var variant := 0
		var rv := rng.randf()
		var wd := rng.randf_range(16.0, 22.0)
		var dp := rng.randf_range(16.0, 22.0)
		var ht := rng.randi_range(4, 7) * FLOOR_H
		if rv >= 0.70 and rv < 0.95:
			variant = 2
			wd = rng.randf_range(10.0, 14.0)
			dp = rng.randf_range(10.0, 14.0)
			ht = rng.randi_range(1, 2) * FLOOR_H
		elif rv >= 0.95:
			variant = 3
			wd = rng.randf_range(20.0, 22.0)
			dp = rng.randf_range(20.0, 22.0)
			ht = rng.randi_range(2, 3) * FLOOR_H
		elif rv >= 0.45:
			variant = 1
		var col := PALETTE[rng.randi() % PALETTE.size()] * rng.randf_range(0.9, 1.0)
		col.a = 1.0
		var cx := clampi(int((x + HALF) / CHUNK), 0, NCH - 1)
		var cz := clampi(int((z + HALF) / CHUNK), 0, NCH - 1)
		var cid := cz * NCH + cx
		var id := bx.size()
		bx.push_back(Vector3(x - ((cx + 0.5) * CHUNK - HALF), g - SKIRT, z - ((cz + 0.5) * CHUNK - HALF)))
		bs.push_back(Vector3(wd, ht + SKIRT, dp))
		bc.push_back(col)
		bang.push_back(rng.randi() % 4 * PI * 0.5)
		var pk := cid * 4 + variant
		if not per_chunk.has(pk):
			per_chunk[pk] = PackedInt32Array()
		per_chunk[pk].push_back(id)
		chunk_count[cid] += 1
		_proxy_add(cid, x - (cx * CHUNK - HALF), z - (cz * CHUNK - HALF), g, ht, col)
		made += 1

	var root := Node3D.new()
	root.name = "City"
	var mmi_count := 0
	for pk in per_chunk:
		var cid: int = pk / 4
		var variant: int = pk % 4
		var ids: PackedInt32Array = per_chunk[pk]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = variant_meshes[variant]
		mm.instance_count = ids.size()
		for k in ids.size():
			var id := ids[k]
			var basis := Basis(Vector3.UP, bang[id]) * Basis.from_scale(bs[id])
			mm.set_instance_transform(k, Transform3D(basis, bx[id]))
			mm.set_instance_color(k, bc[id])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = material
		mmi.position = _chunk_origin(cid)
		mmi.visibility_range_end = detail_end
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		mmi_count += 1
	var proxy_count := 0
	var best := 0
	for cid in NCH * NCH:
		if chunk_count[cid] == 0:
			continue
		if chunk_count[cid] > chunk_count[best]:
			best = cid
		var pm := _proxy_mesh(cid)
		var pmi := MeshInstance3D.new()
		pmi.mesh = pm
		pmi.material_override = material
		pmi.position = _chunk_origin(cid)
		pmi.visibility_range_begin = detail_end
		pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pmi)
		proxy_count += 1
	var o := _chunk_origin(best)
	focus = Vector3(o.x, mesh_height(o.x, o.z), o.z)
	street_x = roundf((o.x + HALF) / CELL) * CELL - HALF
	stats = {
		"requested": n, "buildings": made, "multimesh_instances": mmi_count, "proxy_meshes": proxy_count,
		"densest_chunk_buildings": chunk_count[best], "build_ms": (Time.get_ticks_usec() - t0) / 1000.0,
	}
	return root


func _chunk_origin(cid: int) -> Vector3:
	return Vector3((cid % NCH + 0.5) * CHUNK - HALF, 0.0, (cid / NCH + 0.5) * CHUNK - HALF)


func _reset_proxy() -> void:
	p_cnt = PackedInt32Array()
	p_cnt.resize(NCH * NCH * 16)
	p_f = PackedFloat32Array()
	p_f.resize(NCH * NCH * 16 * 5)  # per cell: sum height, ground, r, g, b


## lx, lz are chunk-local metres from the chunk's min corner.
func _proxy_add(cid: int, lx: float, lz: float, g: float, h: float, col: Color) -> void:
	var k := cid * 16 + clampi(int(lz / PCELL), 0, 3) * 4 + clampi(int(lx / PCELL), 0, 3)
	p_cnt[k] += 1
	p_f[k * 5] += h
	p_f[k * 5 + 1] += g
	p_f[k * 5 + 2] += col.r
	p_f[k * 5 + 3] += col.g
	p_f[k * 5 + 4] += col.b


func _proxy_mesh(cid: int) -> ArrayMesh:
	var mb := MeshBuf.new()
	for s in 16:
		var k := cid * 16 + s
		var c := p_cnt[k]
		if c == 0:
			continue
		var fc := float(c)
		var coverage := fc * 340.0 / (PCELL * PCELL)
		var side := PCELL * sqrt(clampf(coverage * 1.6, 0.12, 0.95))
		var cx := (s % 4 + 0.5) * PCELL - CHUNK * 0.5
		var cz := (s / 4 + 0.5) * PCELL - CHUNK * 0.5
		var g := p_f[k * 5 + 1] / fc
		var col := Color(p_f[k * 5 + 2] / fc, p_f[k * 5 + 3] / fc, p_f[k * 5 + 4] / fc)
		mb.box(Vector3(cx - side * 0.5, g - 15.0, cz - side * 0.5), Vector3(cx + side * 0.5, g + p_f[k * 5] / fc, cz + side * 0.5), col, col * 0.8)
	return mb.to_mesh()
