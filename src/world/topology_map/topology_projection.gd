class_name TopologyProjection
extends RefCounted
## Dünya metresi <-> harita pikseli izdüşümü (T-028). Düzgün (tek) ölçek; kuzey = -z (TEKNİK eksen sözleşmesi, kanon
## değil, WorldData) ekranda YUKARI. Saf: Node/Time/OS yok.

## Dünya kuzeyi (WorldData sözleşmesi: x doğu, z güney, kuzey = -z).
const NORTH := Vector2(0.0, -1.0)

## Gösterilen dünya dikdörtgeni (m) ve ekranda ona karşılık gelen dikdörtgen (px).
var world_rect: Rect2 = Rect2()
var screen_rect: Rect2 = Rect2()
## Piksel / metre (x ve y için aynı).
var px_per_m: float = 1.0


## `world_rect`i `target` içine en-boy oranı korunarak sığdırır ve ortalar.
static func fit(p_world_rect: Rect2, target: Rect2) -> TopologyProjection:
	var p := TopologyProjection.new()
	p.world_rect = p_world_rect
	p.px_per_m = minf(target.size.x / p_world_rect.size.x, target.size.y / p_world_rect.size.y)
	var size := p_world_rect.size * p.px_per_m
	p.screen_rect = Rect2(target.position + (target.size - size) * 0.5, size)
	return p


func to_screen(world_pos: Vector2) -> Vector2:
	return screen_rect.position + (world_pos - world_rect.position) * px_per_m


func to_world(screen_pos: Vector2) -> Vector2:
	return world_rect.position + (screen_pos - screen_rect.position) / px_per_m


func rect_to_screen(rect: Rect2) -> Rect2:
	return Rect2(to_screen(rect.position), rect.size * px_per_m)


func meters_per_pixel() -> float:
	return 1.0 / px_per_m


## Dünya kuzeyinin ekrandaki birim yönü (beklenen: yukarı = (0, -1)).
func north_on_screen() -> Vector2:
	var o := Vector2(world_rect.position + world_rect.size * 0.5)
	return (to_screen(o + NORTH * 100.0) - to_screen(o)).normalized()


## `max_px` pikseli aşmayan "yuvarlak" (1/2/5 x 10^k m) ölçek çubuğu: {"meters", "pixels"}.
func scale_bar(max_px: float) -> Dictionary:
	var meters := nice_length_m(max_px * meters_per_pixel())
	return {"meters": meters, "pixels": meters * px_per_m}


## `max_m`i aşmayan en büyük 1/2/5 x 10^k (m).
static func nice_length_m(max_m: float) -> float:
	if max_m <= 0.0:
		return 0.0
	var mag := pow(10.0, floorf(log(max_m) / log(10.0)))
	for mult in [5.0, 2.0, 1.0]:
		if mult * mag <= max_m * (1.0 + 1.0e-9):
			return mult * mag
	return mag
