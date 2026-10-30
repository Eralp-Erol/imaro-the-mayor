class_name ParcelSelectionRing
extends Node3D
## Seçili parselin dünya içi işareti (T-041 görsel dilimi; VIEW-MODES-AND-DESIGN-SYSTEM B "dünya içi işaretler: seçim
## halkası"): parsel sınırını zemine oturan ince bir şerit olarak çizer. Yalnız OKUR: parsel çokgeni `WorldParcel`den
## (dünya verisi), zemin yüksekliği görünümün kullandığı işlevden gelir; sim'e hiçbir şey yazmaz (CAN-03/determinizm).
##
## Kullanım: `ring.bind(camera_rig, ground_height)`, `ring.set_band(band)`, `ring.select(parcel)` (null/yok = kaldır),
## `ring.clear()`. Düğüm `view_root` altına eklenir (origin rebasing içeriği birlikte kaydırır; koordinatlar dünya).
##
## Ölçek bandı kuralı (`plan`): kalınlık ekranda ~sabit pikselde kalır (kamera uzaklığıyla ölçeklenir) ama dünya tabanı
## vardır (yakında "çizgi" gibi kalır) ve parsel boyutunun bir kesrini aşmaz. Parsel ekranda `MARKER_BELOW_PX`'ten
## küçükse sınır yerine parsel merkezinde küçük bir halka çizilir. Metro bandında işaret yok (spec: parsel metro'da
## yok). Merkez halkası derinlik testsiz (binaların ardında kaybolmaz). Maliyet: tek MeshInstance3D, tek yüzey = en
## çok 1 çizim çağrısı; ağ yalnız seçimde ve kalınlık >%8 değişince yeniden kurulur (birkaç düzine köşe).
##
## Renk: `ui_tokens.json` `focus` (mevcut vurgu). `world.selection` semantic token'ı henüz yok (B.1: ihtiyaç doğunca
## eklenir); eklenince `COLOR_TOKEN` o adı gösterir.

const COLOR_TOKEN := "focus"
## Bant -> hedef çizgi kalınlığı (ekran pikseli). Metro: işaret yok.
const BAND_LINE_PX := {&"street": 2.0, &"neighborhood": 2.5, &"district": 3.0}
const DEFAULT_LINE_PX := 2.5
const HIDDEN_BANDS: Array[StringName] = [&"metro"]
## Yakında kalınlığın dünya tabanı (m): sokak bandında ince ama görünür çizgi.
const MIN_WIDTH_M := 0.3
## Kalınlık parsel kenar ölçeğinin (sqrt(alan)) bu kesrini aşmaz.
const MAX_WIDTH_FRACTION := 0.2
## Parsel ekranda bundan küçükse (px) sınır yerine merkez halkası.
const MARKER_BELOW_PX := 14.0
const MARKER_RADIUS_PX := 10.0
const MARKER_SEGMENTS := 20
## Zemin üstü kaldırma: tabanı + ekran pikseli başına (z-çakışması ve seyrek uzak arazi için).
const LIFT_BASE_M := 0.12
const LIFT_PER_MPP := 0.6
## Kenar altbölümü (m): şerit araziyi izler.
const MAX_SEGMENT_M := 6.0
## Miter uzunluğu sınırı (keskin köşelerde sivri uç yok).
const MITER_LIMIT := 2.0
const REBUILD_RATIO := 0.08

var camera_rig: CameraRig = null
var ground_height: Callable = Callable()
var color: Color = Color.WHITE
var band: StringName = &""

var _parcel: WorldParcel = null
var _mesh_node: MeshInstance3D = null
var _mesh: ArrayMesh = null
var _material: StandardMaterial3D = null
var _plan: Dictionary = {}
var _built_width_m: float = -1.0
var _built_marker: bool = false
var _rebuilds: int = 0


func _init() -> void:
	name = "ParcelSelectionRing"
	color = UiTokens.load_default().color(COLOR_TOKEN)
	set_process(false)


func bind(rig: CameraRig, ground: Callable) -> void:
	camera_rig = rig
	ground_height = ground


## Ölçek bandı değişti (`CameraRig.scale_band_changed`).
func set_band(band_in: StringName) -> void:
	if band_in == band:
		return
	band = band_in
	if _parcel != null:
		_refresh(true)


## Parseli işaretler; `null` (olmayan kimlik dahil) eski işareti kaldırır, hata vermez.
func select(parcel: WorldParcel) -> void:
	if parcel == null or parcel.outline.size() < 3:
		clear()
		return
	_parcel = parcel
	_refresh(true)


func clear() -> void:
	_parcel = null
	_plan = {}
	_built_width_m = -1.0
	if _mesh_node != null:
		remove_child(_mesh_node)
		_mesh_node.queue_free()
		_mesh_node = null
		_mesh = null
	set_process(false)


func parcel_id() -> int:
	return _parcel.id if _parcel != null else -1


## İşaret düğümü var ve görünür mü (test/ölçüm).
func has_mark() -> bool:
	return _mesh_node != null and _mesh_node.visible


func mark_node() -> MeshInstance3D:
	return _mesh_node


## Son kurulan planın kalınlığı (m); işaret yoksa 0.
func width_m() -> float:
	return float(_plan.get("width_m", 0.0)) if has_mark() else 0.0


func is_marker_mode() -> bool:
	return bool(_plan.get("marker", false)) and has_mark()


func rebuild_count() -> int:
	return _rebuilds


## Saf karar: bant + (metre/piksel) + parsel boyutu (m) -> {visible, marker, width_m, lift_m, radius_m}.
static func plan(band_in: StringName, mpp: float, parcel_size_m: float) -> Dictionary:
	var m := maxf(mpp, 0.0001)
	if band_in in HIDDEN_BANDS:
		return {"visible": false, "marker": false, "width_m": 0.0, "lift_m": 0.0, "radius_m": 0.0}
	var line_px: float = float(BAND_LINE_PX.get(band_in, DEFAULT_LINE_PX))
	var lift := LIFT_BASE_M + LIFT_PER_MPP * m
	if parcel_size_m / m < MARKER_BELOW_PX:
		return {"visible": true, "marker": true, "width_m": line_px * m, "lift_m": lift,
				"radius_m": MARKER_RADIUS_PX * m}
	var width := minf(maxf(MIN_WIDTH_M, line_px * m), MAX_WIDTH_FRACTION * parcel_size_m)
	return {"visible": true, "marker": false, "width_m": width, "lift_m": lift, "radius_m": 0.0}


## Kamera uzaklığı (m), dikey görüş açısı (derece) ve ekran yüksekliği (px) -> bir pikselin dünya karşılığı (m).
static func meters_per_pixel(distance_m: float, fov_deg: float, viewport_h_px: float) -> float:
	return 2.0 * maxf(distance_m, 0.01) * tan(deg_to_rad(fov_deg) * 0.5) / maxf(viewport_h_px, 1.0)


func _process(_delta: float) -> void:
	_refresh(false)


func _refresh(force: bool) -> void:
	if _parcel == null:
		return
	var mpp := _current_mpp()
	var p := plan(band, mpp, sqrt(maxf(_parcel.area, 1.0)))
	if not bool(p["visible"]):
		_plan = p
		if _mesh_node != null:
			_mesh_node.visible = false
		set_process(false)
		return
	set_process(camera_rig != null)
	var width := float(p["width_m"])
	var marker := bool(p["marker"])
	var needs := force or _mesh_node == null or not _mesh_node.visible or marker != _built_marker \
			or absf(width - _built_width_m) > REBUILD_RATIO * maxf(_built_width_m, 0.0001)
	_plan = p
	if not needs:
		return
	_build(p)


func _current_mpp() -> float:
	if camera_rig == null or camera_rig.camera == null or not camera_rig.camera.is_inside_tree():
		return 0.1
	var cam := camera_rig.camera
	var origin := camera_rig.rebase_origin
	var c := _parcel.centroid
	var local := Vector3(c.x - origin.x, _ground(c.x, c.y), c.y - origin.y)
	var vp_h := camera_rig.viewport_size_override.y
	if vp_h <= 0.0:
		vp_h = cam.get_viewport().get_visible_rect().size.y
	return meters_per_pixel(cam.global_position.distance_to(local), cam.fov, vp_h)


func _ground(x: float, z: float) -> float:
	return float(ground_height.call(x, z)) if ground_height.is_valid() else 0.0


func _build(p: Dictionary) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	if bool(p["marker"]):
		_marker_geometry(float(p["radius_m"]), float(p["width_m"]), float(p["lift_m"]), verts, indices)
	else:
		_outline_geometry(float(p["width_m"]) * 0.5, float(p["lift_m"]), verts, indices)
	if verts.is_empty():
		clear()
		return
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	if _mesh_node == null:
		_mesh = ArrayMesh.new()
		_mesh_node = MeshInstance3D.new()
		_mesh_node.name = "Ring"
		_mesh_node.mesh = _mesh
		_mesh_node.material_override = _make_material()
		_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh_node)
	# Merkez halkası bir GÖSTERGEDİR: binaların ardında kalmasın (derinlik testi kapalı). Sınır şeridi zemine oturur.
	_make_material().no_depth_test = bool(p["marker"])
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_node.visible = true
	_built_width_m = float(p["width_m"])
	_built_marker = bool(p["marker"])
	_rebuilds += 1


func _make_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.albedo_color = color
	return _material


## Sınır şeridi: her köşede miter ofseti, kenarlar `MAX_SEGMENT_M`de bölünür, köşeler zemine oturur.
func _outline_geometry(half: float, lift: float, verts: PackedVector3Array, indices: PackedInt32Array) -> void:
	var pts := _clean_outline(_parcel.outline)
	var n := pts.size()
	if n < 3:
		return
	var miters: Array[Vector2] = []
	for i in n:
		var prev := pts[(i + n - 1) % n]
		var cur := pts[i]
		var nxt := pts[(i + 1) % n]
		var n0 := _normal_of(cur - prev)
		var n1 := _normal_of(nxt - cur)
		var m := (n0 + n1) / maxf(1.0 + n0.dot(n1), 0.0001)
		if m.length() > MITER_LIMIT:
			m = m.normalized() * MITER_LIMIT
		miters.append(m * half)
	for i in n:
		var j := (i + 1) % n
		var a := pts[i]
		var b := pts[j]
		var steps := maxi(1, ceili(a.distance_to(b) / MAX_SEGMENT_M))
		var base := verts.size()
		for s in steps + 1:
			var t := float(s) / float(steps)
			var pt := a.lerp(b, t)
			var off := miters[i].lerp(miters[j], t)
			var o := pt + off
			var q := pt - off
			verts.append(Vector3(o.x, _ground(o.x, o.y) + lift, o.y))
			verts.append(Vector3(q.x, _ground(q.x, q.y) + lift, q.y))
		for s in steps:
			var k := base + s * 2
			indices.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])


## Küçük parsel: merkezde halka (dış yarıçap `radius`, kalınlık `width`).
func _marker_geometry(radius: float, width: float, lift: float, verts: PackedVector3Array,
		indices: PackedInt32Array) -> void:
	var c := _parcel.centroid
	var r_in := maxf(radius - width, radius * 0.4)
	for s in MARKER_SEGMENTS:
		var ang := TAU * float(s) / float(MARKER_SEGMENTS)
		var dir := Vector2(cos(ang), sin(ang))
		var o := c + dir * radius
		var q := c + dir * r_in
		verts.append(Vector3(o.x, _ground(o.x, o.y) + lift, o.y))
		verts.append(Vector3(q.x, _ground(q.x, q.y) + lift, q.y))
	for s in MARKER_SEGMENTS:
		var k := s * 2
		var nk := ((s + 1) % MARKER_SEGMENTS) * 2
		indices.append_array([k, k + 1, nk, k + 1, nk + 1, nk])


static func _normal_of(edge: Vector2) -> Vector2:
	var d := edge.normalized()
	return Vector2(-d.y, d.x)


## Kapanış tekrarı ve (neredeyse) çakışık köşeleri atar.
static func _clean_outline(outline: PackedVector2Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in outline:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.01:
			out.append(p)
	while out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= 0.01:
		out.pop_back()
	return out
