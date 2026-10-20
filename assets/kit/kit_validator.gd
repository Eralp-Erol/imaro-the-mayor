class_name KitValidator
extends RefCounted
## Kit import doğrulayıcı (T-004; spec bölüm 8 "Doğrulama betiği" + bölüm 9.2 K1/K2/K6/K12).
## `inspect_scene`: içe aktarılmış sahneden nesne başına ölçüm; `check_entry`: manifest girdisi + ölçüm → hata listesi
## (boş = geçti). Saf veri girdili olduğu için olumsuz varyantlar testte bellekte bozulmuş ölçümle gösterilir.

const SKIRT_M := 2.5
const POS_TOL := 0.02
const GRID_M := 0.5
const LOD0_MAX := 1500
const LOD1_MIN := 16
const LOD1_MAX := 60
const PROXY_MAX := 14
const MAX_LOD0_MESHES := 40
const TOWER_MIN_M := 21.0
const TOWER_MAX_M := 25.0
const NAME_PATTERN := "^(bld|prop|veh|veg)_[a-z0-9]+(_[a-z0-9]+)*$"
## Spec 7.2 LOD0 üçgen tavanı (aile → tavan). Tanımsız aile için LOD0_MAX.
const FAMILY_LOD0_CAP := {
	"res_old": 450, "res_mid": 450, "res_house": 450, "res_late": 700, "ind_shed": 250, "ind_heritage": 800,
	"civ_hall": 900, "lmk_clocktower": 1200, "prop_human": 40, "veh_car": 60, "prop_chimney": 60, "veg_plane": 120,
}


## Sahnedeki her MeshInstance3D için {tris, surfaces, materials, aabb, uv_ok} (anahtar = düğüm adı).
static func inspect_scene(root: Node) -> Dictionary:
	var out := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var stats := inspect_mesh(mi.mesh)
			var xf := Transform3D.IDENTITY
			var p: Node = mi
			while p != null and p != root:
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var local: AABB = stats["aabb"]
			stats["aabb"] = xf * local
			out[str(mi.name)] = stats
	return out


static func inspect_mesh(mesh: Mesh) -> Dictionary:
	var tris := 0
	var mats: Array[String] = []
	var uv_ok := true
	var aabb := AABB()
	var first := true
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		tris += (idx.size() if idx != null else verts.size()) / 3
		var mat := mesh.surface_get_material(s)
		mats.append(mat.resource_name if mat != null else "")
		var uvs: Variant = arr[Mesh.ARRAY_TEX_UV]
		if uvs == null or (uvs as PackedVector2Array).size() != verts.size():
			uv_ok = false
		else:
			for uv in (uvs as PackedVector2Array):
				var part := uv.x * 16.0 - 0.5
				if absf(part - roundf(part)) > 0.02 or part < -0.02 or part > 15.02 or uv.y <= 0.0 or uv.y > 1.2:
					uv_ok = false
					break
		for v in verts:
			if first:
				aabb = AABB(v, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(v)
	return {"tris": tris, "surfaces": mesh.get_surface_count(), "materials": mats, "aabb": aabb, "uv_ok": uv_ok}


## Bir manifest girdisini ölçümlerine göre denetler. `stats` = inspect_scene çıktısı. Dönüş: hata metinleri.
static func check_entry(entry: Dictionary, stats: Dictionary, glb_sha256: String = "") -> Array[String]:
	var errors: Array[String] = []
	var id := str(entry.get("id", ""))
	var family := str(entry.get("family", ""))
	var kind := str(entry.get("kind", ""))
	var re := RegEx.create_from_string(NAME_PATTERN)
	if re.search(id) == null:
		errors.append("%s: kimlik adlandırma kuralına uymuyor (küçük harf, ASCII, bld_/prop_/veh_/veg_)" % id)
	var lods: Dictionary = entry.get("lods", {})
	if not lods.has("LOD0"):
		errors.append("%s: LOD0 manifestte yok" % id)
		return errors
	if kind in ["building", "landmark"]:
		for need in ["LOD0", "LOD1", "PROXY"]:
			if not lods.has(need):
				errors.append("%s: %s eksik" % [id, need])
	for lod in lods.keys():
		var node_name := "%s_%s" % [id, lod]
		if str(lods[lod].get("node", "")) != node_name:
			errors.append("%s: düğüm adı '%s' != beklenen '%s'" % [id, lods[lod].get("node", ""), node_name])
		if not stats.has(node_name):
			errors.append("%s: içe aktarılan sahnede '%s' düğümü yok" % [id, node_name])
			continue
		var st: Dictionary = stats[node_name]
		if int(st["surfaces"]) != 1:
			errors.append("%s: %s surface sayısı %d (olması gereken 1)" % [id, lod, st["surfaces"]])
		for m in st["materials"]:
			if str(m) != "mat_kit":
				errors.append("%s: %s malzeme adı '%s' (olması gereken mat_kit)" % [id, lod, m])
		if not bool(st["uv_ok"]):
			errors.append("%s: %s UV0 parça kimliği/gölge çarpanı geçersiz" % [id, lod])
		if int(st["tris"]) != int(lods[lod]["tris"]):
			errors.append("%s: %s üçgen %d != manifest %d" % [id, lod, st["tris"], lods[lod]["tris"]])
		var ab: AABB = st["aabb"]
		if kind in ["building", "landmark"] or id == "prop_chimney":
			if absf(ab.position.y + SKIRT_M) > POS_TOL:
				errors.append("%s: %s taban etek y_min=%.3f (olması gereken -%.1f)" % [id, lod, ab.position.y, SKIRT_M])
		elif absf(ab.position.y) > POS_TOL:
			errors.append("%s: %s y_min=%.3f (zemin 0 olmalı)" % [id, lod, ab.position.y])
		var cx := ab.position.x + ab.size.x / 2.0
		if absf(cx) > 0.75:
			errors.append("%s: %s taban merkezi x=%.2f ≠ 0 (pivot ayak izi merkezinde olmalı)" % [id, lod, cx])
	if not stats.has("%s_LOD0" % id):
		return errors
	var s0: Dictionary = stats["%s_LOD0" % id]
	var ab0: AABB = s0["aabb"]
	var cap := int(FAMILY_LOD0_CAP.get(family, LOD0_MAX))
	if int(s0["tris"]) > mini(cap, LOD0_MAX):
		errors.append("%s: LOD0 %d üçgen > tavan %d" % [id, s0["tris"], mini(cap, LOD0_MAX)])
	if lods.has("LOD1") and stats.has("%s_LOD1" % id) and kind in ["building", "landmark"]:
		var t1 := int(stats["%s_LOD1" % id]["tris"])
		var hi := 120 if family == "lmk_clocktower" else LOD1_MAX
		if t1 < LOD1_MIN or t1 > hi:
			errors.append("%s: LOD1 %d üçgen aralık dışı [%d, %d]" % [id, t1, LOD1_MIN, hi])
	if lods.has("PROXY") and stats.has("%s_PROXY" % id) and int(stats["%s_PROXY" % id]["tris"]) > PROXY_MAX:
		errors.append("%s: PROXY %d üçgen > %d" % [id, stats["%s_PROXY" % id]["tris"], PROXY_MAX])
	# Manifest ↔ içe aktarma eşleşmesi (K12): AABB ve yükseklik
	var m_aabb: Dictionary = entry.get("aabb_lod0_m", {})
	if not m_aabb.is_empty():
		var mn := Vector3(m_aabb["min"][0], m_aabb["min"][1], m_aabb["min"][2])
		var mx := Vector3(m_aabb["max"][0], m_aabb["max"][1], m_aabb["max"][2])
		if ab0.position.distance_to(mn) > 0.05 or ab0.end.distance_to(mx) > 0.05:
			errors.append("%s: LOD0 AABB manifestle eşleşmiyor (%s..%s vs %s..%s)" % [id, ab0.position, ab0.end, mn, mx])
	if absf(ab0.end.y - float(entry.get("total_height_m", -1.0))) > 0.05:
		errors.append("%s: toplam yükseklik %.2f != manifest %.2f" % [id, ab0.end.y, entry.get("total_height_m", -1.0)])
	if kind == "building":
		for dim in entry.get("footprint_m", []):
			if absf(float(dim) / GRID_M - roundf(float(dim) / GRID_M)) > 0.001:
				errors.append("%s: ayak izi ölçüsü %.2f 0,5 m ızgarasında değil" % [id, dim])
	if family == "lmk_clocktower":
		var h := ab0.end.y
		if h < TOWER_MIN_M or h > TOWER_MAX_M:
			errors.append("%s: saat kulesi %.2f m kabul aralığı [%.0f, %.0f] dışında" % [id, h, TOWER_MIN_M, TOWER_MAX_M])
	if glb_sha256 != "" and glb_sha256 != str(entry.get("sha256", "")):
		errors.append("%s: .glb sha256 manifestle uyuşmuyor (üretecin yeniden koşulması gerekir)" % id)
	return errors


## Tüm manifest: kit düzeyi kurallar (mesh sayısı) + girdi başına denetim. Dönüş {errors, checked, lod0_meshes}.
static func check_all(lib: KitLibrary) -> Dictionary:
	var errors: Array[String] = []
	var lod0 := 0
	var checked := 0
	for e in lib.entries():
		var root := KitLibrary.instantiate_scene(str(e["glb"]))
		if root == null:
			errors.append("%s: %s yüklenemedi" % [e["id"], e["glb"]])
			continue
		var sha := FileAccess.get_sha256(ProjectSettings.globalize_path(str(e["glb"])))
		errors.append_array(check_entry(e, inspect_scene(root), sha))
		root.free()
		lod0 += 1
		checked += 1
	if lod0 > MAX_LOD0_MESHES:
		errors.append("kit LOD0 mesh sayısı %d > %d" % [lod0, MAX_LOD0_MESHES])
	return {"errors": errors, "checked": checked, "lod0_meshes": lod0}
