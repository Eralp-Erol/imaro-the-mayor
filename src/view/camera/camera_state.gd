class_name CameraState
extends RefCounted
## Çok ölçekli kamera rig'inin yörünge/odak durumu (T-003 ölçüt 1). SAF VERİ: düğüm, sahne ağacı ve simülasyon yok.
##
## Model: odak noktası (dünya metresi; x = doğu, z = güney, y = yükseklik) + uzaklık + yön (heading) + eğim (pitch).
## Kamera konumu = odak - ileri * uzaklık. Odak daima arazi yüzeyine oturtulur (`CameraMath.reseat`); y ayrı bir
## serbestlik derecesi DEĞİL, odak xz'sindeki zemin yüksekliğidir.
## Değerler GDScript `float` (64-bit) tutulur: Vector3 (32-bit) metro ölçeğinde (40 km) milimetre hassasiyeti kaybeder,
## bu yüzden odak üç ayrı `float` olarak saklanır; 32-bit'e yalnız origin'e göre küçültülmüş göreli değerler iner
## (origin rebasing, ADR-0002 §2).
## Yön: 0 = kuzey (-z), 90 = doğu (+x); artış = sağa (saat yönü, yukarıdan bakışta). Eğim: 90 = tam yukarıdan.

var focus_x: float = 0.0
var focus_y: float = 0.0
var focus_z: float = 0.0
var heading_deg: float = 0.0
var pitch_deg: float = 50.0
var distance: float = 40000.0
## Dikey görüş açısı (derece; Camera3D `KEEP_HEIGHT`).
var fov_deg: float = 40.0


func copy() -> CameraState:
	var c := CameraState.new()
	c.focus_x = focus_x
	c.focus_y = focus_y
	c.focus_z = focus_z
	c.heading_deg = heading_deg
	c.pitch_deg = pitch_deg
	c.distance = distance
	c.fov_deg = fov_deg
	return c


## Bilgi amaçlı 32-bit görünüm (hassasiyet kaybı olabilir; hesapta kullanma).
func focus_xz() -> Vector2:
	return Vector2(focus_x, focus_z)


## Tüm alanlar sonlu ve uzaklık/görüş açısı pozitif mi (NaN/inf yayılmasın).
func is_valid() -> bool:
	for v in [focus_x, focus_y, focus_z, heading_deg, pitch_deg, distance, fov_deg]:
		if not is_finite(v):
			return false
	return distance > 0.0 and fov_deg > 0.0 and fov_deg < 170.0


## Yumuşatma: bu durumu `target`a doğru `alpha` (0..1) oranında yaklaştırır. Odak ve uzaklık DOĞRUSAL ilerler
## (kamera konumu doğrusal gider: tek zoom adımında imleç altındaki nokta yumuşatma boyunca da yerinde kalır);
## yön en kısa yoldan.
func approach(target: CameraState, alpha: float) -> void:
	var a := clampf(alpha, 0.0, 1.0)
	focus_x = lerpf(focus_x, target.focus_x, a)
	focus_y = lerpf(focus_y, target.focus_y, a)
	focus_z = lerpf(focus_z, target.focus_z, a)
	distance = lerpf(distance, target.distance, a)
	pitch_deg = lerpf(pitch_deg, target.pitch_deg, a)
	fov_deg = lerpf(fov_deg, target.fov_deg, a)
	heading_deg = wrapf(heading_deg + angle_delta_deg(heading_deg, target.heading_deg) * a, 0.0, 360.0)


## `to - from` en kısa yönde (-180..180).
static func angle_delta_deg(from_deg: float, to_deg: float) -> float:
	return wrapf(to_deg - from_deg, -180.0, 180.0)


## Eşiklerle yaklaşık eşitlik (test/yumuşatma bitişi): konum metre, açı derece, uzaklık oransal.
func is_close_to(other: CameraState, pos_eps_m: float = 0.01, angle_eps_deg: float = 0.01) -> bool:
	return absf(focus_x - other.focus_x) <= pos_eps_m and absf(focus_z - other.focus_z) <= pos_eps_m \
			and absf(focus_y - other.focus_y) <= pos_eps_m \
			and absf(angle_delta_deg(heading_deg, other.heading_deg)) <= angle_eps_deg \
			and absf(pitch_deg - other.pitch_deg) <= angle_eps_deg \
			and absf(distance - other.distance) <= maxf(pos_eps_m, distance * 1.0e-6)


func to_dict() -> Dictionary:
	return {
		"focus": [focus_x, focus_y, focus_z], "heading_deg": heading_deg, "pitch_deg": pitch_deg,
		"distance": distance, "fov_deg": fov_deg,
	}
