class_name EconomyConfig
extends RefCounted
## Ekonomi çekirdeği yapılandırması (T-013). Çalışma-modeli sayıları kodda değil
## `data/sim/economy/economy_config.json`'da
## (F05-C: ayarlanabilir, kanon değil; ölçek/nüfus/üretim F05-D AÇIK). Kurulumda okunur (tick dışında); tick kodu dosya
## G/Ç yapmaz. Formüller ve anlamlar: design/specs/economy-core-v0.md.
##
## Bölümler: `zones` (imar anahtarı -> izinli kullanımlar + varsayılan yoğunluk), `uses` (konut/ticaret proje
## parametreleri),
## `decision` / `cohorts` / `land` (düz tamsayı parametreler, `p(anahtar)`), `investors` (havuz), `regions`
## (varsayılan +
## bölge koduna göre geçersiz kılma; kod gömülü değildir). `_` ile başlayan anahtarlar belgedir ve yok sayılır.
## JSON sayıları float döner; tam sayı değerli olanlar int'e çevrilir, kesirli olanlar reddedilir. Bilinmeyen anahtar
## hatadır (yazım hatası sessizce yok sayılmaz).

const DEFAULT_PATH := "res://data/sim/economy/economy_config.json"

const USE_NONE := 0
const USE_RESIDENTIAL := 1
const USE_COMMERCIAL := 2
const _USE_IDS := {"residential": USE_RESIDENTIAL, "commercial": USE_COMMERCIAL}
const _NO_MAX := 1 << 40

## Anahtar -> [en az, en çok]. Hepsi tamsayıdır.
const _USE_SPEC := {
	"units_per_1000m2": [1, _NO_MAX], "cost_per_unit": [1, _NO_MAX], "rent_per_unit_month": [1, _NO_MAX],
	"infra_per_unit": [1, _NO_MAX], "plan_days": [1, _NO_MAX], "construction_base_days": [1, _NO_MAX],
	"construction_days_per_unit": [1, _NO_MAX],
}
const _DECISION_SPEC := {
	"w_demand": [0, 1000], "w_expected_return": [0, 1000], "w_construction_cost": [0, 1000],
	"w_infrastructure": [0, 1000], "w_financing": [0, 1000], "w_zoning": [0, 1000], "w_sentiment": [0, 1000],
	"base_threshold": [-1000000, 1000000], "sentiment_range": [0, 1000], "demand_gain_pm": [1, _NO_MAX],
	"rent_floor_pm": [1, _NO_MAX], "rent_cap_pm": [1, _NO_MAX], "interest_pm": [0, 1000],
	"yield_full_scale_pm": [1, _NO_MAX], "project_scale_ref": [1, _NO_MAX], "infra_bonus_max": [0, 1000],
	"financing_bonus_max": [0, 1000], "review_enabled": [0, 1], "review_period_days": [1, 3650],
	"max_reviews_per_tick": [1, 1000000], "decline_backoff_days": [0, 3650],
	"attention_delay_days": [0, 3650],
	"prescreen_demand_pm": [0, 1000], "negative_repeat_days": [1, 36500], "max_starts_per_region_per_day": [1, 10000],
	"storey_m": [1, 1000], "reference_floors": [1, 1000],
}
const _COHORT_SPEC := {
	"initial_occupancy_pm": [0, 1000], "shops_per_household_pm": [0, _NO_MAX], "jobs_per_commercial_unit": [0, _NO_MAX],
	"jobs_needed_per_household_pm": [0, _NO_MAX], "w_access": [0, 1000], "w_service": [0, 1000], "w_jobs": [0, 1000],
	"growth_base_pm": [0, 1000],
}
const _LAND_SPEC := {
	"speculation_demand_pm": [0, 1000], "speculation_rate_pm": [0, 1000], "relax_demand_pm": [0, 1000],
	"relax_rate_pm": [0, 1000], "max_multiplier_pm": [1000, _NO_MAX],
}
const _REGION_SPEC := {
	"initial_households": [0, _NO_MAX], "income_pm": [0, _NO_MAX], "access_pm": [0, 1000], "service_pm": [0, 1000],
	"infra_capacity_units": [0, _NO_MAX],
}

## Düz parametreler (decision + cohorts + land), anahtar -> int.
var params: Dictionary = {}
## Kullanım kimliği (USE_*) -> {anahtar: int}.
var uses: Dictionary = {}
## Imar anahtarı (StringName) -> {"uses": Array[int] (USE_*), "density_pm": int}.
var zones: Dictionary = {}
## Yatırımcı havuzu: [{"capital", "threshold_shift", "monthly_inflow": int}], sıra = yatırımcı kimliği - 1.
var investors: Array[Dictionary] = []
var region_defaults: Dictionary = {}
## Bölge kodu (StringName) -> kısmi {anahtar: int}.
var region_overrides: Dictionary = {}
## Geçersizse insan-okur hata metni, geçerliyse "".
var error: String = ""


static func load_default() -> EconomyConfig:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> EconomyConfig:
	if not FileAccess.file_exists(path):
		return _invalid("ekonomi yapılandırma dosyası yok: %s" % path)
	return from_json_text(FileAccess.get_file_as_string(path))


static func from_json_text(text: String) -> EconomyConfig:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _invalid("ekonomi yapılandırma JSON ayrıştırılamadı (satır %d: %s)"
			% [json.get_error_line(), json.get_error_message()])
	if not (json.data is Dictionary):
		return _invalid("ekonomi yapılandırma JSON nesnesi değil")
	return from_dict(json.data)


static func from_dict(data: Dictionary) -> EconomyConfig:
	var cfg := EconomyConfig.new()
	for section in ["zones", "uses", "decision", "investors", "regions", "cohorts", "land"]:
		if not (data.get(section, null) is Dictionary):
			return _invalid("'%s' bölümü eksik veya nesne değil" % section)
	var problem := cfg._read_zones(data["zones"])
	if problem.is_empty():
		problem = cfg._read_uses(data["uses"])
	if problem.is_empty():
		problem = _read_ints(data["decision"], _DECISION_SPEC, "decision", cfg.params)
	if problem.is_empty():
		problem = _read_ints(data["cohorts"], _COHORT_SPEC, "cohorts", cfg.params)
	if problem.is_empty():
		problem = _read_ints(data["land"], _LAND_SPEC, "land", cfg.params)
	if problem.is_empty():
		problem = cfg._read_investors(data["investors"])
	if problem.is_empty():
		problem = cfg._read_regions(data["regions"])
	if problem.is_empty():
		problem = cfg._cross_checks()
	if not problem.is_empty():
		return _invalid(problem)
	return cfg


func is_valid() -> bool:
	return error.is_empty()


## Düz parametre; bilinmeyen anahtarda push_error + 0 (kod yazım hatası testte yakalanır).
func p(key: String) -> int:
	if not params.has(key):
		push_error("EconomyConfig: unknown param '%s'" % key)
		return 0
	return params[key]


## Kullanım parametresi (USE_RESIDENTIAL / USE_COMMERCIAL).
func use_param(use: int, key: String) -> int:
	return int((uses[use] as Dictionary)[key])


## Imar profili ya da bilinmeyen imarda boş sözlük (yapılanmaya kapalı).
func zone_profile(zone: StringName) -> Dictionary:
	return zones.get(zone, {})


## Bölgenin başlangıç parametreleri: varsayılan + o koda ait geçersiz kılmalar.
func region_params(code: StringName) -> Dictionary:
	var out := region_defaults.duplicate()
	out.merge(region_overrides.get(code, {}), true)
	return out


# --- Okuma ---

func _read_zones(src: Dictionary) -> String:
	for key: Variant in src:
		if str(key).begins_with("_"):
			continue
		var entry: Variant = src[key]
		if not (entry is Dictionary) or not (entry.get("uses", null) is Array):
			return "zones.%s {uses: [...], density_pm} değil" % key
		var use_ids: Array[int] = []
		for name: Variant in entry["uses"]:
			if not _USE_IDS.has(str(name)):
				return "zones.%s.uses bilinmeyen kullanım '%s' (residential|commercial)" % [key, name]
			if use_ids.has(_USE_IDS[str(name)]):
				return "zones.%s.uses tekrarlı '%s'" % [key, name]
			use_ids.append(_USE_IDS[str(name)])
		var density: Variant = _as_int(entry.get("density_pm", null))
		if density == null or int(density) < 1:
			return "zones.%s.density_pm >= 1 tam sayı olmalı" % key
		zones[StringName(str(key))] = {"uses": use_ids, "density_pm": int(density)}
	if zones.is_empty():
		return "zones boş"
	return ""


func _read_uses(src: Dictionary) -> String:
	for name: String in _USE_IDS:
		if not (src.get(name, null) is Dictionary):
			return "uses.%s eksik" % name
		var values := {}
		var problem := _read_ints(src[name], _USE_SPEC, "uses.%s" % name, values)
		if not problem.is_empty():
			return problem
		uses[_USE_IDS[name]] = values
	for key: Variant in src:
		if not str(key).begins_with("_") and not _USE_IDS.has(str(key)):
			return "uses.%s bilinmeyen kullanım (residential|commercial)" % key
	return ""


func _read_investors(src: Dictionary) -> String:
	var list: Variant = src.get("list", null)
	if not (list is Array) or (list as Array).is_empty():
		return "investors.list boş veya dizi değil"
	for i in (list as Array).size():
		var entry: Variant = list[i]
		if not (entry is Dictionary):
			return "investors.list[%d] nesne değil" % i
		var capital: Variant = _as_int(entry.get("capital", null))
		var shift: Variant = _as_int(entry.get("threshold_shift", null))
		var inflow: Variant = _as_int(entry.get("monthly_inflow", null))
		if capital == null or int(capital) < 1:
			return "investors.list[%d].capital >= 1 tam sayı olmalı" % i
		if shift == null or absi(int(shift)) > 1000:
			return "investors.list[%d].threshold_shift |x| <= 1000 tam sayı olmalı" % i
		if inflow == null or int(inflow) < 0:
			return "investors.list[%d].monthly_inflow >= 0 tam sayı olmalı" % i
		investors.append({"capital": int(capital), "threshold_shift": int(shift), "monthly_inflow": int(inflow)})
	return ""


func _read_regions(src: Dictionary) -> String:
	if not (src.get("defaults", null) is Dictionary):
		return "regions.defaults eksik"
	var problem := _read_ints(src["defaults"], _REGION_SPEC, "regions.defaults", region_defaults, true)
	if not problem.is_empty():
		return problem
	var overrides: Variant = src.get("overrides", {})
	if not (overrides is Dictionary):
		return "regions.overrides nesne değil"
	for code: Variant in overrides:
		if str(code).begins_with("_"):
			continue
		var values := {}
		problem = _read_ints(overrides[code], _REGION_SPEC, "regions.overrides.%s" % code, values, false)
		if not problem.is_empty():
			return problem
		region_overrides[StringName(str(code))] = values
	return ""


func _cross_checks() -> String:
	if p("rent_cap_pm") < p("rent_floor_pm"):
		return "decision.rent_cap_pm rent_floor_pm değerinden küçük olamaz"
	if p("w_access") + p("w_service") + p("w_jobs") < 1:
		return "cohorts.w_access + w_service + w_jobs >= 1 olmalı"
	return ""


## `src` içinde `spec`'teki tüm anahtarlar tamsayı ve aralıkta olmalı (`require_all=false` ise kısmi kabul).
static func _read_ints(src: Variant, spec: Dictionary, label: String, out: Dictionary,
		require_all: bool = true) -> String:
	if not (src is Dictionary):
		return "%s nesne değil" % label
	for key: Variant in src:
		if str(key).begins_with("_"):
			continue
		if not spec.has(str(key)):
			return "%s.%s bilinmeyen anahtar" % [label, key]
	for key: String in spec:
		if not src.has(key):
			if require_all:
				return "%s.%s eksik" % [label, key]
			continue
		var value: Variant = _as_int(src[key])
		var bounds: Array = spec[key]
		if value == null:
			return "%s.%s tam sayı değil (kesirli sayı yasak; 1000 ölçekli tamsayı kullanın)" % [label, key]
		if int(value) < int(bounds[0]) or int(value) > int(bounds[1]):
			return "%s.%s aralık dışı (%d..%d)" % [label, key, bounds[0], bounds[1]]
		out[key] = int(value)
	return ""


static func _invalid(message: String) -> EconomyConfig:
	var cfg := EconomyConfig.new()
	cfg.error = message
	return cfg


static func _as_int(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
		return int(value)
	return null
