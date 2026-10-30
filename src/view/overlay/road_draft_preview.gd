class_name RoadDraftPreview
extends Node3D
## Yol taslağının dünya içi önizlemesi (T-042 adım 3; VIEW-MODES B "dünya içi işaretler"): iki uç arasında zemine oturan
## şerit + uç halkaları. Yalnız OKUR (zemin yüksekliği görünümün işlevinden), sim'e hiçbir şey yazmaz. Renkler
## `ui_tokens.json`dan (yeni sabit renk yok): geçerli = `ok`, geçersiz = `danger`, uç/yapışma halkası = `focus`.
##
## Sanat düzeltmesi (T-042): geçerli = daha opak şerit + açık tonlu (`text` token'ı) ince DÜZ kenar çizgisi; geçersiz =
## renge EK OLARAK kesikli kenar + çapraz tarama (renk körlüğü: yalnız tona dayanmaz) ve (varsa) çakışan parselin sınırı
## `danger` ile işaretlenir (ret nedeni haritada görünür).
##
## Kullanım: `bind(camera_rig, ground_height)`, `show_snap(p)` (A seçimi öncesi yapışma göstergesi), `show_draft(a, b,
## width_m, valid, conflict_outline)`, `clear()`. Düğüm `view_root` altına eklenir (origin rebasing ile kayar;
## koordinatlar dünya).
## Ekranda ~sabit piksel kalınlık: şerit yol genişliği ile `LINE_PX`in büyüğü; kamera uzaklığı >%8 değişince yeniden
## kurulur. Maliyet: tek MeshInstance3D, iki yüzey (şerit derinlik testli, halkalar derinliksiz) = 2 çizim çağrısı.

const COLOR_VALID := "ok"
const COLOR_INVALID := "danger"
const COLOR_MARKER := "focus"
const COLOR_EDGE := "text"
const RIBBON_ALPHA := 0.62
const RIBBON_ALPHA_VALID := 0.78
const EDGE_ALPHA := 0.92
const HATCH_ALPHA := 0.55
const EDGE_PX := 2.0
const EDGE_MIN_M := 0.2
const DASH_PX := 14.0
const GAP_PX := 9.0
const HATCH_STEP_PX := 24.0
const HATCH_PX := 3.0
const HATCH_MAX_STRIPES := 60
const CONFLICT_PX := 3.5
const CONFLICT_MIN_M := 0.4
const LINE_PX := 5.0
const RING_PX := 11.0
const RING_THICK_PX := 3.0
const RING_SEGMENTS := 24
const MIN_RING_RADIUS_M := 4.0
const MAX_SEGMENT_M := 6.0
const LIFT_BASE_M := 0.15
const LIFT_PER_MPP := 0.7
const REBUILD_RATIO := 0.08
const EDGE_LIFT_M := 0.05

var camera_rig: CameraRig = null
var ground_height: Callable = Callable()

var _mesh_node: MeshInstance3D = null
var _mesh: ArrayMesh = null
var _ribbon_mat: StandardMaterial3D = null
var _marker_mat: StandardMaterial3D = null
var _draft: Dictionary = {}
var _built_mpp: float = -1.0
var _ribbon_color: Color = Color.TRANSPARENT
var _rebuilds: int = 0
var _valid_color: Color
var _invalid_color: Color
var _marker_color: Color
var _edge_color: Color


func _init() -> void:
	name = "RoadDraftPreview"
	var tokens := UiTokens.load_default()
	_valid_color = tokens.color(COLOR_VALID)
	_invalid_color = tokens.color(COLOR_INVALID)
	_marker_color = tokens.color(COLOR_MARKER)
	_edge_color = tokens.color(COLOR_EDGE)
	set_process(false)


func bind(rig: CameraRig, ground: Callable) -> void:
	camera_rig = rig
	ground_height = ground


## Başlangıç seçilmeden önce: yalnız yapışma halkası (`p` dünya m).
func show_snap(p: Vector2) -> void:
	_draft = {"mode": &"snap", "a": p}
	_refresh(true)


## Taslak şeridi: a -> b, `width_m` yol genişliği, `valid` sim kuru koşusu. `conflict_outline`: geçersizse çakışan
## parselin sınırı (boş = işaret yok).
func show_draft(a: Vector2, b: Vector2, width_m: float, valid: bool,
		conflict_outline: PackedVector2Array = PackedVector2Array()) -> void:
	_draft = {"mode": &"draft", "a": a, "b": b, "width_m": width_m, "valid": valid, "conflict": conflict_outline}
	_refresh(true)


func clear() -> void:
	_draft = {}
	_built_mpp = -1.0
	if _mesh_node != null:
		remove_child(_mesh_node)
		_mesh_node.queue_free()
		_mesh_node = null
		_mesh = null
	set_process(false)


func has_mark() -> bool:
	return _mesh_node != null and _mesh_node.visible


func mark_node() -> MeshInstance3D:
	return _mesh_node


func rebuild_count() -> int:
	return _rebuilds


## Son çizilen şerit rengi (köşe rengi, alfa dahil); şerit yoksa saydam.
func ribbon_color() -> Color:
	return _ribbon_color


func valid_color() -> Color:
	return Color(_valid_color, RIBBON_ALPHA_VALID)


func invalid_color() -> Color:
	return Color(_invalid_color, RIBBON_ALPHA)


func _process(_delta: float) -> void:
	_refresh(false)


func _refresh(force: bool) -> void:
	if _draft.is_empty():
		return
	var mpp := _current_mpp()
	set_process(camera_rig != null)
	if not force and _mesh_node != null and absf(mpp - _built_mpp) <= REBUILD_RATIO * maxf(_built_mpp, 0.0001):
		return
	_build(mpp)


func _current_mpp() -> float:
	if camera_rig == null or camera_rig.camera == null or not camera_rig.camera.is_inside_tree():
		return 0.1
	var cam := camera_rig.camera
	var origin := camera_rig.rebase_origin
	var c: Vector2 = _draft["a"]
	var local := Vector3(c.x - origin.x, _ground(c.x, c.y), c.y - origin.y)
	var vp_h := camera_rig.viewport_size_override.y
	if vp_h <= 0.0:
		vp_h = cam.get_viewport().get_visible_rect().size.y
	return ParcelSelectionRing.meters_per_pixel(cam.global_position.distance_to(local), cam.fov, vp_h)


func _ground(x: float, z: float) -> float:
	return float(ground_height.call(x, z)) if ground_height.is_valid() else 0.0


func _build(mpp: float) -> void:
	var lift := LIFT_BASE_M + LIFT_PER_MPP * mpp
	var ribbon_v := PackedVector3Array()
	var ribbon_i := PackedInt32Array()
	var ribbon_c := PackedColorArray()
	var marker_v := PackedVector3Array()
	var marker_i := PackedInt32Array()
	var marker_c := PackedColorArray()
	var line_color := _marker_color
	var a: Vector2 = _draft["a"]
	var ring_r := maxf(MIN_RING_RADIUS_M, RING_PX * mpp)
	var ring_w := maxf(RING_THICK_PX * mpp, 0.4)
	if _draft["mode"] == &"draft":
		var b: Vector2 = _draft["b"]
		var valid := bool(_draft["valid"])
		line_color = _valid_color if valid else _invalid_color
		var width := maxf(float(_draft["width_m"]), LINE_PX * mpp)
		var alpha := RIBBON_ALPHA_VALID if valid else RIBBON_ALPHA
		_ribbon(a, b, width * 0.5, lift, Color(line_color, alpha), ribbon_v, ribbon_i, ribbon_c)
		_edges(a, b, width * 0.5, mpp, lift + EDGE_LIFT_M, valid, ribbon_v, ribbon_i, ribbon_c)
		if not valid:
			_hatch(a, b, width * 0.5, mpp, lift + EDGE_LIFT_M, ribbon_v, ribbon_i, ribbon_c)
			var conflict: PackedVector2Array = _draft.get("conflict", PackedVector2Array())
			_conflict(conflict, mpp, lift + EDGE_LIFT_M, marker_v, marker_i, marker_c)
		_ring(a, ring_r, ring_w, lift, _marker_color, marker_v, marker_i, marker_c)
		_ring(b, ring_r, ring_w, lift, line_color, marker_v, marker_i, marker_c)
	else:
		_ring(a, ring_r, ring_w, lift, _marker_color, marker_v, marker_i, marker_c)
	if _mesh_node == null:
		_mesh = ArrayMesh.new()
		_mesh_node = MeshInstance3D.new()
		_mesh_node.name = "Draft"
		_mesh_node.mesh = _mesh
		_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh_node)
	_mesh.clear_surfaces()
	_ribbon_color = Color.TRANSPARENT
	if not ribbon_v.is_empty():
		_ribbon_color = Color(line_color, RIBBON_ALPHA_VALID if bool(_draft.get("valid", false)) else RIBBON_ALPHA)
		_add_surface(ribbon_v, ribbon_i, ribbon_c, _make_ribbon_material())
	if not marker_v.is_empty():
		_add_surface(marker_v, marker_i, marker_c, _make_marker_material())
	_mesh_node.visible = true
	_built_mpp = mpp
	_rebuilds += 1


func _add_surface(verts: PackedVector3Array, indices: PackedInt32Array, colors: PackedColorArray,
		material: Material) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_COLOR] = colors
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.surface_set_material(_mesh.get_surface_count() - 1, material)


func _make_ribbon_material() -> StandardMaterial3D:
	if _ribbon_mat == null:
		_ribbon_mat = StandardMaterial3D.new()
		_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ribbon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ribbon_mat.vertex_color_use_as_albedo = true
	return _ribbon_mat


func _make_marker_material() -> StandardMaterial3D:
	if _marker_mat == null:
		_marker_mat = StandardMaterial3D.new()
		_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_marker_mat.no_depth_test = true
		_marker_mat.render_priority = 1
		_marker_mat.vertex_color_use_as_albedo = true
	return _marker_mat


## Zemine oturan şerit: eksen `MAX_SEGMENT_M`de bölünür, iki yanal köşe zemin yüksekliğini izler.
func _ribbon(a: Vector2, b: Vector2, half: float, lift: float, color: Color, verts: PackedVector3Array,
		indices: PackedInt32Array, colors: PackedColorArray) -> void:
	var dir := b - a
	if dir.length() < 0.01:
		return
	var normal := Vector2(-dir.y, dir.x).normalized() * half
	var steps := maxi(1, ceili(dir.length() / MAX_SEGMENT_M))
	var base := verts.size()   # aynı dizilere birden çok şerit eklenir: indeksler köşe tabanına göre
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		var l := p + normal
		var r := p - normal
		verts.append(Vector3(l.x, _ground(l.x, l.y) + lift, l.y))
		verts.append(Vector3(r.x, _ground(r.x, r.y) + lift, r.y))
		colors.append(color)
		colors.append(color)
	for s in steps:
		var k := base + s * 2
		indices.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])


func _ring(c: Vector2, radius: float, width: float, lift: float, color: Color, verts: PackedVector3Array,
		indices: PackedInt32Array, colors: PackedColorArray) -> void:
	var base := verts.size()
	var r_in := maxf(radius - width, radius * 0.4)
	for s in RING_SEGMENTS:
		var ang := TAU * float(s) / float(RING_SEGMENTS)
		var dir := Vector2(cos(ang), sin(ang))
		var o := c + dir * radius
		var q := c + dir * r_in
		verts.append(Vector3(o.x, _ground(o.x, o.y) + lift, o.y))
		verts.append(Vector3(q.x, _ground(q.x, q.y) + lift, q.y))
		colors.append(color)
		colors.append(color)
	for s in RING_SEGMENTS:
		var k := base + s * 2
		var nk := base + ((s + 1) % RING_SEGMENTS) * 2
		indices.append_array([k, k + 1, nk, k + 1, nk + 1, nk])


## Şerit kenar çizgileri: geçerli = düz, geçersiz = kesikli (renk dışı ipucu). Açık tonlu `text` token'ı.
func _edges(a: Vector2, b: Vector2, half: float, mpp: float, lift: float, valid: bool, verts: PackedVector3Array,
		indices: PackedInt32Array, colors: PackedColorArray) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.01:
		return
	var axis := dir / length
	var normal := Vector2(-axis.y, axis.x)
	var line_w := maxf(EDGE_PX * mpp, EDGE_MIN_M)
	var color := Color(_edge_color, EDGE_ALPHA)
	for side in [-1.0, 1.0]:
		var off: Vector2 = normal * (half - line_w * 0.5) * float(side)
		if valid:
			_ribbon(a + off, b + off, line_w * 0.5, lift, color, verts, indices, colors)
			continue
		var dash := maxf(DASH_PX * mpp, 0.6)
		var gap := maxf(GAP_PX * mpp, 0.4)
		var t := 0.0
		while t < length:
			var t1 := minf(t + dash, length)
			_ribbon(a + off + axis * t, a + off + axis * t1, line_w * 0.5, lift, color, verts, indices, colors)
			t = t1 + gap


## Çapraz tarama (yalnız geçersiz): sol kenardan sağ kenara eğik çizgiler.
func _hatch(a: Vector2, b: Vector2, half: float, mpp: float, lift: float, verts: PackedVector3Array,
		indices: PackedInt32Array, colors: PackedColorArray) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.01:
		return
	var axis := dir / length
	var normal := Vector2(-axis.y, axis.x)
	var step := maxf(HATCH_STEP_PX * mpp, length / float(HATCH_MAX_STRIPES))
	var skew := half * 2.0
	var color := Color(_edge_color, HATCH_ALPHA)
	var t := step * 0.5
	while t < length:
		var p0 := a + axis * t + normal * half
		var p1 := a + axis * minf(t + skew, length) - normal * half
		_ribbon(p0, p1, maxf(HATCH_PX * mpp, 0.15) * 0.5, lift, color, verts, indices, colors)
		t += step


## Çakışan parselin sınırı `danger` renginde (derinliksiz yüzeye; binaların ardında kaybolmaz).
func _conflict(outline: PackedVector2Array, mpp: float, lift: float, verts: PackedVector3Array,
		indices: PackedInt32Array, colors: PackedColorArray) -> void:
	var n := outline.size()
	if n < 3:
		return
	var half := maxf(CONFLICT_PX * mpp, CONFLICT_MIN_M) * 0.5
	for i in n:
		var p := outline[i]
		var q := outline[(i + 1) % n]
		if p.distance_to(q) < 0.01:
			continue
		var d := (q - p).normalized()
		_ribbon(p - d * half, q + d * half, half, lift, _invalid_color, verts, indices, colors)
