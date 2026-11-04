class_name WorldBlock
extends RefCounted
## Blok: yol/ray kenarlarının kapattığı yüzden türeyen kapalı poligon (T-011). `outline` = yüz (yol eksenleri),
## `buildable` = yarım yol genişliği kadar içe ötelenmiş inşa edilebilir alan. Saf veri.

## Tür: parcelized = parsellendi; open = çok büyük, yeşil kuşak/tarım açıklığı (parselsiz); sliver = ofset sonrası
## geçersiz/dar; holed = içinde bağlantısız ağ parçası var (parselsiz); unbuildable = su/ada/eğim.
const KIND_PARCELIZED := &"parcelized"
const KIND_OPEN := &"open"
const KIND_SLIVER := &"sliver"
const KIND_HOLED := &"holed"
const KIND_UNBUILDABLE := &"unbuildable"

var id: int = 0
var outline: PackedVector2Array = PackedVector2Array()
var buildable: PackedVector2Array = PackedVector2Array()
## outline'ın i -> i+1 kenarının yol kenarı kimliği.
var edge_ids: PackedInt32Array = PackedInt32Array()
var kind: StringName = KIND_SLIVER
var region_code: StringName = &""
## Parsel şablonu adı (örn. &"core", &"rural"); görünürlük/T-005 için ipucu.
var fabric: StringName = &""
var area: float = 0.0
var parcel_ids: PackedInt32Array = PackedInt32Array()
## Geometri imzası (blok kimliğini artımlı güncellemede korumak için).
var signature: String = ""


func state_row() -> Array:
	return [id, String(kind), String(region_code), String(fabric), area, signature]
