class_name WorldRoadEdge
extends RefCounted
## Yol ağı kenarı: iki düğüm arası düz parça. Sınıf, genişlik, açık/kapalı (T-011, CAN-04). Saf veri.
## Eğri yollar ara düğümlerle temsil edilir (kenar başına tek doğru parça).

const CLASS_ARTERIAL := &"arterial"
const CLASS_COLLECTOR := &"collector"
const CLASS_LOCAL := &"local"
const CLASS_FIELD := &"field"
const CLASS_RAIL := &"rail"
const CLASS_FERRY := &"ferry"
## Bina cephesi alabilen kara yolu sınıfları (ray ve feribot cephe vermez).
const ROAD_CLASSES: Array[StringName] = [CLASS_ARTERIAL, CLASS_COLLECTOR, CLASS_LOCAL, CLASS_FIELD]
const ALL_CLASSES: Array[StringName] = [CLASS_ARTERIAL, CLASS_COLLECTOR, CLASS_LOCAL, CLASS_FIELD, CLASS_RAIL,
		CLASS_FERRY]
## Katman: 0 = taban (tohum + kontrol verisinden üretilir), 1 = delta (oyuncu çizimi, CAN-04).
const LAYER_BASE := 0
const LAYER_DELTA := 1

var id: int = 0
var a: int = 0
var b: int = 0
var road_class: StringName = CLASS_LOCAL
var width: float = 10.0
var open: bool = true
var layer: int = LAYER_BASE
## Önbellek: uç düğümlerden hesaplanır (WorldNetwork yazar).
var length: float = 0.0


## Hat yürütme kipi: &"road" | &"rail" | &"ferry".
func mode() -> StringName:
	return mode_of(road_class)


func other(node_id: int) -> int:
	return b if node_id == a else a


func state_row() -> Array:
	return [id, a, b, String(road_class), width, open, layer]


static func mode_of(cls: StringName) -> StringName:
	if cls == CLASS_RAIL:
		return &"rail"
	if cls == CLASS_FERRY:
		return &"ferry"
	return &"road"


## Sınıf önceliği (yükseltme için): büyük = daha üst sınıf. Ray/feribot kendi kipinde yükseltilmez.
static func rank(cls: StringName) -> int:
	match cls:
		CLASS_ARTERIAL:
			return 3
		CLASS_COLLECTOR:
			return 2
		CLASS_LOCAL:
			return 1
		_:
			return 0


static func is_road_class(cls: StringName) -> bool:
	return ROAD_CLASSES.has(cls)
