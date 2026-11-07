class_name EconomyMonthly
extends RefCounted
## Ekonomi aylık akışı (T-013, T-078 ile `EconomySystem`den ayrıldı; DAVRANIŞ DEĞİŞMEDİ): hane kohortu (SIM-01), arsa
## değeri (SIM-07), yatırımcı sermaye girdisi ve kira geliri. Sıra sabittir (`run`). Durum TUTMAZ: kalıcı veri
## `state.systems["economy"]` içindedir (`d`); nesnedeki alanlar `EconomySystem` kurulumunda türetilmiş değişmez
## önbelleklerin salt okunur paylaşımıdır. Rastgelelik yoktur.

var _cfg: EconomyConfig
var _ids: PackedInt64Array
var _region_of: PackedInt32Array
var _region_codes: PackedStringArray
var _base_land: PackedInt64Array
var _base_zone: PackedStringArray
var _unplanned_on: bool


func _init(cfg: EconomyConfig, ids: PackedInt64Array, region_of: PackedInt32Array, region_codes: PackedStringArray,
		base_land: PackedInt64Array, base_zone: PackedStringArray, unplanned_on: bool) -> void:
	_cfg = cfg
	_ids = ids
	_region_of = region_of
	_region_codes = region_codes
	_base_land = base_land
	_base_zone = base_zone
	_unplanned_on = unplanned_on


## Aylık sıra: kohort -> arsa değeri -> sermaye girdisi -> kira.
func run(d: Dictionary) -> void:
	_update_cohorts(d)
	_update_land_values(d)
	_collect_rents(d)
	_inject_capital(d)


## Hane kohortu: çekim (erişim/hizmet/iş dengesi) -> işaretli aylık büyüme; kesir `growth_frac`'ta birikir.
@warning_ignore("integer_division")
func _update_cohorts(d: Dictionary) -> void:
	var regions: Dictionary = d["regions"]
	var latent: PackedInt64Array = regions["latent_hh"]
	var frac: PackedInt64Array = regions["growth_frac"]
	var res_built: PackedInt64Array = regions["res_built"]
	var com_built: PackedInt64Array = regions["com_built"]
	var access: PackedInt64Array = regions["access_pm"]
	var service: PackedInt64Array = regions["service_pm"]
	var w_access := _cfg.p("w_access")
	var w_service := _cfg.p("w_service")
	var w_jobs := _cfg.p("w_jobs")
	var w_sum := w_access + w_service + w_jobs
	for r in latent.size():
		var housed := mini(latent[r], res_built[r])
		var jobs := com_built[r] * _cfg.p("jobs_per_commercial_unit")
		var needed := housed * _cfg.p("jobs_needed_per_household_pm") / 1000
		var job_balance := 500 if needed <= 0 else mini(1000, EconomyMath.ratio_pm(jobs, needed))
		var pull := (access[r] * w_access + service[r] * w_service + job_balance * w_jobs) / w_sum
		var growth_pm := _cfg.p("growth_base_pm") * (pull - 500) / 500
		var step := EconomyMath.accumulate_pm(latent[r], growth_pm, frac[r])
		latent[r] = maxi(0, latent[r] + step[0])
		frac[r] = step[1]


## Boş yapılabilir parsellerde aylık: izinli kullanımların en yüksek talebi `speculation_demand_pm` üstündeyse arsa
## değeri
## `speculation_rate_pm` kadar artar (tavan: taban x max_multiplier_pm); `relax_demand_pm` altındaysa taban değere doğru
## `relax_rate_pm` kadar geri çekilir. Yapılı/yapılmakta olan ve yapılanmaya kapalı imarlı parsellere dokunulmaz.
@warning_ignore("integer_division")
func _update_land_values(d: Dictionary) -> void:
	var regions: Dictionary = d["regions"]
	var rn := _region_codes.size()
	var demand_by_use: Array = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for use in [EconomyConfig.USE_RESIDENTIAL, EconomyConfig.USE_COMMERCIAL]:
		var col := PackedInt32Array()
		col.resize(rn)
		for r in rn:
			col[r] = EconomyMath.region_demand_pm(_cfg, regions, r, use, 0)
		demand_by_use[use] = col
	var zone_demand := {}  # imar (String) -> bölge başına izinli kullanımların en yüksek talebi (-1 = yapılanmaya kapalı)
	var zone_seen: Dictionary = d["zone_seen"]
	var stage: PackedByteArray = d["stage"]
	var land: PackedInt64Array = d["land_value"]
	var spec_demand := _cfg.p("speculation_demand_pm")
	var spec_rate := _cfg.p("speculation_rate_pm")
	var relax_demand := _cfg.p("relax_demand_pm")
	var relax_rate := _cfg.p("relax_rate_pm")
	var max_mult := _cfg.p("max_multiplier_pm")
	# T-049: plansız modda görülen imarı olmayan parselin imarı "" ve "" imarın izinli kullanımı yoksa (talep -1) hiçbiri
	# yapılanmaya açık değildir: tam tarama (40 k parsel, ~19 ms) yerine yalnız `zone_seen` parselleri bakılır. Güncelleme
	# parsel başına bağımsızdır, sonuç tam tarama ile aynıdır (tests/sim/economy/economy_land_values_unplanned_test.gd).
	var only_seen := _unplanned_on and _all_closed(_zone_demand_by_region("", demand_by_use, rn))
	var scan: Array = zone_seen.keys() if only_seen else []
	for k in (scan.size() if only_seen else _ids.size()):
		var i: int = scan[k] if only_seen else k
		if stage[i] != EconomyState.STAGE_VACANT:
			continue
		var zone: String = String(_seen_zone(zone_seen, i))
		if not zone_demand.has(zone):
			zone_demand[zone] = _zone_demand_by_region(zone, demand_by_use, rn)
		var demand: int = (zone_demand[zone] as PackedInt32Array)[_region_of[i]]
		if demand < 0:
			continue
		var base: int = _base_land[i]
		if demand >= spec_demand:
			land[i] = mini(land[i] + land[i] * spec_rate / 1000, base * max_mult / 1000)
		elif demand <= relax_demand and land[i] > base:
			land[i] -= maxi(1, (land[i] - base) * relax_rate / 1000)


## Bölge başına talep sütununun hepsi yapılanmaya kapalı (-1) mı?
func _all_closed(demand: PackedInt32Array) -> bool:
	for value in demand:
		if value >= 0:
			return false
	return true


func _zone_demand_by_region(zone: String, demand_by_use: Array, rn: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(rn)
	var uses: Array = _cfg.zone_profile(StringName(zone)).get("uses", [])
	for r in rn:
		var demand := -1 if uses.is_empty() else 0
		for use: int in uses:
			demand = maxi(demand, (demand_by_use[use] as PackedInt32Array)[r])
		out[r] = demand
	return out


## Aylık dış sermaye girdisi (kredi/diğer gelir): her yatırımcının sermayesine `monthly_inflow` eklenir.
func _inject_capital(d: Dictionary) -> void:
	var investors: Dictionary = d["investors"]
	var capital: PackedInt64Array = investors["capital"]
	var inflow: PackedInt64Array = investors["monthly_inflow"]
	var totals: Dictionary = d["totals"]
	for k in capital.size():
		capital[k] += inflow[k]
		totals["capital_inflow"] += inflow[k]


## Yatırımcıya ait yapılı parsellerin aylık kirası: birim x birim kirası x talep kira çarpanı. Finansman geri bildirimi:
## sermaye artar, yeni yatırımlar mümkün olur. Arsa sahibine ait T0 stoku yatırımcı geliri üretmez.
@warning_ignore("integer_division")
func _collect_rents(d: Dictionary) -> void:
	var regions: Dictionary = d["regions"]
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var owner_col: PackedInt32Array = d["owner_id"]
	var capital: PackedInt64Array = (d["investors"] as Dictionary)["capital"]
	var totals: Dictionary = d["totals"]
	var rent_floor := _cfg.p("rent_floor_pm")
	var rent_cap := _cfg.p("rent_cap_pm")
	var demand_cache := {}
	for i in _ids.size():
		if stage[i] != EconomyState.STAGE_BUILT or owner_col[i] <= 0:
			continue
		var use: int = use_col[i]
		var key := _region_of[i] * 4 + use
		if not demand_cache.has(key):
			demand_cache[key] = EconomyMath.region_demand_pm(_cfg, regions, _region_of[i], use, 0)
		var income: int = units_col[i] * _cfg.use_param(use, "rent_per_unit_month") \
			* EconomyMath.rent_mult_pm(demand_cache[key], rent_floor, rent_cap) / 1000
		capital[owner_col[i] - 1] += income
		totals["rent_income"] += income


func _seen_zone(zone_seen: Dictionary, i: int) -> StringName:
	return EconomyState.seen_zone(zone_seen, i, _unplanned_on, _base_zone)
