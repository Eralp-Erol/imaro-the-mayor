extends GdUnitTestSuite
## T-062 A1 / ADR-0006 §3.4 kabul 2 · Reddedilmiş (approved olmayan) kit kimliklerine ve kit GLB ağacına SABİT
## referans taraması: src/, scenes/, data/ (data/library/ hariç: katalog ve oyun tabloları kimlikleri zaten listeler)
## ve assets/kit/.
## YENİ referans eklenemez: her (dosya, belirteç) çifti aşağıdaki "bilinen kalan referans" listesinde olmalı.
## Liste AŞAĞI doğru küçülür: bir referans kaldırıldığında girdi de silinmeli (bayat girdi testi düşürür).
## A2 (settlement.json, dünya yükleyicileri) ve A3 (görünüm: BuildingKit/BuildingView/playable/world_preview/placer,
## `DevBuildingSource` kaldırıldı) sonrası ÜRETİM kodunda (src/, scenes/game, data/) referans YOKTUR: bunu
## `test_production_roots_have_no_known_remaining_entries` ayrıca zorlar. Kalanlar YALNIZ eski (REDDEDİLMİŞ) kiti
## inceleyen araç dosyalarıdır (ADR-0006 §3.4 kabul 2: "izinli liste: kit_lab ve tools"):
## kit_lab/kit_validator/KitLibrary,
## hepsi bu kitin kimliklerine/yoluna doğası gereği bağlıdır; reddedilmiş kit dosyaları silinene (ADR §8.6 ayrı temizlik
## görevi) kadar listede kalırlar.

const ROOTS := ["res://src", "res://scenes", "res://data", "res://assets/kit"]
const SKIP_DIRS := ["res://data/library"]
const TEXT_EXTENSIONS := ["gd", "json", "tscn", "tres", "gdshader"]
## Reddedilmiş kit modüllerinin GLB ağacı (kit_manifest.json burada): yol referansı da bağımlılıktır.
const KIT_PATH_TOKEN := "assets/models/buildings/"

## BİLİNEN KALAN REFERANSLAR (dosya -> belirteçler): yalnız eski-kit araçları (yukarı bak). YENİ girdi eklemek için
## gerekçe
## gerekir; üretim kökleri (PRODUCTION_PREFIXES) altında girdi OLAMAZ.
const KNOWN_REMAINING := {
	"res://assets/kit/kit_library.gd": ["assets/models/buildings/"],
	"res://assets/kit/kit_validator.gd": ["prop_chimney", "prop_human", "veh_car"],
	"res://scenes/dev/kit_lab.gd": [
		"bld_civ_hall_a", "bld_ind_heritage_a", "bld_ind_shed_a", "bld_lmk_clocktower", "bld_res_house_a",
		"bld_res_late_a", "bld_res_late_a_gf", "bld_res_mid_a", "bld_res_mid_a_gf", "bld_res_old_a",
		"bld_res_old_a_gf", "prop_chimney", "prop_human", "veh_car",
	],
	"res://scenes/dev/kit_lab_layout.gd": [
		"bld_civ_hall_b", "bld_ind_heritage_b", "bld_ind_shed_b", "bld_lmk_clocktower", "bld_res_old_c",
		"bld_res_old_c_gf", "prop_human", "veh_car",
	],
	"res://scenes/dev/kit_lab_metrics.gd": ["bld_lmk_clocktower"],
}
## Üretim (oyun/çalışma zamanı) kodu ve verisi: burada reddedilmiş kit referansı HİÇ olamaz.
const PRODUCTION_PREFIXES := ["res://src/", "res://scenes/game/", "res://data/"]


## Katalogdaki approved OLMAYAN kimlikler (rejected/proposed; sıralı).
static func non_approved_ids() -> PackedStringArray:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/library/catalog.json"))
	var ids := PackedStringArray()
	for entry in (catalog as Dictionary)["entries"] as Array:
		if str((entry as Dictionary)["approval"]) != "approved":
			ids.append(str((entry as Dictionary)["id"]))
	ids.sort()
	return ids


## `text` içindeki belirteçler: tam-kimlik eşleşmesi (bitişik kimlik karakteri OLMAYAN) + kit yol belirteci.
## Sıralı, tekil.
static func find_tokens(text: String, ids: PackedStringArray) -> PackedStringArray:
	var found: Dictionary = {}
	var longest_first: Array = Array(ids)
	longest_first.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var regex := RegEx.new()
	var parts: Array[String] = []
	for id in longest_first:
		parts.append(String(id))
	regex.compile("(?<![A-Za-z0-9_])(" + "|".join(parts) + ")(?![A-Za-z0-9_])")
	for m in regex.search_all(text):
		found[m.get_string(1)] = true
	if text.contains(KIT_PATH_TOKEN):
		found[KIT_PATH_TOKEN] = true
	var out := PackedStringArray(found.keys())
	out.sort()
	return out


static func scan_files() -> Dictionary:
	var ids := non_approved_ids()
	var hits: Dictionary = {}
	for root in ROOTS:
		for path in _text_files(root):
			var tokens := find_tokens(FileAccess.get_file_as_string(path), ids)
			if not tokens.is_empty():
				hits[path] = tokens
	return hits


static func _text_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if SKIP_DIRS.has(dir_path):
		return out
	for sub in DirAccess.get_directories_at(dir_path):
		out.append_array(_text_files(dir_path.path_join(sub)))
	for file in DirAccess.get_files_at(dir_path):
		if TEXT_EXTENSIONS.has(file.get_extension()):
			out.append(dir_path.path_join(file))
	return out


func test_no_new_rejected_reference_outside_the_known_remaining_list() -> void:
	var hits := scan_files()
	var new_refs: Array[String] = []
	for path in hits:
		var allowed: Array = KNOWN_REMAINING.get(path, [])
		for token in hits[path] as PackedStringArray:
			if not allowed.has(token):
				new_refs.append("%s -> %s" % [path, token])
	new_refs.sort()
	assert_array(new_refs).override_failure_message(
		"YENİ rejected kit referansı (CAN/ADR-0006 kabul 2): %s" % str(new_refs)
	).is_empty()


func test_known_remaining_list_has_no_stale_entries() -> void:
	var hits := scan_files()
	var stale: Array[String] = []
	for path in KNOWN_REMAINING:
		var present: PackedStringArray = hits.get(path, PackedStringArray())
		for token in KNOWN_REMAINING[path] as Array:
			if not present.has(String(token)):
				stale.append("%s -> %s" % [path, token])
	stale.sort()
	assert_array(stale).override_failure_message(
		"referans kaldırıldı; KNOWN_REMAINING'den de sil: %s" % str(stale)
	).is_empty()


func test_production_roots_have_no_known_remaining_entries() -> void:
	var leaked: Array[String] = []
	for path in KNOWN_REMAINING:
		for prefix in PRODUCTION_PREFIXES:
			if String(path).begins_with(prefix):
				leaked.append(String(path))
	assert_array(leaked).override_failure_message(
		"üretim kodunda rejected kit referansı bırakılamaz (ADR-0006 kabul 2): %s" % str(leaked)
	).is_empty()
	# Taramanın kendisi de aynısını görür: üretim kökündeki HER dosya temiz.
	var hits := scan_files()
	var found: Array[String] = []
	for path in hits:
		for prefix in PRODUCTION_PREFIXES:
			if String(path).begins_with(prefix):
				found.append("%s -> %s" % [path, str(hits[path])])
	assert_array(found).override_failure_message("üretim kökünde rejected kit referansı: %s" % str(found)).is_empty()


func test_scanner_detects_a_planted_rejected_reference_and_ignores_lookalikes() -> void:
	var ids := non_approved_ids()
	assert_int(ids.size()).is_equal(45)   # D-005: 45 rejected; proposed da kapsanır
	assert_array(Array(find_tokens('var m := "bld_res_mid_a"', ids))).contains_exactly(["bld_res_mid_a"])
	assert_array(Array(find_tokens("veh_car,prop_human", ids))).contains_exactly(["prop_human", "veh_car"])
	assert_array(Array(find_tokens('"bld_res_mid_a_gf"', ids))).contains_exactly(["bld_res_mid_a_gf"])
	assert_array(Array(find_tokens('load("res://assets/models/buildings/x.glb")', ids))).contains_exactly([KIT_PATH_TOKEN])
	# Yan şeyler: onaylı hero kimliği, bitişik kimlik karakteri, ek.
	assert_array(Array(find_tokens("bld_hero_civ_hero_a xbld_res_mid_a bld_res_mid_ab", ids))).is_empty()
