class_name GroundLayerSet
extends RefCounted
## Onaylı zemin dokuları -> tek `Texture2DArray` (T-062 A4, ADR-0006 §3.3). Katman kimliği YALNIZ `LibraryGate`'ten
## gelir: kapıdan geçen (`approved` + oyun tablosunda) zemin kayıtları `layer_index` sırasıyla diziye yüklenir; kapıdan
## geçmeyen kimlik (rejected/proposed/bilinmeyen) yüklenmez, `gate.unapproved_ids` sayacına yazılır ve çağırana
## yedek katman döner. Katalogda olmayan (laboratuvar/makro) zemin dokuları BURADAN yüklenemez.
## Arazi ve yol gölgelendiricileri AYNI diziyi paylaşır (VRAM tek kopya). Saf görünüm verisi: sim/dünya okunmaz.
## Ana iş parçacığında kurulmalı (Texture2DArray); aynı veri -> aynı dizi.

const TABLE_NAME := "ground"
## Dizinin istenen tam boyutu/biçimi: tüm katmanlar aynı olmalı (Texture2DArray kuralı).
const FORMAT := Image.FORMAT_RGBA8

static var _shared: GroundLayerSet = null

## Katman sırası = dizi indeksi (`layer_index` artan; eşitlikte kimlik sırası).
var layer_ids: PackedStringArray = PackedStringArray()
## Dizi indeksi -> doku başına dünya metresi (UV = dünya xz / tile_m).
var tile_m: PackedFloat32Array = PackedFloat32Array()
var array: Texture2DArray = null
## Yükleme hataları (eksik/uyumsuz dosya); boşsa küme sağlıklı.
var errors: PackedStringArray = PackedStringArray()
var gate: LibraryGate = null
var size_px: int = 0
var mip_levels: int = 0

var _index: Dictionary = {}


## Varsayılan kapı ile önbellekli küme. İş parçacıklarından ÖNCE ana iş parçacığında çağrılmalı.
static func shared() -> GroundLayerSet:
	if _shared == null:
		_shared = GroundLayerSet.build(LibraryGate.load_default())
	return _shared


static func clear_shared() -> void:
	_shared = null


## Kapıdaki tüm onaylı zemin katmanlarından dizi kurar. `load_images=false`: yalnız kimlik/tile tablosu (dizi yok).
static func build(source_gate: LibraryGate, load_images: bool = true) -> GroundLayerSet:
	var layers := GroundLayerSet.new()
	layers.gate = source_gate
	var order: Array[Dictionary] = []
	for id in source_gate.approved_ids_of(TABLE_NAME):
		var rec := source_gate.request(id)
		if rec.is_empty():
			continue
		order.append(rec)
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia := int(a.get("layer_index", 0))
		var ib := int(b.get("layer_index", 0))
		return ia < ib or (ia == ib and str(a["id"]) < str(b["id"])))
	var images: Array[Image] = []
	for rec in order:
		var id := str(rec["id"])
		var tile := float(rec.get("tile_m", 0.0))
		if tile <= 0.0:
			layers.errors.append("%s: tile_m yok/geçersiz" % id)
			continue
		layers._index[id] = layers.layer_ids.size()
		layers.layer_ids.append(id)
		layers.tile_m.append(tile)
		if load_images:
			var image := layers._load_image(source_gate, id)
			if image == null:
				continue
			images.append(image)
	if load_images and images.size() == layers.layer_ids.size() and not images.is_empty():
		layers.array = Texture2DArray.new()
		var err := layers.array.create_from_images(images)
		if err != OK:
			layers.errors.append("Texture2DArray.create_from_images hata %d" % err)
			layers.array = null
		else:
			layers.size_px = images[0].get_width()
			layers.mip_levels = images[0].get_mipmap_count() + 1
	return layers


func count() -> int:
	return layer_ids.size()


func has_layer(id: String) -> bool:
	return _index.has(id)


## Kimliğin dizi indeksi; kümede yoksa -1 (kapıya SORULMAZ).
func index_of(id: String) -> int:
	return int(_index.get(id, -1))


## Rol çözümü: `id` kümedeyse indeksi; değilse kapıdan istenir (ret kaydedilir: `gate.unapproved_ids`) ve `fallback_id`
## indeksi döner (o da yoksa 0). Onaysız kimlik ASLA yüklenmez.
func resolve(id: String, fallback_id: String = "") -> int:
	if _index.has(id):
		return int(_index[id])
	if gate != null:
		gate.request(id)
	return int(_index.get(fallback_id, 0))


func _load_image(source_gate: LibraryGate, id: String) -> Image:
	var paths := source_gate.request_paths(id)
	if paths.is_empty():
		errors.append("%s: kapıdan yol gelmedi" % id)
		return null
	var path := paths[0]
	var tex := load(path) as Texture2D
	if tex == null:
		errors.append("%s: doku yüklenemedi (%s)" % [id, path])
		return null
	var image := tex.get_image()
	if image == null or image.is_empty():
		errors.append("%s: görüntü okunamadı (%s)" % [id, path])
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != FORMAT:
		image.convert(FORMAT)
	if not image.has_mipmaps():
		image.generate_mipmaps()
	if size_px == 0:
		size_px = image.get_width()
	elif image.get_width() != size_px or image.get_height() != size_px:
		errors.append("%s: boyut %dx%d != %d" % [id, image.get_width(), image.get_height(), size_px])
		return null
	return image
