class_name EconomyQuery
extends RefCounted
## Ekonomi durumunun salt okunur sorguları (T-013): T-014 (bütçe/altyapı), T-017 (siyasi tepki), HUD/denetçi ve testler
## için API. Durumu DEĞİŞTİRMEZ; sözlükler kopyadır. Ekonomi kurulu değilse/ilk tick geçmediyse boş sonuç.


## {parcel_id, stage, use, units, owner_id, land_value, days_left, reason_id}; yoksa {}.
static func parcel_record(state: GameState, parcel_id: int) -> Dictionary:
	var d := EconomyState.data(state)
	if d.is_empty():
		return {}
	var i := EconomyState.index_of(d, parcel_id)
	if i < 0:
		return {}
	return {
		"parcel_id": parcel_id,
		"stage": EconomyState.stage_name((d["stage"] as PackedByteArray)[i]),
		"use": EconomyState.use_name((d["use"] as PackedByteArray)[i]),
		"units": (d["units"] as PackedInt32Array)[i],
		"owner_id": (d["owner_id"] as PackedInt32Array)[i],
		"land_value": (d["land_value"] as PackedInt64Array)[i],
		"days_left": (d["days_left"] as PackedInt32Array)[i],
		"reason_id": (d["reason_id"] as PackedInt64Array)[i],
	}


## Bölge başına satırlar (bölge kodu sırasıyla): ham kohort sütunları + türetilmiş endeksler.
static func region_stats(state: GameState, cfg: EconomyConfig) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := EconomyState.data(state)
	if d.is_empty():
		return out
	var regions: Dictionary = d["regions"]
	for r in (regions["codes"] as PackedStringArray).size():
		out.append(region_row(regions, r, cfg))
	return out


static func region_row(regions: Dictionary, r: int, cfg: EconomyConfig) -> Dictionary:
	var latent: int = regions["latent_hh"][r]
	var res_built: int = regions["res_built"][r]
	var com_built: int = regions["com_built"][r]
	var infra_cap: int = regions["infra_cap"][r]
	var load := EconomyMath.infra_load(cfg, regions, r)
	return {
		"code": StringName((regions["codes"] as PackedStringArray)[r]),
		"latent_hh": latent, "housed_hh": mini(latent, res_built),
		"res_built": res_built, "res_pipe": regions["res_pipe"][r],
		"com_built": com_built, "com_pipe": regions["com_pipe"][r],
		"infra_cap": infra_cap, "infra_load": load, "infra_load_pm": EconomyMath.ratio_pm(load, infra_cap),
		"income_pm": regions["income_pm"][r], "access_pm": regions["access_pm"][r],
		"service_pm": regions["service_pm"][r],
		"demand_res_pm": EconomyMath.region_demand_pm(cfg, regions, r, EconomyConfig.USE_RESIDENTIAL, 0),
		"demand_com_pm": EconomyMath.region_demand_pm(cfg, regions, r, EconomyConfig.USE_COMMERCIAL, 0),
	}


## Toplam sayaçlar (değerlendirme, onay, ret, tamamlanma, arsa satışı, inşaat harcaması, kira geliri...).
static func totals(state: GameState) -> Dictionary:
	var d := EconomyState.data(state)
	return {} if d.is_empty() else (d["totals"] as Dictionary).duplicate()
