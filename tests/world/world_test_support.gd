class_name WorldTestSupport
extends RefCounted
## tests/world ortak yardımcıları (test paketi değildir). Kontrol verisini bir kez okur, her çağrıda derin kopya verir;
## bozulmuş (olumsuz) varyantlar bellekte üretilir, dosyalara yazılmaz.

const DATA_DIR := "res://data/world/ismeral"
## Hızlı testler için kaba hücre boyutları (veri varsayılanı 100 m); topoloji bu çözünürlüklerde de aynıdır.
const COARSE_CELL_M := 400.0
const MEDIUM_CELL_M := 250.0
const DEFAULT_SEED := 1467

static var _control_cache: Dictionary = {}
static var _default_world: WorldData = null


## Veri dosyalarından kontrol verisinin DERİN KOPYASI (çağıran serbestçe bozabilir).
static func control() -> Dictionary:
	if _control_cache.is_empty():
		_control_cache = WorldControlData.load_dir(DATA_DIR)
	return _control_cache.duplicate(true)


## Veri dosyasındaki varsayılan çözünürlük + varsayılan tohumla dünya; süreç başına bir kez üretilir.
## SALT OKUNUR kullanın.
static func default_world() -> WorldData:
	if _default_world == null:
		_default_world = WorldGenerator.generate(control(), DEFAULT_SEED)
	return _default_world


static func medium(control_data: Dictionary, world_seed: int = DEFAULT_SEED) -> WorldData:
	return WorldGenerator.generate(control_data, world_seed, {"cell_size_m": MEDIUM_CELL_M})


static func coarse(control_data: Dictionary, world_seed: int = DEFAULT_SEED) -> WorldData:
	return WorldGenerator.generate(control_data, world_seed, {"cell_size_m": COARSE_CELL_M})


## `control_data["regions"]["regions"]` içinden kodla bölge girdisi (referans; değiştirmek veriyi bozar).
static func region_entry(control_data: Dictionary, code: String) -> Dictionary:
	for entry: Dictionary in control_data["regions"]["regions"]:
		if entry["code"] == code:
			return entry
	return {}


static func island_entry(control_data: Dictionary, island_id: String) -> Dictionary:
	for entry: Dictionary in control_data["coast"]["islands"]:
		if entry["id"] == island_id:
			return entry
	return {}


static func site_entry(control_data: Dictionary, site_id: String) -> Dictionary:
	for entry: Dictionary in control_data["sites"]["sites"]:
		if entry["id"] == site_id:
			return entry
	return {}


## Tüm kıyı verisini doğu-batı aynalar (körfez doğuya açılır): bilerek bozulmuş coğrafya.
static func mirror_coast_x(control_data: Dictionary) -> void:
	var mainland: Dictionary = control_data["coast"]["mainland"]
	var width_km: float = control_data["world"]["size_km"][0]
	for key in ["coast_path_km", "closure_km"]:
		for p: Array in mainland[key]:
			p[0] = width_km - float(p[0])
	for island: Dictionary in control_data["coast"]["islands"]:
		for p: Array in island["outline_km"]:
			p[0] = width_km - float(p[0])


## Körfezi yok eden düz batı kıyısı (doldurma/düzleştirme): bilerek bozulmuş coğrafya (WLD-05 ters senaryo).
static func straighten_coast(control_data: Dictionary) -> void:
	control_data["coast"]["mainland"]["coast_path_km"] = [[14.0, -1.0], [12.0, 10.0], [12.5, 20.0], [16.0, 42.0]]


## Ağzı ana karaya bağlayan kara barajı ekler: körfez kapalı göle döner.
static func seal_bay_mouth(control_data: Dictionary) -> void:
	var barrier := {
		"id": "TEST_BARRIER", "peak_m": 5, "t0_tags": [],
		"outline_km": [[10.5, 13.5], [12.0, 13.5], [13.5, 13.5], [13.5, 21.0], [13.5, 29.5], [12.0, 29.5],
			[10.5, 29.5], [10.5, 21.0]],
	}
	(control_data["coast"]["islands"] as Array).append(barrier)


## Kaynak dosyada yasak API var mı (TEK-01/02). Boş = temiz.
static func forbidden_api_hits(res_path: String) -> PackedStringArray:
	var text := FileAccess.get_file_as_string(res_path)
	var pattern := "(?<![\\w.])(randf|randi|randf_range|randi_range|randomize|shuffle)\\("
	pattern += "|\\bTime\\.|\\bOS\\.|get_tree|extends Node|Engine\\.get_frames"
	var rx := RegEx.create_from_string(pattern)
	var hits := PackedStringArray()
	for m in rx.search_all(text):
		hits.append(m.get_string())
	return hits
