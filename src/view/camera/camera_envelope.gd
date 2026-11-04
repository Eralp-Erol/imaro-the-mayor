class_name CameraEnvelope
extends RefCounted
## Kamera zarfı + K1 kadraj kuralı (T-064, ADR-0007, D-006). SAF (sahne ağacı yok, başsız test edilir) ve VERİ SÜRÜMLÜ:
## bütün sınır sayıları `data/view/camera_envelope.json`'dan gelir; kod yalnız algoritmayı taşır.
## Kamera bir görünüm kavramıdır: simülasyon bu sınıfı okumaz (TEK-01).
##
## K1: uzaklık >= `k1_min_distance_m` iken gerçek göz konumundan (zemin açıklığı dahil) ekranın dört köşe ışını
## `y = deniz seviyesi` düzlemiyle kesişir ve dört nokta `sınır - kenar payı` içinde kalmalıdır. Düzlem en alçak görünür
## yüzeydir (arazi ışını daha önce keser): kural muhafazakârdır. Çözüm sırası veridedir (`solve_order`): varsayılan
## eğim -> uzaklık -> odak; pan'da uzaklık HİÇ değişmez (eğim -> odak).
## Sokak bandında (uzaklık < `k1_min_distance_m`) yalnız odak `sınır - pay` içine kenetlenir.

const DATA_PATH := "res://data/view/camera_envelope.json"
const ID_PLAYER := &"player"
const ID_LEGACY := &"legacy"
const MODE_DEFAULT := &"default"
const MODE_PAN := &"pan"
const DEFAULT_ASPECT := 16.0 / 9.0
const DEFAULT_FOV_DEG := 40.0
const SOLVE_ITERATIONS := 24
const VALID_STEPS: Array[StringName] = [&"pitch", &"distance", &"focus"]

var id: StringName = ID_PLAYER
var d_min_m: float = 0.0
var d_max_m: float = 0.0
var pitch_max_deg: float = 0.0
## (uzaklık m, en küçük eğim derece); uzaklığın logaritmasında parçalı doğrusal.
var pitch_curve: Array[Vector2] = []
var k1_enabled: bool = false
var edge_margin_m: float = 0.0
var k1_epsilon_deg: float = 0.0
var k1_min_distance_m: float = 0.0
## Her giriş: {"name": StringName, "min_m": float, "max_m": float}.
var bands: Array[Dictionary] = []
var hysteresis: float = 0.0
var zoom_gates_m: Array[float] = []
var solve_order: Dictionary = {}
var map_exit_distance_m: float = 0.0
var fog_enabled: bool = false
var fog_full_below_m: float = 0.0
var fog_gone_above_m: float = 0.0
## Bina farkında göz açıklığı (ADR-0007 Ek c): göz, çevresindeki `roof_radius_m` içindeki en yüksek çatı +
## `roof_margin_m` üstünde kalır. `roof_active_below_m` altında tam, `roof_fade_to_m`e doğru doğrusal söner.
## `roof_smooth_rate_per_s`: kaldırmanın üstel yumuşatma hızı (kare başı sıçrama yok).
var roof_enabled: bool = false
var roof_radius_m: float = 0.0
var roof_margin_m: float = 0.0
var roof_active_below_m: float = 0.0
var roof_fade_to_m: float = 0.0
var roof_smooth_rate_per_s: float = 0.0
## Yükleme/doğrulama hataları (boş = geçerli).
var errors: PackedStringArray = PackedStringArray()


## `player` zarfı (oyuncu yolu). Hata varsa `errors` dolu + push_error.
static func load_default() -> CameraEnvelope:
	return load_named(ID_PLAYER)


## Geliştirici zarfı: eski 90 km / 25 m / 8 derece, K1 yok.
static func legacy() -> CameraEnvelope:
	return load_named(ID_LEGACY)


static func load_named(env_id: StringName, path: String = DATA_PATH,
		fov_deg: float = DEFAULT_FOV_DEG) -> CameraEnvelope:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var env := CameraEnvelope.new()
	if not parsed is Dictionary or not (parsed as Dictionary).get(String(env_id)) is Dictionary:
		env.id = env_id
		env.errors.append("%s: '%s' zarfı okunamadı" % [path, env_id])
		push_error("CameraEnvelope: " + env.errors[0])
		return env
	env = from_dict((parsed as Dictionary)[String(env_id)] as Dictionary, env_id, fov_deg)
	if not env.errors.is_empty():
		push_error("CameraEnvelope(%s) geçersiz: %s" % [env_id, "; ".join(env.errors)])
	return env


## Bayrak değeri -> zarf. `legacy` yalnız geliştirici derlemesinde (`debug_build`) kabul edilir; dışa aktarılan
## sürümde bayrak yok sayılır (R5). Bilinmeyen değer oyuncu zarfıdır (hata `error` çıktısında).
static func from_flag(value: String, debug_build: bool) -> CameraEnvelope:
	if value.strip_edges().to_lower() == "legacy" and debug_build:
		return legacy()
	return load_default()


static func from_dict(d: Dictionary, env_id: StringName, fov_deg: float = DEFAULT_FOV_DEG) -> CameraEnvelope:
	var env := CameraEnvelope.new()
	env.id = env_id
	env.errors = validate(d, fov_deg)
	if not env.errors.is_empty():
		return env
	env.d_min_m = float(d["d_min_m"])
	env.d_max_m = float(d["d_max_m"])
	env.pitch_max_deg = float(d["pitch_max_deg"])
	for pt in d["pitch_min_curve"] as Array:
		env.pitch_curve.append(Vector2(float((pt as Array)[0]), float((pt as Array)[1])))
	env.k1_enabled = bool(d["k1_enabled"])
	env.edge_margin_m = float(d["edge_margin_m"])
	env.k1_epsilon_deg = float(d["k1_epsilon_deg"])
	env.k1_min_distance_m = float(d["k1_min_distance_m"])
	for b in d["bands"] as Array:
		env.bands.append({"name": StringName(str((b as Dictionary)["name"])),
				"min_m": float((b as Dictionary)["min_m"]), "max_m": float((b as Dictionary)["max_m"])})
	env.hysteresis = float(d["hysteresis"])
	for g in d["zoom_gates_m"] as Array:
		env.zoom_gates_m.append(float(g))
	for mode in (d["solve_order"] as Dictionary):
		var steps: Array[StringName] = []
		for step in (d["solve_order"] as Dictionary)[mode] as Array:
			steps.append(StringName(str(step)))
		env.solve_order[StringName(str(mode))] = steps
	env.map_exit_distance_m = float(d["map_exit_distance_m"])
	var fog: Dictionary = d.get("edge_fog", {})
	env.fog_enabled = bool(fog.get("enabled", false))
	env.fog_full_below_m = float(fog.get("full_below_m", 0.0))
	env.fog_gone_above_m = float(fog.get("gone_above_m", 0.0))
	var roof: Dictionary = d.get("eye_roof_clearance", {})
	env.roof_enabled = bool(roof.get("enabled", false))
	env.roof_radius_m = float(roof.get("radius_m", 0.0))
	env.roof_margin_m = float(roof.get("margin_m", 0.0))
	env.roof_active_below_m = float(roof.get("active_below_m", 0.0))
	env.roof_fade_to_m = float(roof.get("fade_to_m", 0.0))
	env.roof_smooth_rate_per_s = float(roof.get("smooth_rate_per_s", 0.0))
	return env


## Ham veri doğrulayıcı: hata metinleri (boş = geçerli). Yükleyici bunu çağırır; olumsuz testler bozuk sözlük verir.
static func validate(d: Dictionary, fov_deg: float = DEFAULT_FOV_DEG) -> PackedStringArray:
	var out := PackedStringArray()
	for key in ["d_min_m", "d_max_m", "pitch_max_deg", "pitch_min_curve", "k1_enabled", "edge_margin_m",
			"k1_epsilon_deg", "k1_min_distance_m", "bands", "hysteresis", "zoom_gates_m", "solve_order",
			"map_exit_distance_m"]:
		if not d.has(key):
			out.append("alan eksik: %s" % key)
	if not out.is_empty():
		return out
	var d_min := float(d["d_min_m"])
	var d_max := float(d["d_max_m"])
	if not (is_finite(d_min) and is_finite(d_max)) or d_min <= 0.0 or d_min >= d_max:
		out.append("d_min_m (%s) d_max_m'den (%s) küçük ve pozitif olmalı" % [d_min, d_max])
		return out
	var pitch_max := float(d["pitch_max_deg"])
	if pitch_max <= 0.0 or pitch_max > 89.0:
		out.append("pitch_max_deg (0, 89] içinde olmalı")
	out.append_array(_validate_curve(d["pitch_min_curve"], d_min, d_max, pitch_max))
	if not out.is_empty():
		return out
	if bool(d["k1_enabled"]):
		var k1_min := float(d["k1_min_distance_m"])
		if k1_min < d_min or k1_min > d_max:
			out.append("k1_min_distance_m zarf içinde olmalı")
		elif _curve_pitch(d["pitch_min_curve"], k1_min) < fov_deg * 0.5 + float(d["k1_epsilon_deg"]):
			out.append("pitch_min(k1_min_distance_m) = %.2f < FOV/2 + epsilon: K1'e girişte eğim sıçrar"
					% _curve_pitch(d["pitch_min_curve"], k1_min))
		if float(d["edge_margin_m"]) < 0.0:
			out.append("edge_margin_m negatif")
	out.append_array(_validate_bands(d["bands"], d_min, d_max))
	out.append_array(_validate_gates(d["zoom_gates_m"], d_min, d_max))
	var hysteresis := float(d["hysteresis"])
	if hysteresis < 0.0 or hysteresis >= 0.5:
		out.append("hysteresis [0, 0.5) içinde olmalı")
	if not d["solve_order"] is Dictionary:
		out.append("solve_order sözlük olmalı")
	else:
		for mode in [&"default", &"pan"]:
			var steps: Variant = (d["solve_order"] as Dictionary).get(String(mode))
			if not steps is Array or (steps as Array).is_empty():
				out.append("solve_order.%s eksik" % mode)
				continue
			for step in steps as Array:
				if not VALID_STEPS.has(StringName(str(step))):
					out.append("solve_order.%s bilinmeyen adım '%s'" % [mode, step])
		var pan_steps: Variant = (d["solve_order"] as Dictionary).get("pan")
		if pan_steps is Array and (pan_steps as Array).has("distance"):
			out.append("solve_order.pan 'distance' içeremez: pan uzaklığı değiştirmez")
	var exit_m := float(d["map_exit_distance_m"])
	if exit_m < d_min or exit_m > d_max:
		out.append("map_exit_distance_m zarf içinde olmalı")
	out.append_array(_validate_roof(d.get("eye_roof_clearance", {})))
	return out


# --- Sorgular ---

## En küçük izinli eğim (derece) bu uzaklıkta.
func pitch_min_deg(distance: float) -> float:
	return _curve_value(pitch_curve, distance)


func clamp_distance(distance: float) -> float:
	if not is_finite(distance):
		return d_min_m
	return clampf(distance, d_min_m, d_max_m)


func clamp_pitch_deg(pitch_deg: float, distance: float) -> float:
	var lo := pitch_min_deg(distance)
	if not is_finite(pitch_deg):
		return lo
	return clampf(pitch_deg, lo, pitch_max_deg)


func is_legacy() -> bool:
	return id == ID_LEGACY


func band_of(distance: float) -> StringName:
	for b in bands:
		if distance < float(b["max_m"]):
			return b["name"]
	return bands[bands.size() - 1]["name"] if not bands.is_empty() else &""


## Histerezisli bant: mevcut bant, kendi aralığının ±`hysteresis` genişlemesi içinde kaldıkça korunur.
func next_band(distance: float, current: StringName) -> StringName:
	for b in bands:
		if b["name"] == current:
			var lo := float(b["min_m"]) * (1.0 - hysteresis)
			var hi := float(b["max_m"]) * (1.0 + hysteresis)
			if distance >= lo and distance < hi:
				return current
			break
	return band_of(distance)


## TopBar metni anahtarı (`data/ui/strings.tr.json`): yalnız bant sinyalinden türer.
static func band_text_key(band: StringName) -> StringName:
	return StringName("zoom.%s" % band)


## 0..1: bina farkında göz açıklığının uzaklık ağırlığı (tam `roof_active_below_m` altında, `roof_fade_to_m`de 0).
func roof_weight(distance: float) -> float:
	if not roof_enabled:
		return 0.0
	if distance <= roof_active_below_m:
		return 1.0
	if distance >= roof_fade_to_m:
		return 0.0
	return 1.0 - (distance - roof_active_below_m) / (roof_fade_to_m - roof_active_below_m)


## 0..1: sokak bandında dünya-uzayı kenar sisinin gücü (kamera uzaklığına göre; K1 bandında sis kapanır).
func fog_strength(distance: float) -> float:
	if not fog_enabled or fog_gone_above_m <= fog_full_below_m:
		return 0.0
	return 1.0 - smoothstep(fog_full_below_m, fog_gone_above_m, distance)


## Odak için izinli dikdörtgen (sınır - kenar payı).
func inner_rect(bounds: Rect2) -> Rect2:
	if not bounds.has_area():
		return bounds
	var inner := bounds.grow(-edge_margin_m)
	return inner if inner.has_area() else Rect2(bounds.get_center(), Vector2.ZERO)


# --- K1 ---

## Dört köşe ışınının deniz düzlemiyle kesişimi sınır - pay içinde mi? (K1 kapalıysa veya sokak bandındaysa true.)
func footprint_ok(s: CameraState, aspect: float, ground: Callable, bounds: Rect2, sea_level: float = 0.0) -> bool:
	if not k1_enabled or not bounds.has_area() or s.distance < k1_min_distance_m:
		return true
	return _corners_inside(s, aspect, ground, inner_rect(bounds), sea_level)


## Dört köşe kesişim noktası (xz); ışın düzlemi kesmezse o köşe Vector2(INF, INF). Tanı/test.
func footprint_points(s: CameraState, aspect: float, ground: Callable, sea_level: float = 0.0) -> PackedVector2Array:
	var eye := CameraMath.eye_xyz(s, ground)
	var out := PackedVector2Array()
	var vp := Vector2(aspect, 1.0)
	for px in [Vector2(0.0, 0.0), Vector2(aspect, 0.0), Vector2(0.0, 1.0), Vector2(aspect, 1.0)]:
		var dir := CameraMath.ray_dir(s, px, vp)
		var h := eye[1] - sea_level
		if dir.y >= -1.0e-9:
			out.append(Vector2(INF, INF))
		elif h <= 0.0:
			out.append(Vector2(eye[0], eye[2]))
		else:
			var t := h / -dir.y
			out.append(Vector2(eye[0] + dir.x * t, eye[2] + dir.z * t))
	return out


## Zarfı uygular: uzaklık/eğim sınırları, odak kenarı, K1. Saf ve deterministik (girdi/kareden bağımsız): aynı girdi
## bit-eşit çıktı. Geçersiz (NaN) girdi olduğu gibi (kopya) döner; çağıran `is_valid` ile denetler.
func resolve(state: CameraState, aspect: float, ground: Callable, bounds: Rect2, mode: StringName = MODE_DEFAULT,
		sea_level: float = 0.0) -> CameraState:
	var s := state.copy()
	if not s.is_valid() or not is_finite(aspect) or aspect <= 0.0:
		return s
	var inner := inner_rect(bounds)
	s.distance = clamp_distance(s.distance)
	s.pitch_deg = clamp_pitch_deg(s.pitch_deg, s.distance)
	if bounds.has_area():
		s.focus_x = clampf(s.focus_x, inner.position.x, inner.end.x)
		s.focus_z = clampf(s.focus_z, inner.position.y, inner.end.y)
	CameraMath.reseat(s, ground)
	if k1_enabled and bounds.has_area() and s.distance >= k1_min_distance_m \
			and not _corners_inside(s, aspect, ground, inner, sea_level):
		s = _apply_solve_steps(s, mode, aspect, ground, inner, sea_level)
	return s


## En büyük uzaklık (m) ki bu odak/yön/en-boy oranında en dik eğimle (pitch_max) K1 sağlansın; d_max sağlıyorsa d_max.
## Belge tablosu (ADR-0007 §Bağlam) ve tanı için.
func max_distance_at(s: CameraState, aspect: float, ground: Callable, bounds: Rect2, sea_level: float = 0.0) -> float:
	var inner := inner_rect(bounds)
	var probe := s.copy()
	probe.pitch_deg = pitch_max_deg
	if _solvable_at(probe, d_max_m, aspect, ground, inner, sea_level):
		return d_max_m
	if not _solvable_at(probe, k1_min_distance_m, aspect, ground, inner, sea_level):
		return 0.0
	return _bisect_distance(probe, k1_min_distance_m, d_max_m, aspect, ground, inner, sea_level)


## Bu uzaklıkta K1'i sağlayan en küçük eğim (derece); pitch_max bile yetmezse -1. Tanı için.
func required_pitch(s: CameraState, aspect: float, ground: Callable, bounds: Rect2, sea_level: float = 0.0) -> float:
	var probe := s.copy()
	probe.pitch_deg = pitch_min_deg(probe.distance)
	if _corners_inside(probe, aspect, ground, inner_rect(bounds), sea_level):
		return probe.pitch_deg
	return _solve_pitch(probe, aspect, ground, inner_rect(bounds), sea_level)


# --- Özel ---

## Çözüm sırasındaki adımları sırayla dener; ilk geçerli sonuçta durur (hiçbiri çözmezse son durum).
func _apply_solve_steps(start: CameraState, mode: StringName, aspect: float, ground: Callable, inner: Rect2,
		sea_level: float) -> CameraState:
	var s := start
	var steps: Array = solve_order.get(mode, solve_order.get(MODE_DEFAULT, [&"pitch", &"distance", &"focus"]))
	for step in steps:
		match step:
			&"pitch":
				var p := _solve_pitch(s, aspect, ground, inner, sea_level)
				if p >= 0.0:
					s.pitch_deg = p
					return s
			&"distance":
				s = _solve_distance(s, aspect, ground, inner, sea_level)
			&"focus":
				s = _solve_focus(s, aspect, ground, inner, sea_level)
		if _corners_inside(s, aspect, ground, inner, sea_level):
			return s
	return s


func _corners_inside(s: CameraState, aspect: float, ground: Callable, inner: Rect2, sea_level: float) -> bool:
	for p in footprint_points(s, aspect, ground, sea_level):
		if not is_finite(p.x) or not inner.has_point(p):
			return false
	return true


## En küçük geçerli eğim >= mevcut eğim (ikiye bölme; üst uç pitch_max geçerli olmalı). Çözümsüzse -1.
func _solve_pitch(s: CameraState, aspect: float, ground: Callable, inner: Rect2, sea_level: float) -> float:
	var probe := s.copy()
	probe.pitch_deg = pitch_max_deg
	if not _corners_inside(probe, aspect, ground, inner, sea_level):
		return -1.0
	var lo := clampf(s.pitch_deg, pitch_min_deg(s.distance), pitch_max_deg)
	var hi := pitch_max_deg
	for i in SOLVE_ITERATIONS:
		var mid := (lo + hi) * 0.5
		probe.pitch_deg = mid
		if _corners_inside(probe, aspect, ground, inner, sea_level):
			hi = mid
		else:
			lo = mid
	return hi


func _solvable_at(s: CameraState, distance: float, aspect: float, ground: Callable, inner: Rect2,
		sea_level: float) -> bool:
	var probe := s.copy()
	probe.distance = distance
	probe.pitch_deg = pitch_max_deg
	CameraMath.reseat(probe, ground)
	return _corners_inside(probe, aspect, ground, inner, sea_level)


func _bisect_distance(s: CameraState, solvable_m: float, unsolvable_m: float, aspect: float, ground: Callable,
		inner: Rect2, sea_level: float) -> float:
	var lo := solvable_m
	var hi := unsolvable_m
	for i in SOLVE_ITERATIONS:
		var mid := (lo + hi) * 0.5
		if _solvable_at(s, mid, aspect, ground, inner, sea_level):
			lo = mid
		else:
			hi = mid
	return lo


## Uzaklığı en büyük çözülebilir değere indirir (en az k1_min), sonra eğimi oturtur. Hiç çözülmezse k1_min'de bırakır.
func _solve_distance(s: CameraState, aspect: float, ground: Callable, inner: Rect2, sea_level: float) -> CameraState:
	var out := s.copy()
	if _solvable_at(s, k1_min_distance_m, aspect, ground, inner, sea_level):
		out.distance = _bisect_distance(s, k1_min_distance_m, s.distance, aspect, ground, inner, sea_level)
	else:
		out.distance = k1_min_distance_m
	out.pitch_deg = clampf(s.pitch_deg, pitch_min_deg(out.distance), pitch_max_deg)
	CameraMath.reseat(out, ground)
	var p := _solve_pitch(out, aspect, ground, inner, sea_level)
	if p >= 0.0:
		out.pitch_deg = p
	return out


## Odağı dünya merkezine doğru en az kaydırır (en dik eğimle çözülebilir olana kadar), sonra eğimi oturtur.
func _solve_focus(s: CameraState, aspect: float, ground: Callable, inner: Rect2, sea_level: float) -> CameraState:
	var center := inner.get_center()
	var from := Vector2(s.focus_x, s.focus_z)
	var probe := s.copy()
	var lo := 0.0
	var hi := 1.0
	for i in SOLVE_ITERATIONS:
		var mid := (lo + hi) * 0.5
		var f := from.lerp(center, mid)
		probe.focus_x = f.x
		probe.focus_z = f.y
		probe.pitch_deg = pitch_max_deg
		CameraMath.reseat(probe, ground)
		if _corners_inside(probe, aspect, ground, inner, sea_level):
			hi = mid
		else:
			lo = mid
	var out := s.copy()
	var target := from.lerp(center, hi)
	out.focus_x = target.x
	out.focus_z = target.y
	CameraMath.reseat(out, ground)
	var p := _solve_pitch(out, aspect, ground, inner, sea_level)
	if p >= 0.0:
		out.pitch_deg = p
	return out


static func _curve_value(curve: Array[Vector2], distance: float) -> float:
	if curve.is_empty():
		return 0.0
	if not is_finite(distance) or distance <= curve[0].x:
		return curve[0].y
	for i in range(1, curve.size()):
		if distance <= curve[i].x:
			var a := curve[i - 1]
			var b := curve[i]
			var u := (log(distance) - log(a.x)) / (log(b.x) - log(a.x))
			return lerpf(a.y, b.y, u)
	return curve[curve.size() - 1].y


static func _curve_pitch(raw: Variant, distance: float) -> float:
	var curve: Array[Vector2] = []
	for pt in raw as Array:
		curve.append(Vector2(float((pt as Array)[0]), float((pt as Array)[1])))
	return _curve_value(curve, distance)


static func _validate_curve(raw: Variant, d_min: float, d_max: float, pitch_max: float) -> PackedStringArray:
	var out := PackedStringArray()
	if not raw is Array or (raw as Array).size() < 2:
		out.append("pitch_min_curve en az 2 nokta olmalı")
		return out
	var prev := Vector2(-INF, -INF)
	var idx := 0
	for pt in raw as Array:
		if not pt is Array or (pt as Array).size() != 2:
			out.append("pitch_min_curve[%d] [uzaklık, eğim] değil" % idx)
			return out
		var cur := Vector2(float((pt as Array)[0]), float((pt as Array)[1]))
		if cur.x <= prev.x:
			out.append("pitch_min_curve uzaklıkları artmıyor (nokta %d)" % idx)
		if cur.y < prev.y:
			out.append("pitch_min_curve monoton değil: eğim azalıyor (nokta %d)" % idx)
		if cur.y > pitch_max:
			out.append("pitch_min_curve eğimi pitch_max_deg'i aşıyor (nokta %d)" % idx)
		prev = cur
		idx += 1
	var first := Vector2(float(((raw as Array)[0] as Array)[0]), 0.0)
	var last := Vector2(float(((raw as Array)[(raw as Array).size() - 1] as Array)[0]), 0.0)
	if first.x > d_min or last.x < d_max:
		out.append("pitch_min_curve [d_min_m, d_max_m] aralığını kapsamıyor")
	return out


static func _validate_roof(raw: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not raw is Dictionary:
		out.append("eye_roof_clearance sözlük olmalı")
		return out
	var r := raw as Dictionary
	if r.is_empty() or not bool(r.get("enabled", false)):
		return out
	for key in ["radius_m", "margin_m", "active_below_m", "fade_to_m", "smooth_rate_per_s"]:
		if not r.has(key) or not is_finite(float(r[key])):
			out.append("eye_roof_clearance.%s eksik/sonlu değil" % key)
	if not out.is_empty():
		return out
	if float(r["radius_m"]) <= 0.0 or float(r["margin_m"]) < 0.0 or float(r["smooth_rate_per_s"]) <= 0.0:
		out.append("eye_roof_clearance: radius_m > 0, margin_m >= 0, smooth_rate_per_s > 0 olmalı")
	if float(r["active_below_m"]) <= 0.0 or float(r["fade_to_m"]) <= float(r["active_below_m"]):
		out.append("eye_roof_clearance: 0 < active_below_m < fade_to_m olmalı")
	return out


static func _validate_bands(raw: Variant, d_min: float, d_max: float) -> PackedStringArray:
	var out := PackedStringArray()
	if not raw is Array or (raw as Array).is_empty():
		out.append("bands boş")
		return out
	var expect := d_min
	var names: Dictionary = {}
	for b in raw as Array:
		if not b is Dictionary or not (b as Dictionary).has_all(["name", "min_m", "max_m"]):
			out.append("bands girişi {name,min_m,max_m} değil")
			return out
		var lo := float((b as Dictionary)["min_m"])
		var hi := float((b as Dictionary)["max_m"])
		if not is_equal_approx(lo, expect):
			out.append("bant boşluğu/çakışma: '%s' %s'te başlıyor, %s bekleniyordu" % [(b as Dictionary)["name"], lo, expect])
		if hi <= lo:
			out.append("bant '%s' aralığı boş" % (b as Dictionary)["name"])
		if names.has(str((b as Dictionary)["name"])):
			out.append("bant adı tekrar: %s" % (b as Dictionary)["name"])
		names[str((b as Dictionary)["name"])] = true
		expect = hi
	if not is_equal_approx(expect, d_max):
		out.append("bantlar d_max_m'de (%s) bitmiyor (%s)" % [d_max, expect])
	return out


static func _validate_gates(raw: Variant, d_min: float, d_max: float) -> PackedStringArray:
	var out := PackedStringArray()
	if not raw is Array or (raw as Array).is_empty():
		out.append("zoom_gates_m boş")
		return out
	var prev := 0.0
	for g in raw as Array:
		var v := float(g)
		if v <= prev:
			out.append("zoom_gates_m artmıyor")
		if v < d_min - 0.001 or v > d_max + 0.001:
			out.append("zoom_gates_m zarf dışında: %s" % v)
		prev = v
	return out
