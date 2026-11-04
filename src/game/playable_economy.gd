class_name PlayableEconomy
extends RefCounted
## Oynanabilir sahnenin ekonomi BAŞLANGIÇ koşulları (T-040): varsayılan ekonomi yapılandırması + T0 stoğundan türeyen
## bölge başına altyapı kapasitesi ve gizli hane talebi (`data/game/playable_economy.json`). Karar kuralları DEĞİŞMEZ;
## yalnız `regions.overrides` verisi eklenir (sim lane'inin dosyası düzenlenmez). Sim bu sınıfı bilmez.

const PATH := "res://data/game/playable_economy.json"


## `views`: sim'e verilen parsel görünümleri (id -> bölge kodu). `stock`: T0 başlangıç stoğu. `patch`: türetilmiş
## yapılandırma üstüne derin birleştirilen yama (yalnız testler/deneyler; oynanabilir sahne vermez). `patch["playable"]`
## (varsa) ekonomi yapılandırmasına DEĞİL `playable_economy.json` ayarlarına uygulanır (ör. kontrol koşusu için
## `{"playable": {"infra_free_units_max": -1}}`).
## `infra_free_units` >= 0: (YALNIZ dev senaryosu, `--infra-free`) her bölgenin boş altyapı kapasitesi bu birime iner
## (kapasite = T0 yükü + N); -1 = oynanabilir varsayılan (yük + pay).
static func config_for(views: Array[ParcelView], stock: ExistingStockSource, patch: Dictionary = {},
		infra_free_units: int = -1) -> EconomyConfig:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(EconomyConfig.DEFAULT_PATH))
	var tune: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (raw is Dictionary and tune is Dictionary):
		push_error("playable_economy: yapılandırma okunamadı; varsayılan ekonomi kullanılıyor")
		return EconomyConfig.load_default()
	var tune_patch: Variant = patch.get("playable", {})
	if tune_patch is Dictionary:
		tune = _merge(tune as Dictionary, tune_patch)
		patch = patch.duplicate(true)
		patch.erase("playable")
	var region_of := {}
	for v in views:
		region_of[v.id] = v.region_code
	var res_units := {}
	var com_units := {}
	for id in stock.parcel_ids():
		var code: StringName = region_of.get(int(id), &"")
		if code == &"":
			continue
		var bucket := res_units if stock.use_of(int(id)) == &"residential" else com_units
		bucket[code] = int(bucket.get(code, 0)) + stock.units_of(int(id))
	var infra_res := int(((raw as Dictionary)["uses"] as Dictionary)["residential"]["infra_per_unit"])
	var infra_com := int(((raw as Dictionary)["uses"] as Dictionary)["commercial"]["infra_per_unit"])
	var headroom := int((tune as Dictionary).get("infra_headroom_pm", 0))
	var latent := int((tune as Dictionary).get("latent_demand_pm", 0))
	# Başlangıç BOŞ kapasitenin mutlak üst sınırı (birim); -1 = sınırsız (yalnız %`infra_headroom_pm` payı).
	var free_max := int((tune as Dictionary).get("infra_free_units_max", -1))
	var base_households := int((raw["regions"]["defaults"] as Dictionary)["initial_households"])
	var overrides: Dictionary = (raw["regions"] as Dictionary).get("overrides", {})
	var codes: Array = res_units.keys()
	for code in com_units:
		if not codes.has(code):
			codes.append(code)
	codes.sort()
	for code: StringName in codes:
		var res := int(res_units.get(code, 0))
		var com := int(com_units.get(code, 0))
		var load := res * infra_res + com * infra_com
		var entry: Dictionary = overrides.get(String(code), {})
		var free := load * headroom / 1000
		if free_max >= 0:
			free = mini(free, free_max)
		entry["infra_capacity_units"] = load + free + 1 if infra_free_units < 0 else load + infra_free_units
		entry["initial_households"] = base_households + res * latent / 1000
		overrides[String(code)] = entry
	(raw["regions"] as Dictionary)["overrides"] = overrides
	# Geçici tempo verisi (kare bütçesi): yalnız `decision.*` sayıları; karar KURALLARI değişmez.
	var pace: Variant = (tune as Dictionary).get("decision", {})
	if pace is Dictionary:
		raw["decision"] = _merge(raw["decision"], pace)
	var cfg := EconomyConfig.from_dict(_merge(raw as Dictionary, patch))
	if not cfg.is_valid():
		push_error("playable_economy: türetilen yapılandırma geçersiz: %s" % cfg.error)
		return EconomyConfig.load_default()
	return cfg


## Derin birleştirme (sözlükler özyinelemeli): `patch` değerleri `base` üzerine yazar. Yalnız test/deney yamaları için.
static func _merge(base: Dictionary, patch: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: Variant in patch:
		if out.get(key, null) is Dictionary and patch[key] is Dictionary:
			out[key] = _merge(out[key], patch[key])
		else:
			out[key] = patch[key]
	return out
