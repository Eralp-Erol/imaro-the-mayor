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


## Verideki İLK ada (ada sayısı/kimlikleri kilitli değil: testler "I5" gibi kimliğe bağlanmaz). Ada yoksa boş sözlük.
static func first_island_entry(control_data: Dictionary) -> Dictionary:
	var islands: Array = control_data["coast"]["islands"]
	return {} if islands.is_empty() else islands[0]


## Ada dış hat noktalarının ortalaması (km) — küçük, dışbükeye yakın adalarda adanın içinde bir nokta.
static func outline_center_km(island: Dictionary) -> Vector2:
	var center := Vector2.ZERO
	for p: Array in island["outline_km"]:
		center += Vector2(float(p[0]), float(p[1]))
	return center / float((island["outline_km"] as Array).size())


## İki nokta (km) arasında `half_width_km` yarı genişlikte, köşeleri ve kenar ortaları verilen şerit çokgeni (dış hat).
static func strip_outline_km(a: Vector2, b: Vector2, half_width_km: float) -> Array:
	var dir := (b - a).normalized()
	var normal := Vector2(-dir.y, dir.x) * half_width_km
	var corners: Array[Vector2] = [a + normal, a - normal, b - normal, b + normal]
	var out: Array = []
	for k in corners.size():
		var c := corners[k]
		var nxt := corners[(k + 1) % corners.size()]
		out.append([c.x, c.y])
		out.append([(c.x + nxt.x) * 0.5, (c.y + nxt.y) * 0.5])
	return out


## Bölgenin dünya ağırlık merkezi (km) — veriden türetilmiş, sabit koordinat değil.
static func region_centroid_km(world: WorldData, code: StringName) -> Vector2:
	return world.region_by_code(code).centroid / 1000.0


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
## Kıyı yolunun İLK ve SON noktası korunur; aradaki körfez/koy düz çizgiyle kesilir (sabit koordinat yok).
static func straighten_coast(control_data: Dictionary) -> void:
	var path: Array = control_data["coast"]["mainland"]["coast_path_km"]
	var a := Vector2(float(path[0][0]), float(path[0][1]))
	var b := Vector2(float(path[path.size() - 1][0]), float(path[path.size() - 1][1]))
	var line: Array = []
	for t in [0.0, 0.33, 0.66, 1.0]:
		var p := a.lerp(b, t)
		line.append([p.x, p.y])
	control_data["coast"]["mainland"]["coast_path_km"] = line


## Körfezin ağzını ana karaya bağlayan kara barajı ekler: körfez kapalı göle döner. Ağzın yeri VERİDEN türetilir:
## bozulmamış kontrol verisinden kaba dünya üretilir, körfez analizi ağız hücrelerinin sınır kutusunu verir; baraj bu
## kutuyu her iki uçta kıyıya bağlanacak kadar uzatır.
static func seal_bay_mouth(control_data: Dictionary) -> void:
	var baseline := coarse(control_data.duplicate(true))
	var mouth: Rect2 = WorldInvariants.analyze_bay(baseline)["mouth_bbox"]
	var lo := mouth.position / 1000.0 - Vector2(0.8, 3.0)
	var hi := mouth.end / 1000.0 + Vector2(0.8, 3.0)
	var mid := (lo + hi) * 0.5
	var barrier := {
		"id": "TEST_BARRIER", "peak_m": 5, "t0_tags": [],
		"outline_km": [[lo.x, lo.y], [mid.x, lo.y], [hi.x, lo.y], [hi.x, mid.y], [hi.x, hi.y], [mid.x, hi.y],
			[lo.x, hi.y], [lo.x, mid.y]],
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
