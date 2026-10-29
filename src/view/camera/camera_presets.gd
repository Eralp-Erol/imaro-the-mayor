class_name CameraPresets
extends RefCounted
## Kamera preset'leri (T-003 ölçüt 4; T-064 ADR-0007): `core`, `district(<bölge kodu>)`, `street(<dünya noktası>)`,
## `start_view(<ilçe kodu>)` + T-001 dev preset'leri (bay_west, plain_east, harbor, d5_slopes; sayılar değişmedi).
## HER ŞEY `WorldData`'dan türer (bölge çapası/yarıçapı, saha konumu, dünya boyutu); koordinat, bölge kodu veya
## kıyı çizgisi gömülü değildir (LANES kural 8). Saf: sahne ağacı yok; yalnız `WorldData` OKUR.
## Her preset `CameraEnvelope.resolve` (zarf + K1) ile çözülür; legacy zarf dışında ham eski görüntü verilmez.
##
## Metin biçimi (komut satırı `--preset=...` ve kod): `core` · `district:D4` veya `district(D4)` ·
## `street:12500,8300` / `street(12500,8300)` (dünya x,z metre) · `street:D4` (bölge çapası) · `street:port`
## (T0 saha kimliği veya türü) · `bay_west|plain_east|harbor|d5_slopes` · `metro_legacy_bench` (YALNIZ legacy zarf).
## `metro` EMEKLİ: açık hata (anlamı sessizce değişip perf serisini yalan söyletmesin; ADR-0007 §Karar 6).

## 1-5 tuşları sırası.
const KEY_ORDER: Array[StringName] = [&"core", &"bay_west", &"plain_east", &"harbor", &"d5_slopes"]
## Yedek (geçersiz/bilinmeyen/emekli preset) ve değer yokken açılış.
const FALLBACK: StringName = &"core"
const RETIRED_METRO_MESSAGE := "metro kaldırıldı: core | metro_legacy_bench"

const FOV_DEG := 40.0

# metro_legacy_bench (T-001'in eski `metro`'su; yalnız legacy zarf)
const METRO_FOCUS_SOUTH_SHARE := 0.06
const METRO_DISTANCE_PER_WORLD_WIDTH := 1.45
const METRO_PITCH_DEG := 50.0
# district
const DISTRICT_DISTANCE_PER_RADIUS := 2.2
const DISTRICT_MIN_DISTANCE_M := 3000.0
const DISTRICT_PITCH_DEG := 40.0
## Bölge çapası dünya merkezine bundan yakınsa yön 0 (kuzey) kalır; belirsiz yönü uydurmayız.
const DISTRICT_MIN_HEADING_OFFSET_M := 1500.0
# street
const STREET_DISTANCE_M := 60.0
const STREET_PITCH_DEG := 12.0
const STREET_DOWNHILL_PROBE_M := 400.0
const STREET_MIN_SLOPE := 0.01
# T-001 dev preset'leri (sayılar T-001'den)
const D5_SLOPES_FOCUS_RADIUS_SHARE := 0.4
const D5_SLOPES_DISTANCE_M := 7000.0
const D5_SLOPES_PITCH_DEG := 35.0


## Metin -> {"ok": bool, "state": CameraState, "name": StringName, "clamped": bool, "adjusted": bool, "error": String}.
## Geçersiz/bilinmeyen/emekli preset: ok = false, `error` dolu, `state` `core` (güvenli yedek).
## `envelope` boşsa oyuncu zarfı.
## `adjusted`: zarf/K1 durumu ham preset'ten farklı çözdü (kenar ilçe kadrajları için tanı).
static func resolve(spec: String, world: WorldData, ground: Callable = Callable(), envelope: CameraEnvelope = null,
		aspect: float = CameraEnvelope.DEFAULT_ASPECT) -> Dictionary:
	var env := envelope if envelope != null else CameraEnvelope.load_default()
	var text := spec.strip_edges()
	var kind := text
	var arg := ""
	var open := text.find("(")
	var colon := text.find(":")
	if open >= 0 and text.ends_with(")"):
		kind = text.substr(0, open)
		arg = text.substr(open + 1, text.length() - open - 2)
	elif colon >= 0:
		kind = text.substr(0, colon)
		arg = text.substr(colon + 1)
	kind = kind.strip_edges().to_lower()
	arg = arg.strip_edges()
	var state: CameraState = null
	var clamped := false
	var error := ""
	match kind:
		"", "core":
			state = core(world, env)
			kind = "core"
		"metro":
			error = RETIRED_METRO_MESSAGE
		"metro_legacy_bench":
			if env.is_legacy():
				state = metro_legacy_bench(world)
			else:
				error = "metro_legacy_bench yalnız --envelope=legacy ile çalışır"
		"district":
			state = district(world, StringName(arg.to_upper()))
			if state == null:
				error = "district: '%s' bölge kodu dünyada yok" % arg
		"street":
			var point := street_point(world, arg)
			if not point["ok"]:
				error = "street: '%s' nokta değil (x,z | bölge kodu | saha kimliği/türü)" % arg
			else:
				var p: Vector2 = point["point"]
				clamped = not world.bounds().has_point(p)
				state = street(world, p)
		"bay_west", "plain_east", "harbor", "d5_slopes":
			state = legacy(world, StringName(kind))
		_:
			error = "bilinmeyen preset '%s'" % spec
	var ok := state != null
	if not ok:
		state = core(world, env)
		kind = String(FALLBACK)
	var raw := state.copy()
	state = env.resolve(state, aspect, ground, world.bounds(), CameraEnvelope.MODE_DEFAULT, world.sea_level)
	var adjusted := not state.is_close_to(raw, 0.01, 0.01)
	return {"ok": ok, "state": state, "name": StringName(kind), "clamped": clamped, "adjusted": adjusted, "error": error}


## Açılış/Home (ADR-0007 §Karar 5): `district(kod)` + zarf çözümü. Kod boş/bilinmiyorsa `core` (kodda ilçe kimliği
## yok; değer oturumdan/veriden gelir, T-043). Dönüş `resolve` ile aynı biçim.
static func start_view(world: WorldData, district_code: StringName, ground: Callable = Callable(),
		envelope: CameraEnvelope = null, aspect: float = CameraEnvelope.DEFAULT_ASPECT) -> Dictionary:
	var code := String(district_code).strip_edges()
	if code.is_empty() or world.region_by_code(StringName(code.to_upper())) == null:
		return resolve(String(FALLBACK), world, ground, envelope, aspect)
	return resolve("district:%s" % code, world, ground, envelope, aspect)


## `core`: dünya merkezi, `d_max`, K1'in çözdüğü eğim (oyuncunun görebileceği en uzak, ortalı görünüm).
static func core(world: WorldData, envelope: CameraEnvelope) -> CameraState:
	var f := world.origin + world.size * 0.5
	return _state(f, 0.0, envelope.pitch_min_deg(envelope.d_max_m), envelope.d_max_m, false)


## `metro_legacy_bench`: ESKİ `metro` durumu birebir (dünya genişliği x 1,45 / 50 derece); perf serisi sürekliliği için.
static func metro_legacy_bench(world: WorldData) -> CameraState:
	var f := world.origin + world.size * 0.5 + Vector2(0.0, world.size.y * METRO_FOCUS_SOUTH_SHARE)
	return _state(f, 0.0, METRO_PITCH_DEG, world.size.x * METRO_DISTANCE_PER_WORLD_WIDTH)


## `district(kod)`: odak = bölge çapası, uzaklık = bölge yarıçapından, bakış İÇE (çapa -> dünya merkezi). Dışa bakış
## K1 altında kenar ilçelerinde dik eğim ister; içe bakış dengelidir (ADR-0007 §Karar 5, kompozisyon design-director
## incelemesinde). Bilinmeyen kod: null.
static func district(world: WorldData, code: StringName) -> CameraState:
	var region := world.region_by_code(code)
	if region == null:
		return null
	var center := world.origin + world.size * 0.5
	var inward := center - region.anchor
	var heading := 0.0
	if inward.length() >= DISTRICT_MIN_HEADING_OFFSET_M:
		heading = rad_to_deg(atan2(inward.x, -inward.y))
	var distance := maxf(maxf(region.radius.x, region.radius.y) * DISTRICT_DISTANCE_PER_RADIUS, DISTRICT_MIN_DISTANCE_M)
	return _state(region.anchor, heading, DISTRICT_PITCH_DEG, distance)


## `street(nokta)`: insan ölçeği. Odak = dünya noktası (metro sınırına kenetlenir), bakış = yokuş aşağı (kıyıda
## genelde suya doğru; eğim yoksa kuzey). Yükseklik arazi yüzeyinden.
static func street(world: WorldData, point: Vector2) -> CameraState:
	var p := Vector2(
		clampf(point.x, world.origin.x, world.origin.x + world.size.x),
		clampf(point.y, world.origin.y, world.origin.y + world.size.y)
	)
	return _state(p, _downhill_heading(world, p), STREET_PITCH_DEG, STREET_DISTANCE_M)


## Sokak noktası metni: "x,z" | bölge kodu | saha kimliği -> {"ok", "point": Vector2}.
static func street_point(world: WorldData, arg: String) -> Dictionary:
	var parts := arg.split(",", false)
	if parts.size() == 2 and parts[0].strip_edges().is_valid_float() and parts[1].strip_edges().is_valid_float():
		return {"ok": true, "point": Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())}
	var region := world.region_by_code(StringName(arg.to_upper()))
	if region != null:
		return {"ok": true, "point": region.anchor}
	var site := world.site_by_id(StringName(arg.to_lower()))
	if site == null:
		for candidate in world.sites:
			if String(candidate.kind) == arg.to_lower():  # "port" -> ilk liman sahası
				site = candidate
				break
	if site != null:
		return {"ok": true, "point": site.position}
	return {"ok": false}


## T-001 preset'leri (kamera sayıları değişmedi).
static func legacy(world: WorldData, preset: StringName) -> CameraState:
	var size := world.size
	var center := world.origin + size * 0.5
	match preset:
		&"bay_west":
			return _state(world.origin + size * Vector2(0.17, 0.5), 78.0, 32.0, 17000.0)
		&"plain_east":
			var d4 := world.region_by_code(&"D4")
			var d5 := world.region_by_code(&"D5")
			var f := center
			if d4 != null and d5 != null:
				f = (d4.anchor + d5.anchor) * 0.5 + Vector2(0.0, 1500.0)
			return _state(f, 150.0, 38.0, 24000.0)
		&"d5_slopes":
			return _d5_slopes(world, center)
		&"harbor":
			var port := world.port_site.position if world.port_site != null else center
			return _state(port, 235.0, 42.0, 8500.0)
	return metro_legacy_bench(world)


static func _d5_slopes(world: WorldData, center: Vector2) -> CameraState:
	var d5 := world.region_by_code(&"D5")
	var to_d5 := Vector2(1.0, 0.0)
	var f := center
	if d5 != null:
		var away := d5.anchor - center
		to_d5 = away.normalized() if away.length() > 1.0 else to_d5
		# Odak: D5 çapasından metro merkezine (körfez/ova) doğru, küçük yarıçapın bir oranı kadar alt yamaç.
		f = d5.anchor - to_d5 * minf(d5.radius.x, d5.radius.y) * D5_SLOPES_FOCUS_RADIUS_SHARE
	# Kamera ova/körfez tarafında, D5'e (yamaca) doğru bakar: yön = metro merkezinden D5'e.
	return _state(f, rad_to_deg(atan2(to_d5.x, -to_d5.y)), D5_SLOPES_PITCH_DEG, D5_SLOPES_DISTANCE_M)


## En dik iniş yönünün yönü (derece); eğim ihmal edilebilirse 0.
static func _downhill_heading(world: WorldData, p: Vector2) -> float:
	var d := STREET_DOWNHILL_PROBE_M
	var gx := (world.height_at(p.x + d, p.y) - world.height_at(p.x - d, p.y)) / (2.0 * d)
	var gz := (world.height_at(p.x, p.y + d) - world.height_at(p.x, p.y - d)) / (2.0 * d)
	if sqrt(gx * gx + gz * gz) < STREET_MIN_SLOPE:
		return 0.0
	var down := Vector2(-gx, -gz)
	return wrapf(rad_to_deg(atan2(down.x, -down.y)), 0.0, 360.0)


## Ham durum; zarf sınırlarını `CameraEnvelope.resolve` uygular (güvenlik tabanı yalnız NaN/sonsuza karşı).
static func _state(focus_xz: Vector2, heading_deg: float, pitch_deg: float, distance: float,
		safety_clamp: bool = true) -> CameraState:
	var s := CameraState.new()
	s.focus_x = focus_xz.x
	s.focus_z = focus_xz.y
	s.heading_deg = wrapf(heading_deg, 0.0, 360.0)
	s.pitch_deg = CameraMath.clamp_pitch_deg(pitch_deg) if safety_clamp else pitch_deg
	s.distance = CameraMath.clamp_distance(distance) if safety_clamp else distance
	s.fov_deg = FOV_DEG
	return s
