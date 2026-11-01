class_name VegetationViewConfig
extends RefCounted
## Bitki görünümü ayarları (T-062 B1): `data/view/vegetation_view.json`. Görünüm profil ayarıdır (ADR-0004): simülasyon
## okumaz. Sayılar ÇALIŞMA MODELİ (T-057 Karar 5: eşikler ölçülmüş cihaz sonucu değil). Doğrulama hata metni döndürür;
## geçersiz dosya `errors` doldurur ve `valid()` false olur (çağıran görünümü kurmaz).

const PATH := "res://data/view/vegetation_view.json"
const SCHEMA_VERSION := 1
const SHAPE_SIDES_MIN := 3
const SHAPE_SIDES_MAX := 12

# tiers
var lod0_end_m: float = 120.0
var lod1_end_m: float = 400.0
var palm_proxy_end_m: float = 1500.0
# update
var step_m: float = 10.0
var load_margin_m: float = 40.0
var unload_margin_m: float = 140.0
var max_cells_built_per_update: int = 6
var max_instances_per_frame: int = 2500
# shadows
var shadow_lod0: bool = true
var shadow_lod1: bool = false
var shadow_proxy: bool = false
# ground
var sink_m: float = 0.12
# blob
var blob_enabled: bool = true
var blob_chunk_cells: int = 4
var blob_fade_begin_m: float = 1400.0
var blob_end_m: float = 2200.0
var blob_load_margin_m: float = 200.0
var blob_unload_margin_m: float = 700.0
var blob_max_chunks_per_frame: int = 2
## Biten leke parçalarının sahneye kurulumu (ArrayMesh + GPU yükleme) karede bu kadar ms'yi aşmaz (en az 1 parça).
## Ölçüm: kurulum ~0,2 ms / 1000 köşe; kamera hareketinden sonra 13 parça aynı karede biterse tek karede ~110 ms'ydi.
var blob_install_budget_ms: float = 2.0
var blob_clump_m: float = 32.0
var blob_radius_mult: float = 0.95
var blob_max_clump_radius_m: float = 15.0
var blob_min_clump_radius_m: float = 2.5
var blob_sides: int = 6
var blob_sink_m: float = 0.4
var blob_value_jitter: float = 0.08
var blob_skip_species: PackedStringArray = PackedStringArray()
## Şekil adı -> Array[Vector2] (yarıçap oranı, taç yüksekliği oranı [0,1)); en sonda tepe noktası eklenir.
var blob_shapes: Dictionary = {}
## Tür anahtarı -> {shape, crown_base_frac, radius_frac}.
var species_look: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()


static func load_default() -> VegetationViewConfig:
	return load_path(PATH)


static func load_path(path: String) -> VegetationViewConfig:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(parsed as Dictionary if parsed is Dictionary else {})


static func from_dict(d: Dictionary) -> VegetationViewConfig:
	var c := VegetationViewConfig.new()
	if d.is_empty():
		c.errors.append("vegetation_view.json okunamadı/boş")
		return c
	if int(d.get("schema_version", 0)) != SCHEMA_VERSION:
		c.errors.append("schema_version != %d" % SCHEMA_VERSION)
	for section in ["tiers", "update", "shadows", "ground", "blob", "species_look"]:
		if not (d.get(section) is Dictionary):
			c.errors.append("bölüm yok: %s" % section)
	if not c.errors.is_empty():
		return c
	c._read_tiers(d["tiers"] as Dictionary)
	c._read_update(d["update"] as Dictionary)
	var sh: Dictionary = d["shadows"]
	c.shadow_lod0 = bool(sh.get("lod0", true))
	c.shadow_lod1 = bool(sh.get("lod1", false))
	c.shadow_proxy = bool(sh.get("proxy", false))
	c.sink_m = float((d["ground"] as Dictionary).get("sink_m", c.sink_m))
	c._read_blob(d["blob"] as Dictionary)
	c.species_look = (d["species_look"] as Dictionary).duplicate(true)
	c.errors.append_array(c.problems())
	return c


func valid() -> bool:
	return errors.is_empty()


## Tür anahtarı için görünüm kaydı; yoksa boş sözlük.
func look_of(species_key: String) -> Dictionary:
	return species_look.get(species_key, {})


## Tutarlılık hataları (boş = geçerli). Dosya değerleri `from_dict`ten sonra; testler alanları değiştirip çağırır.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if lod0_end_m <= 0.0 or lod1_end_m <= lod0_end_m:
		out.append("tiers: 0 < lod0_end_m < lod1_end_m olmalı")
	if palm_proxy_end_m < lod1_end_m:
		out.append("tiers: palm_proxy_end_m >= lod1_end_m olmalı")
	if step_m <= 0.0 or load_margin_m < 0.0 or unload_margin_m < load_margin_m:
		out.append("update: step_m > 0 ve 0 <= load_margin_m <= unload_margin_m olmalı")
	if max_cells_built_per_update < 1 or max_instances_per_frame < 1:
		out.append("update: kare tavanları >= 1 olmalı")
	if blob_enabled:
		if blob_fade_begin_m <= lod1_end_m or blob_end_m <= blob_fade_begin_m:
			out.append("blob: lod1_end_m < fade_begin_m < end_m olmalı")
		if blob_install_budget_ms <= 0.0:
			out.append("blob: install_budget_ms > 0 olmalı")
		if blob_chunk_cells < 1 or blob_chunk_cells > 16:
			out.append("blob: chunk_cells 1..16 olmalı")
		if blob_sides < SHAPE_SIDES_MIN or blob_sides > SHAPE_SIDES_MAX:
			out.append("blob: sides %d..%d olmalı" % [SHAPE_SIDES_MIN, SHAPE_SIDES_MAX])
		if blob_clump_m < 4.0 or blob_min_clump_radius_m <= 0.0 or blob_max_clump_radius_m < blob_min_clump_radius_m:
			out.append("blob: clump_m >= 4 ve 0 < min <= max_clump_radius_m olmalı")
		if blob_shapes.is_empty():
			out.append("blob: şekil yok")
		if blob_max_chunks_per_frame < 1 or blob_unload_margin_m < blob_load_margin_m:
			out.append("blob: kare tavanı >= 1 ve load_margin_m <= unload_margin_m olmalı")
	for key: String in species_look:
		var look: Dictionary = species_look[key]
		if blob_enabled and not blob_shapes.has(str(look.get("shape", ""))):
			out.append("species_look.%s: bilinmeyen şekil '%s'" % [key, str(look.get("shape", ""))])
		if float(look.get("radius_frac", 0.0)) <= 0.0:
			out.append("species_look.%s: radius_frac > 0 olmalı" % key)
		var base := float(look.get("crown_base_frac", -1.0))
		if base < 0.0 or base >= 1.0:
			out.append("species_look.%s: crown_base_frac [0,1) olmalı" % key)
	return out


func _read_tiers(t: Dictionary) -> void:
	lod0_end_m = float(t.get("lod0_end_m", lod0_end_m))
	lod1_end_m = float(t.get("lod1_end_m", lod1_end_m))
	palm_proxy_end_m = float(t.get("palm_proxy_end_m", palm_proxy_end_m))


func _read_update(u: Dictionary) -> void:
	step_m = float(u.get("step_m", step_m))
	load_margin_m = float(u.get("load_margin_m", load_margin_m))
	unload_margin_m = float(u.get("unload_margin_m", unload_margin_m))
	max_cells_built_per_update = int(u.get("max_cells_built_per_update", max_cells_built_per_update))
	max_instances_per_frame = int(u.get("max_instances_per_frame", max_instances_per_frame))


func _read_blob(b: Dictionary) -> void:
	blob_enabled = bool(b.get("enabled", true))
	blob_chunk_cells = int(b.get("chunk_cells", blob_chunk_cells))
	blob_fade_begin_m = float(b.get("fade_begin_m", blob_fade_begin_m))
	blob_end_m = float(b.get("end_m", blob_end_m))
	blob_load_margin_m = float(b.get("load_margin_m", blob_load_margin_m))
	blob_unload_margin_m = float(b.get("unload_margin_m", blob_unload_margin_m))
	blob_max_chunks_per_frame = int(b.get("max_chunks_built_per_frame", blob_max_chunks_per_frame))
	blob_install_budget_ms = float(b.get("install_budget_ms", blob_install_budget_ms))
	blob_clump_m = float(b.get("clump_m", blob_clump_m))
	blob_radius_mult = float(b.get("radius_mult", blob_radius_mult))
	blob_max_clump_radius_m = float(b.get("max_clump_radius_m", blob_max_clump_radius_m))
	blob_min_clump_radius_m = float(b.get("min_clump_radius_m", blob_min_clump_radius_m))
	blob_sides = int(b.get("sides", blob_sides))
	blob_sink_m = float(b.get("sink_m", blob_sink_m))
	blob_value_jitter = float(b.get("value_jitter", blob_value_jitter))
	blob_skip_species = PackedStringArray()
	for s in b.get("skip_species", []):
		blob_skip_species.append(str(s))
	blob_shapes = {}
	var shapes: Dictionary = b.get("shapes", {})
	for name: String in shapes:
		var rings: Array[Vector2] = []
		for r in (shapes[name] as Dictionary).get("rings", []):
			var pair: Array = r
			rings.append(Vector2(float(pair[0]), float(pair[1])))
		blob_shapes[name] = rings
