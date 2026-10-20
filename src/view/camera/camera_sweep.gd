class_name CameraSweep
extends RefCounted
## Otomatik kamera taraması (T-003 ölçüt 7): metro -> ilçe -> sokak -> ilçe -> metro, yörünge (yön değişir) + sürekli
## zoom. Hareket halinde kare süresi / draw call ölçümü için. KARE SAYACINA bağlıdır (duvar saati değil): kare hızından
## bağımsız, tekrarlanabilir yol. Anahtar durumlar `CameraPresets`'ten (WorldData türevli); koordinat gömülü değil.
## Ara değerler: uzaklık logaritmik (sabit görsel zoom hızı), odak doğrusal, yön en kısa yoldan, eğim doğrusal.

## Ölçüm etiketi eşikleri (m): perf_probe kare süresini bu aşamalara göre ayırır.
const PHASE_METRO_MIN_M := 20000.0
const PHASE_DISTRICT_MIN_M := 3000.0
const PHASE_LOCAL_MIN_M := 300.0
const DEFAULT_FRAMES_PER_LEG := 150
const DEFAULT_HOLD_FRAMES := 60
## Bölge anahtarında yön, sokak bakışından bu kadar (derece) döndürülür: tarama yalnız yakınlaşmaz, yörüngeler de.
const ORBIT_DEG := 90.0

var keys: Array[CameraState] = []
var frames_per_leg: int = DEFAULT_FRAMES_PER_LEG
var hold_frames: int = DEFAULT_HOLD_FRAMES
var _ground: Callable = Callable()


## `street_spec`: `CameraPresets` sokak metni (örn. `street:port`). Çözülemezse `ok` false, yol yalnız metro.
static func build(world: WorldData, street_spec: String, ground: Callable, legs_frames: int = DEFAULT_FRAMES_PER_LEG,
		hold: int = DEFAULT_HOLD_FRAMES) -> CameraSweep:
	var sweep := CameraSweep.new()
	sweep.frames_per_leg = maxi(2, legs_frames)
	sweep.hold_frames = maxi(0, hold)
	sweep._ground = ground
	var metro: CameraState = CameraPresets.resolve("metro", world, ground)["state"]
	var street_r := CameraPresets.resolve(street_spec, world, ground)
	var street: CameraState = street_r["state"]
	var district := _district_near(world, Vector2(street.focus_x, street.focus_z), ground)
	if not street_r["ok"] or district == null:
		sweep.keys = [metro, metro.copy()]
		return sweep
	var district_back := district.copy()
	district_back.heading_deg = wrapf(street.heading_deg + ORBIT_DEG, 0.0, 360.0)
	var metro_back := metro.copy()
	metro_back.heading_deg = wrapf(street.heading_deg + 2.0 * ORBIT_DEG, 0.0, 360.0)
	district.heading_deg = street.heading_deg
	sweep.keys = [metro, district, street, district_back, metro_back]
	return sweep


func total_frames() -> int:
	return hold_frames + (keys.size() - 1) * frames_per_leg


## Kare numarasına göre durum (`frame` 0 = tarama başlangıcı; bekleme süresince metro, sonda son anahtar).
func state_at_frame(frame: int) -> CameraState:
	var t := frame - hold_frames
	if t <= 0 or keys.size() < 2:
		return _seat(keys[0].copy())
	var leg := t / frames_per_leg
	if leg >= keys.size() - 1:
		return _seat(keys[keys.size() - 1].copy())
	return _seat(blend(keys[leg], keys[leg + 1], float(t % frames_per_leg) / float(frames_per_leg)))


## İki anahtar arası ara durum, `u` 0..1 (yumuşak bitiş: smoothstep).
static func blend(a: CameraState, b: CameraState, u: float) -> CameraState:
	var w := smoothstep(0.0, 1.0, clampf(u, 0.0, 1.0))
	var out := a.copy()
	out.distance = exp(lerpf(log(a.distance), log(b.distance), w))
	# Odak, uzaklığın DOĞRUSAL fonksiyonu: odak hızı uzaklıkla orantılı kalır (yakınken hızlı kayma yok, ekranda sabit
	# görsel hız). Uzaklık sabitse (yalnız yörünge) doğrusal.
	var span := b.distance - a.distance
	var g := (out.distance - a.distance) / span if absf(span) > 1.0e-6 else w
	out.focus_x = lerpf(a.focus_x, b.focus_x, g)
	out.focus_z = lerpf(a.focus_z, b.focus_z, g)
	out.pitch_deg = lerpf(a.pitch_deg, b.pitch_deg, w)
	out.heading_deg = wrapf(a.heading_deg + CameraState.angle_delta_deg(a.heading_deg, b.heading_deg) * w, 0.0, 360.0)
	return out


## Ölçüm aşaması etiketi (kamera uzaklığına göre).
static func phase_of(distance: float) -> StringName:
	if distance >= PHASE_METRO_MIN_M:
		return &"metro"
	if distance >= PHASE_DISTRICT_MIN_M:
		return &"district"
	if distance >= PHASE_LOCAL_MIN_M:
		return &"local"
	return &"street"


func _seat(s: CameraState) -> CameraState:
	return CameraMath.reseat(s, _ground)


## Noktaya en yakın bölgenin `district` durumu (nokta bir bölgedeyse o bölge); bölge yoksa null.
static func _district_near(world: WorldData, p: Vector2, ground: Callable) -> CameraState:
	var best: WorldRegion = null
	var best_d := INF
	for region in world.regions:
		var d := (region.anchor - p).length()
		if d < best_d:
			best_d = d
			best = region
	if best == null:
		return null
	var s := CameraPresets.district(world, best.code)
	return CameraMath.reseat(s, ground) if s != null and ground.is_valid() else s
