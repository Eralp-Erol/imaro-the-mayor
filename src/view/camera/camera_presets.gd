class_name CameraPresets
extends RefCounted
## Kamera preset'leri (T-003 ölçüt 4): `metro`, `district(<bölge kodu>)`, `street(<dünya noktası>)` + T-001 dev
## preset'leri (bay_west, plain_east, harbor, d5_slopes; sayılar T-001'den değişmeden taşındı).
## HER ŞEY `WorldData`'dan türer (bölge çapası/yarıçapı, saha konumu, dünya boyutu); koordinat, bölge kodu veya
## kıyı çizgisi gömülü değildir (LANES kural 8). Saf: sahne ağacı yok; yalnız `WorldData` OKUR.
##
## Metin biçimi (komut satırı `--preset=...` ve kod): `metro` · `district:D4` veya `district(D4)` ·
## `street:12500,8300` / `street(12500,8300)` (dünya x,z metre) · `street:D4` (bölge çapası) · `street:port`
## (T0 saha kimliği veya türü) · `bay_west|plain_east|harbor|d5_slopes`.

## 1-5 tuşları sırası (T-001 ile aynı).
const KEY_ORDER: Array[StringName] = [&"metro", &"bay_west", &"plain_east", &"harbor", &"d5_slopes"]

const FOV_DEG := 40.0

# metro (T-001)
const METRO_FOCUS_SOUTH_SHARE := 0.06
const METRO_DISTANCE_PER_WORLD_WIDTH := 1.45
const METRO_PITCH_DEG := 50.0
# district
const DISTRICT_DISTANCE_PER_RADIUS := 2.2
const DISTRICT_MIN_DISTANCE_M := 3000.0
const DISTRICT_PITCH_DEG := 40.0
## Bölge çapası metro merkezine bundan yakınsa yön 0 (kuzey) kalır; belirsiz yönü uydurmayız.
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


## Metin -> {"ok": bool, "state": CameraState, "name": StringName, "clamped": bool, "error": String}.
## Geçersiz/bilinmeyen preset: ok = false, `error` dolu, `state` metro (güvenli yedek).
static func resolve(spec: String, world: WorldData, ground: Callable = Callable()) -> Dictionary:
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
		"", "metro":
			state = metro(world)
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
		state = metro(world)
		kind = "metro"
	if ground.is_valid():
		CameraMath.reseat(state, ground)
	return {"ok": ok, "state": state, "name": StringName(kind), "clamped": clamped, "error": error}


## `metro`: tüm metro, merkezin biraz güneyine odaklı (T-001 ile aynı biçim), boyut dünyadan.
static func metro(world: WorldData) -> CameraState:
	var f := world.origin + world.size * 0.5 + Vector2(0.0, world.size.y * METRO_FOCUS_SOUTH_SHARE)
	return _state(f, 0.0, METRO_PITCH_DEG, world.size.x * METRO_DISTANCE_PER_WORLD_WIDTH)


## `district(kod)`: odak = bölge çapası, uzaklık = bölge yarıçapından, bakış metro merkezinden bölgeye (körfezden
## kıyıya). Bilinmeyen kod: null.
static func district(world: WorldData, code: StringName) -> CameraState:
	var region := world.region_by_code(code)
	if region == null:
		return null
	var center := world.origin + world.size * 0.5
	var away := region.anchor - center
	var heading := 0.0
	if away.length() >= DISTRICT_MIN_HEADING_OFFSET_M:
		heading = rad_to_deg(atan2(away.x, -away.y))
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
	return metro(world)


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


static func _state(focus_xz: Vector2, heading_deg: float, pitch_deg: float, distance: float) -> CameraState:
	var s := CameraState.new()
	s.focus_x = focus_xz.x
	s.focus_z = focus_xz.y
	s.heading_deg = wrapf(heading_deg, 0.0, 360.0)
	s.pitch_deg = CameraMath.clamp_pitch_deg(pitch_deg)
	s.distance = CameraMath.clamp_distance(distance)
	s.fov_deg = FOV_DEG
	return s
