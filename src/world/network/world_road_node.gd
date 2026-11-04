class_name WorldRoadNode
extends RefCounted
## Yol ağı düğümü (kavşak, uç, istasyon, iskele). Saf veri (T-011, WLD-01); konum dünya metresi (x doğu, y güney).

## Düğüm türleri (serbest genişler): boş = sıradan kavşak/uç.
const KIND_JUNCTION := &""
const KIND_REGION_HUB := &"region_hub"
const KIND_PORT := &"port"
const KIND_STATION := &"station"
const KIND_PIER := &"pier"

var id: int = 0
var pos: Vector2 = Vector2.ZERO
var kind: StringName = KIND_JUNCTION


func state_row() -> Array:
	return [id, pos.x, pos.y, String(kind)]
