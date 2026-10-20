class_name WorldControlData
extends RefCounted
## Elle düzenlenebilir dünya kontrol verisi (data/world/<id>/*.json) yükleyici + şema doğrulaması (T-001, WLD-02).
## JSON'da yorum olmadığı için her dosyada `_header` (kanon dayanağı) ve serbest `_notes`/`basis` alanları vardır.
## Koordinatlar KİLİTLİ DEĞİLDİR (F02, F04); bu veri yalnız yön yorumudur ve serbestçe düzenlenir.

const FILES: Array[String] = ["world", "coast", "regions", "sites", "terrain"]
## Her veri dosyasının başlığında bulunması gereken kanon ibaresi (T-001 ölçüt 1).
const HEADER_PHRASE := "ONAYLANMIŞ YÖN"
const HEADER_SOURCE := "02_ismeral_t0_vs_mature_SELECTED.jpg"
const REGION_CODES: Array[String] = ["D1", "D2", "D3", "D4", "D5", "D6"]
## Yalnız D2 ad taşır (CAN-01).
const ONLY_NAMED_REGION := "D2"
const ONLY_NAME := "Orven"


## `dir` altındaki dosyaları yükler → {"world": {...}, "coast": {...}, ...}. Okunamayan dosyada push_error + boş sözlük.
static func load_dir(dir: String) -> Dictionary:
	var control := {}
	for file_name in FILES:
		var path := "%s/%s.json" % [dir, file_name]
		if not FileAccess.file_exists(path):
			push_error("WorldControlData: dosya yok: %s" % path)
			return {}
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			push_error("WorldControlData: geçersiz JSON: %s" % path)
			return {}
		control[file_name] = parsed
	return control


## Şema/kanon sağlığı: hata metinleri listesi (boş = geçerli). Üretimden önce çağrılır; testler de kullanır.
static func validate(control: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for file_name in FILES:
		if not control.has(file_name):
			errors.append("eksik dosya: %s" % file_name)
			continue
		var header := str((control[file_name] as Dictionary).get("_header", ""))
		if not (header.contains(HEADER_PHRASE) and header.contains(HEADER_SOURCE)):
			errors.append("%s: _header kanon ibaresini (%s, %s) içermiyor" % [file_name, HEADER_PHRASE, HEADER_SOURCE])
	if not errors.is_empty():
		return errors
	var regions: Array = (control["regions"] as Dictionary).get("regions", [])
	var seen := {}
	for r: Dictionary in regions:
		var code := str(r.get("code", ""))
		seen[code] = true
		var display := str(r.get("name", ""))
		if code != ONLY_NAMED_REGION and not display.is_empty():
			errors.append("bölge %s ad taşıyor ('%s'); yalnız %s adlıdır (CAN-01)" % [code, display, ONLY_NAMED_REGION])
		if code == ONLY_NAMED_REGION and display != ONLY_NAME:
			errors.append("bölge %s adı '%s' olmalı (CAN-01)" % [code, ONLY_NAME])
	for code in REGION_CODES:
		if not seen.has(code):
			errors.append("bölge %s tanımlı değil (WLD-02)" % code)
	errors.append_array(_validate_terraces(control, seen))
	var coast: Dictionary = control["coast"]
	if (coast.get("mainland", {}) as Dictionary).get("coast_path_km", []).size() < 4:
		errors.append("coast.mainland.coast_path_km en az 4 kontrol noktası içermeli")
	return errors


## terrain.settlement_terraces şeması: kimlik, pozitif yarıçap, bilinen bölge VEYA mutlak merkez, makul eğim/sönüm.
static func _validate_terraces(control: Dictionary, region_codes: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	for t: Dictionary in (control["terrain"] as Dictionary).get("settlement_terraces", []):
		var tag := "settlement_terraces '%s'" % str(t.get("id", "?"))
		var id := str(t.get("id", ""))
		if id.is_empty() or ids.has(id):
			errors.append("%s: kimlik boş veya yinelenen" % tag)
		ids[id] = true
		var rad: Variant = t.get("radius_km", [])
		if not (rad is Array) or (rad as Array).size() != 2 or float(rad[0]) <= 0.0 or float(rad[1]) <= 0.0:
			errors.append("%s: radius_km iki pozitif sayı olmalı" % tag)
		var region := str(t.get("region", ""))
		if not region.is_empty() and not region_codes.has(region):
			errors.append("%s: bilinmeyen bölge '%s'" % [tag, region])
		if region.is_empty() and not t.has("center_km"):
			errors.append("%s: region + offset_norm veya center_km gerekli" % tag)
		var slope := float(t.get("slope_deg", 5.0))
		if slope <= 0.0 or slope >= 45.0:
			errors.append("%s: slope_deg (0, 45) aralığında olmalı" % tag)
		if float(t.get("falloff", 1.2)) < 0.0 or float(t.get("detail_falloff", 0.0)) < 0.0:
			errors.append("%s: falloff negatif olamaz" % tag)
	return errors
