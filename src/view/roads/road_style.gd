class_name RoadStyle
extends RefCounted
## Geçici sanat ayarları yalnız JSON'da. Genişlik: ağ genişliği x veri katsayısı;
## parsel cephesi için kullanılan gerçek yol koridorunu varsayılan ayarlar korur.

const PATH := "res://data/view/road_style.json"

var data: Dictionary


static func load_default() -> RoadStyle:
	var style := RoadStyle.new()
	style.data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return style


func width_of(edge: WorldRoadEdge, metro: bool = false) -> float:
	var entry: Dictionary = data["classes"][String(edge.road_class)]
	return edge.width * float(entry["width_scale"]) * (float(data["metro_width_scale"]) if metro else 1.0)


func color_of(edge: WorldRoadEdge) -> Color:
	return Color.html(str(data["classes"][String(edge.road_class)]["color"]))
