class_name RoadStyle
extends RefCounted
## Geçici sanat ayarları yalnız JSON'da. Genişlik: ağ genişliği x veri katsayısı;
## parsel cephesi için kullanılan gerçek yol koridorunu varsayılan ayarlar korur.
## T-062 A4: yüzey = onaylı zemin katmanı (asfalt new/worn; `LibraryGate` kimlikleri `GroundLayerSet` ile çözülür).
## Köşe rengi YÜZEY KODUDUR: R = katman indeksi x 16/255 (tam sayı, 8-bit güvenli), G = parlaklık / 2,
## B = kaldırım bandı (m) / 8 (0 = yok), A = 1. Kaldırım ek geometri değil: köşe UV'si (yanal ofset, yarım genişlik).
## Seçim (new/worn) kenar kimliği hash'iyle deterministik; mesh yapımı iş parçacığında olduğundan katman indeksleri
## ANA iş parçacığında `bind_layers` ile bir kez çözülür.

const PATH := "res://data/view/road_style.json"
const LAYER_CODE_STEP := 16.0 / 255.0
## Köşe rengi B kanalı: kaldırım genişliği (m) bu değere bölünerek kodlanır.
const WALK_CODE_M := 8.0

var data: Dictionary
## Sınıf -> [taban indeksi, eskimiş indeksi]; `bind_layers` doldurur (bağlanmadıysa 0).
var _layer_of_class: Dictionary = {}
var _walk_layer: int = 0


static func load_default() -> RoadStyle:
	var style := RoadStyle.new()
	style.data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return style


func width_of(edge: WorldRoadEdge, metro: bool = false) -> float:
	var entry: Dictionary = data["classes"][String(edge.road_class)]
	return edge.width * float(entry["width_scale"]) * (float(data["metro_width_scale"]) if metro else 1.0)


## Sınıf yüzey kimlikleri kümede (kapıdan geçmiş) değilse yüklenmez (kapı ret sayar) ve "surface.fallback" kullanılır.
func bind_layers(layers: GroundLayerSet) -> void:
	_layer_of_class.clear()
	var fallback := str(data["surface"].get("fallback", ""))
	_walk_layer = layers.resolve(str(data["surface"].get("sidewalk_layer", "")), fallback)
	for cls in data["classes"]:
		var surface: Dictionary = data["classes"][cls]["surface"]
		_layer_of_class[cls] = [layers.resolve(str(surface["base"]), fallback),
				layers.resolve(str(surface["worn"]), fallback)]


## Kaldırım katmanının dizi indeksi (`bind_layers` sonrası).
func walk_layer() -> int:
	return _walk_layer


## Kenarın yüzeyi eskimiş mi (kenar kimliği hash'i < sınıf payı). Saf ve deterministik.
func is_worn(edge: WorldRoadEdge) -> bool:
	var surface: Dictionary = data["classes"][String(edge.road_class)]["surface"]
	return ViewHash.hash01(edge.id, int(data["surface"]["seed"])) < float(surface["worn_share"])


## Kenarın katman indeksi (new/worn seçimi + bağlı katman tablosu).
func layer_of(edge: WorldRoadEdge) -> int:
	var pair: Array = _layer_of_class.get(String(edge.road_class), [0, 0])
	return int(pair[1 if is_worn(edge) else 0])


## Köşe rengi = yüzey kodu (bkz. başlık). `road_surface.gdshader` çözer.
func color_of(edge: WorldRoadEdge) -> Color:
	var brightness := float(data["classes"][String(edge.road_class)]["brightness"])
	var walk_m := float(data["classes"][String(edge.road_class)].get("sidewalk_m", 0.0))
	return Color(float(layer_of(edge)) * LAYER_CODE_STEP, clampf(brightness * 0.5, 0.0, 1.0),
			clampf(walk_m / WALK_CODE_M, 0.0, 1.0), 1.0)


## Köşe renginden katman indeksi (CPU aynası; gölgelendirici aynı işlemi yapar).
static func layer_from_color(color: Color) -> int:
	return int(roundf(color.r / LAYER_CODE_STEP))
