class_name CameraTestSupport
extends RefCounted
## tests/view kamera testlerinin ortak yardımcıları (test paketi değildir): sentetik zeminler ve durum üretimi.

const VIEWPORT := Vector2(1600.0, 900.0)
const PIXELS: Array[Vector2] = [
	Vector2(800.0, 450.0), Vector2(200.0, 150.0), Vector2(1400.0, 200.0), Vector2(300.0, 800.0), Vector2(1500.0, 850.0),
]


static func flat(_x: float, _z: float) -> float:
	return 0.0


## Yumuşak tepeli sentetik zemin (m): sürekli, eğim ~20 dereceyi geçmez.
static func hills(x: float, z: float) -> float:
	return 40.0 * sin(x / 350.0) * cos(z / 410.0) + 15.0 * sin((x + z) / 120.0) + 60.0


static func make_state(ground: Callable, focus_x := 1000.0, focus_z := -500.0, distance := 800.0, pitch := 45.0,
		heading := 30.0) -> CameraState:
	var s := CameraState.new()
	s.focus_x = focus_x
	s.focus_z = focus_z
	s.distance = distance
	s.pitch_deg = pitch
	s.heading_deg = heading
	return CameraMath.reseat(s, ground)


## px ekran noktasının altındaki zemin noktası {ok, x, y, z}.
static func under(s: CameraState, px: Vector2, ground: Callable) -> Dictionary:
	return CameraMath.grab_point(s, px, VIEWPORT, ground)


## İki `under()` sonucu arasındaki 3B uzaklık (m).
static func gap(a: Dictionary, b: Dictionary) -> float:
	return Vector3(b["x"] - a["x"], b["y"] - a["y"], b["z"] - a["z"]).length()
