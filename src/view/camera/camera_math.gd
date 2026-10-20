class_name CameraMath
extends RefCounted
## Çok ölçekli kamera rig'inin SAF matematiği (T-003; sahne ağacı, Camera3D, girdi yok → başsız test edilir).
## Kamera bir VIEW katmanı kavramıdır: simülasyon/dünya verisine yazmaz; zemin yüksekliği `Callable(x, z) -> float`
## olarak verilir (görünümde `TerrainView.surface_height_at`).
##
## Koordinatlar: dünya metresi, x = doğu, z = güney, y = yukarı (WorldData sözleşmesi). Konumlar `float` (64-bit)
## ayrı bileşenler olarak taşınır; `Vector3` (32-bit) yalnız küçük göreli değerler (göz ofseti, origin'e göre konum)
## içindir (origin rebasing, ADR-0002 §2 / ADR-0001 §5).
##
## Tüm fonksiyonlar saf ve salt okunurdur; durum değiştirenler yeni `CameraState` döndürür.

const MIN_DISTANCE_M := 25.0
const MAX_DISTANCE_M := 90000.0
const MIN_PITCH_DEG := 8.0
const MAX_PITCH_DEG := 88.0
## Tek zoom olayının çarpan sınırı (aşırı tekerlek/kıstırma sıçraması tek adımda dünyayı aşmasın).
const MIN_ZOOM_FACTOR := 0.2
const MAX_ZOOM_FACTOR := 5.0

const NEAR_MIN_M := 0.5
const NEAR_MAX_M := 700.0
const NEAR_PER_DISTANCE := 0.02
const FAR_PER_DISTANCE := 3.0
## Uzak düzlem tabanı: sokaktaki bir kameradan metro ufku (~40-60 km) görünür kalsın.
const FAR_BASE_M := 60000.0
const DEPTH_BITS := 24

const CLEARANCE_MIN_M := 2.0
const CLEARANCE_MAX_M := 30.0
const CLEARANCE_PER_DISTANCE := 0.03

## Origin rebasing: origin bu ızgaraya oturur (2'nin kuvveti: 32-bit'te tam temsil edilir; kayma sırasında yuvarlama
## hatası olmaz) ve odak origin'den `REBASE_TRIGGER_M` uzaklaşınca yeniden oturtulur.
const REBASE_GRID_M := 512.0
const REBASE_TRIGGER_M := 1536.0

const MARCH_MIN_STEP_M := 1.0
const MARCH_MAX_STEP_M := 600.0
const MARCH_STEP_FRACTION := 0.45
const MARCH_MAX_STEPS := 4000
const BISECT_ITERATIONS := 16
const PAN_ITERATIONS := 4


# --- Temel geometri ---

static func clamp_distance(distance: float) -> float:
	if not is_finite(distance):
		return MIN_DISTANCE_M
	return clampf(distance, MIN_DISTANCE_M, MAX_DISTANCE_M)


static func clamp_pitch_deg(pitch_deg: float) -> float:
	if not is_finite(pitch_deg):
		return MIN_PITCH_DEG
	return clampf(pitch_deg, MIN_PITCH_DEG, MAX_PITCH_DEG)


## Bakış yönü (birim). heading 0 = kuzey (-z), 90 = doğu (+x); pitch 90 = aşağı.
static func forward(heading_deg: float, pitch_deg: float) -> Vector3:
	var h := deg_to_rad(heading_deg)
	var p := deg_to_rad(pitch_deg)
	return Vector3(sin(h) * cos(p), -sin(p), -cos(h) * cos(p))


## Yatay sağ yön (birim).
static func right(heading_deg: float) -> Vector3:
	var h := deg_to_rad(heading_deg)
	return Vector3(cos(h), 0.0, sin(h))


## Kameranın dönüşü: x = sağ, y = yukarı, z = -ileri (Godot Camera3D sözleşmesi); roll yok.
static func basis_for(heading_deg: float, pitch_deg: float) -> Basis:
	var f := forward(heading_deg, pitch_deg)
	var r := right(heading_deg)
	return Basis(r, r.cross(f), -f)


## Odaktan göze ofset (göz = odak + ofset), ham yörünge (kenetsiz).
static func eye_offset(s: CameraState) -> Vector3:
	return -forward(s.heading_deg, s.pitch_deg) * s.distance


## Odağı arazi yüzeyine oturtur (yeni durum): focus_y = zemin(focus_x, focus_z). NaN odak güvenli sıfırlanmaz,
## geçersiz durum çağırana döner (`is_valid`).
static func reseat(s: CameraState, ground: Callable) -> CameraState:
	if ground.is_valid() and is_finite(s.focus_x) and is_finite(s.focus_z):
		s.focus_y = float(ground.call(s.focus_x, s.focus_z))
	return s


## Göz üstü açıklığı (m): uzaklıkla ölçeklenir; sokakta insan boyu, metroda anlamsız (göz zaten çok yüksekte).
static func clearance_m(distance: float) -> float:
	return clampf(distance * CLEARANCE_PER_DISTANCE, CLEARANCE_MIN_M, CLEARANCE_MAX_M)


## Göz konumu, dünya koordinatı (Vector3 = 32-bit: BİLGİ/test amaçlı; hassas yol `eye_relative`). Zemin açıklığı
## uygulanmıştır: göz arazinin `clearance_m` altına inmez.
static func eye_world(s: CameraState, ground: Callable) -> Vector3:
	var e := _eye_xyz(s, ground)
	return Vector3(e[0], e[1], e[2])


## Göz konumu origin'e GÖRE (rebasing): çıkarma 64-bit yapılır, 32-bit'e yalnız küçük sonuç iner.
static func eye_relative(s: CameraState, origin_x: float, origin_z: float, ground: Callable) -> Vector3:
	var e := _eye_xyz(s, ground)
	return Vector3(e[0] - origin_x, e[1], e[2] - origin_z)


# --- Ekran ışını / izdüşüm (Camera3D KEEP_HEIGHT sözleşmesi: dikey FOV sabit) ---

## Piksel -> dünya yönü (birim), `s` durumunun HAM yörünge kamerasından.
static func ray_dir(s: CameraState, px: Vector2, viewport: Vector2) -> Vector3:
	var b := basis_for(s.heading_deg, s.pitch_deg)
	var ty := tan(deg_to_rad(s.fov_deg) * 0.5)
	var nx := (2.0 * px.x / viewport.x - 1.0) * ty * (viewport.x / viewport.y)
	var ny := (1.0 - 2.0 * px.y / viewport.y) * ty
	return (-b.z + b.x * nx + b.y * ny).normalized()


## Dünya noktası -> piksel (HAM yörünge kamerası). Kameranın arkasındaki nokta için `Vector2(NAN, NAN)`.
static func project(s: CameraState, wx: float, wy: float, wz: float, viewport: Vector2) -> Vector2:
	var off := eye_offset(s)
	var rel := Vector3(wx - (s.focus_x + off.x), wy - (s.focus_y + off.y), wz - (s.focus_z + off.z))
	var b := basis_for(s.heading_deg, s.pitch_deg)
	var depth := rel.dot(-b.z)
	if depth <= 1.0e-6:
		return Vector2(NAN, NAN)
	var ty := tan(deg_to_rad(s.fov_deg) * 0.5)
	var nx := rel.dot(b.x) / (depth * ty * (viewport.x / viewport.y))
	var ny := rel.dot(b.y) / (depth * ty)
	return Vector2((nx + 1.0) * 0.5 * viewport.x, (1.0 - ny) * 0.5 * viewport.y)


# --- Zemine ışın ---

## Işın ilk zemin kesişimi: {"hit": bool, "t": float, "x", "y", "z"}. Başlangıç zeminin altındaysa t = 0 isabet.
## Adım, zemin üstü yükseklikle orantılı (güvenli adım) ve [MARCH_MIN, MARCH_MAX] aralığında; kesişimden sonra
## ikiye bölme ile inceltilir.
static func ray_ground_hit(ox: float, oy: float, oz: float, dir: Vector3, ground: Callable, max_t: float) -> Dictionary:
	var t := 0.0
	var prev_t := 0.0
	var steps := 0
	while t <= max_t and steps < MARCH_MAX_STEPS:
		var h := (oy + dir.y * t) - float(ground.call(ox + dir.x * t, oz + dir.z * t))
		if h <= 0.0:
			return _bisect(ox, oy, oz, dir, ground, prev_t, t)
		prev_t = t
		t += clampf(h * MARCH_STEP_FRACTION, MARCH_MIN_STEP_M, MARCH_MAX_STEP_M)
		steps += 1
	return {"hit": false}


## Ekran noktasının altındaki zemin {ok, x, y, z}. Zemin kesişimi yoksa odak yüksekliğindeki yatay düzleme
## kesişim (ok = true); o da yoksa (gökyüzü) ok = false.
static func grab_point(s: CameraState, px: Vector2, viewport: Vector2, ground: Callable) -> Dictionary:
	var eye := _eye_xyz(s, ground)
	var dir := ray_dir(s, px, viewport)
	var hit := ray_ground_hit(eye[0], eye[1], eye[2], dir, ground, _march_range(s))
	if hit["hit"]:
		return {"ok": true, "x": hit["x"], "y": hit["y"], "z": hit["z"]}
	if dir.y < -1.0e-6:
		var t := (s.focus_y - eye[1]) / dir.y
		if t > 0.0:
			return {"ok": true, "x": eye[0] + dir.x * t, "y": s.focus_y, "z": eye[2] + dir.z * t}
	return {"ok": false}


# --- Fiiller: zoom, pan, döndürme (yeni durum döner) ---

## Zoom-to-cursor: `px` altındaki zemin noktası ekranda SABİT kalır. Kamera konumu o noktadan görülen ışın boyunca
## ölçeklenir (göz' = A + (göz - A) / çarpan); yön değişmez. Çarpan > 1 yakınlaşır. Geçersiz/NaN/<=0 çarpan: durum
## değişmez. Uzaklık [MIN, MAX] içinde kalır. Gökyüzü altındaysa anchor = ışın üzerinde odak uzaklığındaki nokta.
static func zoom_at(s: CameraState, factor: float, px: Vector2, viewport: Vector2, ground: Callable,
		bounds: Rect2 = Rect2()) -> CameraState:
	if not is_finite(factor) or factor <= 0.0 or not s.is_valid():
		return s.copy()
	var f := clampf(factor, MIN_ZOOM_FACTOR, MAX_ZOOM_FACTOR)
	var wanted := clamp_distance(s.distance / f)
	var f_eff := s.distance / wanted
	if absf(f_eff - 1.0) < 1.0e-9:
		return s.copy()
	var eye := _eye_xyz(s, ground)
	var dir := ray_dir(s, px, viewport)
	var hit := ray_ground_hit(eye[0], eye[1], eye[2], dir, ground, _march_range(s))
	var ax: float = hit["x"] if hit["hit"] else eye[0] + dir.x * s.distance
	var ay: float = hit["y"] if hit["hit"] else eye[1] + dir.y * s.distance
	var az: float = hit["z"] if hit["hit"] else eye[2] + dir.z * s.distance
	var nx := ax + (eye[0] - ax) / f_eff
	var ny := ay + (eye[1] - ay) / f_eff
	var nz := az + (eye[2] - az) / f_eff
	var out := s.copy()
	var fwd := forward(s.heading_deg, s.pitch_deg)
	var axis := ray_ground_hit(nx, ny, nz, fwd, ground, _march_range(s) + s.distance)
	if axis["hit"]:
		out.focus_x = axis["x"]
		out.focus_z = axis["z"]
		out.distance = clamp_distance(float(axis["t"]))
	else:
		out.focus_x = nx + fwd.x * wanted
		out.focus_z = nz + fwd.z * wanted
		out.distance = wanted
	return _finish(out, ground, bounds)


## İçerik-izleyen pan: `from_px` altındaki zemin noktası `to_px`e gelecek şekilde odak kayar (içerik imleci/parmağı
## izler). Eğimli arazide birkaç yinelemeyle yakınsar. Gökyüzü tutulursa (zemin/düzlem yok) durum değişmez.
static func pan_grab(s: CameraState, from_px: Vector2, to_px: Vector2, viewport: Vector2, ground: Callable,
		bounds: Rect2 = Rect2()) -> CameraState:
	if not s.is_valid() or not from_px.is_finite() or not to_px.is_finite():
		return s.copy()
	var held := grab_point(s, from_px, viewport, ground)
	if not held["ok"] or from_px.is_equal_approx(to_px):
		return s.copy()
	var out := s.copy()
	for i in PAN_ITERATIONS:
		var now := grab_point(out, to_px, viewport, ground)
		if not now["ok"]:
			return s.copy()
		out.focus_x += float(held["x"]) - float(now["x"])
		out.focus_z += float(held["z"]) - float(now["z"])
		reseat(out, ground)
	return _finish(out, ground, bounds)


## `px` altındaki zemin noktası etrafında döndürme. Pozitif `radians` = sahne ekranda SAAT YÖNÜNDE döner (InputProfile
## sözleşmesi) = kamera yönü azalır. Kamera ve odak anchor etrafında birlikte döner: anchor ekranda yerinde kalır.
static func rotate_about(s: CameraState, radians: float, px: Vector2, viewport: Vector2, ground: Callable,
		bounds: Rect2 = Rect2()) -> CameraState:
	if not is_finite(radians) or radians == 0.0 or not s.is_valid() or not px.is_finite():
		return s.copy()
	var held := grab_point(s, px, viewport, ground)
	var ax := s.focus_x
	var az := s.focus_z
	if held["ok"]:
		ax = held["x"]
		az = held["z"]
	var theta := -radians
	var c := cos(theta)
	var sn := sin(theta)
	var dx := s.focus_x - ax
	var dz := s.focus_z - az
	var out := s.copy()
	out.focus_x = ax + dx * c - dz * sn
	out.focus_z = az + dx * sn + dz * c
	out.heading_deg = wrapf(s.heading_deg + rad_to_deg(theta), 0.0, 360.0)
	return _finish(out, ground, bounds)


## Odağı yatay düzlemde `offset_m` (sağ, ileri) kadar kaydırır (klavye pan'ı).
static func move_focus(s: CameraState, right_m: float, forward_m: float, ground: Callable,
		bounds: Rect2 = Rect2()) -> CameraState:
	var out := s.copy()
	if not is_finite(right_m) or not is_finite(forward_m):
		return out
	var h := deg_to_rad(s.heading_deg)
	out.focus_x += cos(h) * right_m + sin(h) * forward_m
	out.focus_z += sin(h) * right_m - cos(h) * forward_m
	return _finish(out, ground, bounds)


# --- Yakın/uzak düzlem ---

## (near, far) metre: yakın düzlem uzaklıkla ölçeklenir (derinlik tamponu çözünürlüğü odak çevresinde hep ince),
## uzak düzlem sokaktan metro ufkuna yetecek tabana sahiptir.
static func near_far(distance: float) -> Vector2:
	return Vector2(
		clampf(distance * NEAR_PER_DISTANCE, NEAR_MIN_M, NEAR_MAX_M),
		distance * FAR_PER_DISTANCE + FAR_BASE_M
	)


## `z` uzaklığındaki derinlik tamponu çözünürlüğü (m): bir derinlik adımına karşılık gelen mesafe.
static func depth_resolution_m(near: float, far: float, z: float, bits: int = DEPTH_BITS) -> float:
	return z * z * (far - near) / (far * near) / pow(2.0, float(bits))


# --- Origin rebasing / 32-bit ---

## Değeri 32-bit float'a yuvarlar (rebasing hassasiyet testi ve belgeleme için).
static func f32(value: float) -> float:
	var a := PackedFloat32Array([value])
	return a[0]


## Rebasing origin ızgarası (bileşen): en yakın `REBASE_GRID_M` katı.
static func snap_origin(value: float) -> float:
	return roundf(value / REBASE_GRID_M) * REBASE_GRID_M


# --- Özel ---

## Göz konumu 64-bit bileşenler [x, y, z] (ground geçerliyse zemin açıklığı uygulanır).
static func _eye_xyz(s: CameraState, ground: Callable) -> PackedFloat64Array:
	var off := eye_offset(s)
	var out := PackedFloat64Array([s.focus_x + off.x, s.focus_y + off.y, s.focus_z + off.z])
	if ground.is_valid():
		out[1] = maxf(out[1], float(ground.call(out[0], out[2])) + clearance_m(s.distance))
	return out


static func _march_range(s: CameraState) -> float:
	return s.distance * 4.0 + FAR_BASE_M


static func _finish(s: CameraState, ground: Callable, bounds: Rect2) -> CameraState:
	if bounds.has_area():
		s.focus_x = clampf(s.focus_x, bounds.position.x, bounds.end.x)
		s.focus_z = clampf(s.focus_z, bounds.position.y, bounds.end.y)
	return reseat(s, ground)


static func _bisect(ox: float, oy: float, oz: float, dir: Vector3, ground: Callable, lo: float,
		hi: float) -> Dictionary:
	var a := lo
	var b := hi
	for i in BISECT_ITERATIONS:
		var m := (a + b) * 0.5
		if (oy + dir.y * m) - float(ground.call(ox + dir.x * m, oz + dir.z * m)) <= 0.0:
			b = m
		else:
			a = m
	var x := ox + dir.x * b
	var z := oz + dir.z * b
	return {"hit": true, "t": b, "x": x, "y": float(ground.call(x, z)), "z": z}
