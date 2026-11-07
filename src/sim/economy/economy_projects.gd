class_name EconomyProjects
extends RefCounted
## Ekonomi proje yaşam döngüsü (SIM-03/08; T-013/T-014, T-078 ile `EconomySystem`den ayrıldı; DAVRANIŞ DEĞİŞMEDİ):
## `planned` -> `under_construction` -> `built`, altyapı kapasitesi yetmeyince `stalled`/devam, bölgenin ETKİN altyapı
## kapasitesi. Durum TUTMAZ: kalıcı veri `state.systems["economy"]` içindedir (`d`); nesnedeki alanlar `EconomySystem`
## kurulumunda türetilmiş değişmez önbelleklerin salt okunur paylaşımıdır (`_changes` halkası paylaşılan DURUM DEĞİL
## nesnedir: parsel değişikliklerini aynı halkaya yazar). Rastgelelik yoktur.

var _cfg: EconomyConfig
var _ids: PackedInt64Array
var _region_codes: PackedStringArray
var _region_of: PackedInt32Array
var _changes: ParcelChangeLog


func _init(cfg: EconomyConfig, ids: PackedInt64Array, region_codes: PackedStringArray, region_of: PackedInt32Array,
		changes: ParcelChangeLog) -> void:
	_cfg = cfg
	_ids = ids
	_region_codes = region_codes
	_region_of = region_of
	_changes = changes


## `planned` -> `under_construction` -> `built`; her aşama `days_left` gün sürer. İnşaatta bölge altyapı yükü kapasiteyi
## aşarsa (kapasite düşünce; T-014) proje `stalled` olur, süre işlemez; kapasite dönünce sürer. Sıralı indeks
## iterasyonu.
func progress(state: GameState, d: Dictionary) -> void:
	var active: Dictionary = d["active"]
	if active.is_empty():
		return
	var keys: Array = active.keys()
	keys.sort()
	for i: int in keys:
		match (d["stage"] as PackedByteArray)[i]:
			EconomyState.STAGE_PLANNED:
				_tick_planned(state, d, i)
			EconomyState.STAGE_UNDER_CONSTRUCTION:
				_tick_construction(state, d, i)
			EconomyState.STAGE_STALLED:
				_tick_stalled(state, d, i)


## Bölgenin ETKİN altyapı kapasitesi: taban sütunu (`regions.infra_cap`) + oyuncu yollarının eklediği (T-042,
## `PublicWorksState.infra_bonus`; yol yoksa 0 => eski davranış). Sütuna YAZILMAZ: geri alma bonusu kendiliğinden
## düşürür.
func effective_cap(state: GameState, regions: Dictionary, r: int) -> int:
	return int((regions["infra_cap"] as PackedInt64Array)[r]) + PublicWorksState.infra_bonus(state, _region_codes[r])


func _headroom(state: GameState, d: Dictionary, i: int) -> int:
	var regions: Dictionary = d["regions"]
	var r := _region_of[i]
	return effective_cap(state, regions, r) - EconomyMath.infra_load(_cfg, regions, r)


func _tick_planned(state: GameState, d: Dictionary, i: int) -> void:
	var days_left: PackedInt32Array = d["days_left"]
	days_left[i] -= 1
	if days_left[i] > 0:
		return
	var use: int = (d["use"] as PackedByteArray)[i]
	var stage: PackedByteArray = d["stage"]
	stage[i] = EconomyState.STAGE_UNDER_CONSTRUCTION
	days_left[i] = EconomyMath.construction_days(_cfg, use, (d["units"] as PackedInt32Array)[i])
	_changes.note(_ids[i])
	_emit_parcel_event(state, d, i, &"event.construction.started", int((d["reason_id"] as PackedInt64Array)[i]))


func _tick_construction(state: GameState, d: Dictionary, i: int) -> void:
	if _headroom(state, d, i) < 0:
		_change_construction(state, d, i, EconomyState.STAGE_STALLED, &"construction_stalled",
			&"event.construction.stalled", -1000)
		return
	var days_left: PackedInt32Array = d["days_left"]
	days_left[i] -= 1
	if days_left[i] > 0:
		return
	var regions: Dictionary = d["regions"]
	var use: int = (d["use"] as PackedByteArray)[i]
	var units: int = (d["units"] as PackedInt32Array)[i]
	var r := _region_of[i]
	var pipe: PackedInt64Array = regions["res_pipe"] if use == EconomyConfig.USE_RESIDENTIAL else regions["com_pipe"]
	var built: PackedInt64Array = regions["res_built"] if use == EconomyConfig.USE_RESIDENTIAL else regions["com_built"]
	pipe[r] -= units
	built[r] += units
	var stage: PackedByteArray = d["stage"]
	stage[i] = EconomyState.STAGE_BUILT
	(d["active"] as Dictionary).erase(i)
	(d["totals"] as Dictionary)["completions"] += 1
	_changes.note(_ids[i])
	_emit_parcel_event(state, d, i, &"event.construction.completed", int((d["reason_id"] as PackedInt64Array)[i]))


func _tick_stalled(state: GameState, d: Dictionary, i: int) -> void:
	var headroom := _headroom(state, d, i)
	if headroom < 0:
		return
	var cap := effective_cap(state, d["regions"], _region_of[i])
	var value := mini(_cfg.p("infra_bonus_max"), EconomyMath.ratio_pm(headroom, cap))
	_change_construction(state, d, i, EconomyState.STAGE_UNDER_CONSTRUCTION, &"construction_resumed",
		&"event.construction.resumed", value)


## Durma/devam kararı: sahibi yatırımcının gerekçeli kararı (eşik 0: altyapı etkeni negatifse devam etmez).
func _change_construction(state: GameState, d: Dictionary, i: int, new_stage: int, code: StringName,
		message_key: StringName, infra_value: int) -> void:
	var reason_col: PackedInt64Array = d["reason_id"]
	var owner_id: int = (d["owner_id"] as PackedInt32Array)[i]
	var parents := PackedInt64Array()
	if reason_col[i] > 0:
		parents.append(reason_col[i])
	var reason_id := state.record_reason(StringName("actor.investor.%d" % owner_id), &"decision.investor.continue",
		[_continue_infra_factor(state, i, infra_value)], 0, code,
		PackedStringArray([String(SimContract.parcel_ref(_ids[i]))]), parents)
	reason_col[i] = reason_id
	var stage: PackedByteArray = d["stage"]
	stage[i] = new_stage
	if new_stage == EconomyState.STAGE_STALLED:
		(d["totals"] as Dictionary)["stalls"] += 1
	_changes.note(_ids[i])
	_emit_parcel_event(state, d, i, message_key, reason_id)


## Durma/devam gerekçesinin altyapı etkeni; kapasiteyi en son oyuncu yolu artırdıysa `source_ref` o yoldur (SIM-12).
func _continue_infra_factor(state: GameState, i: int, infra_value: int) -> Dictionary:
	var factor := {"name": InvestorDecision.F_INFRA, "value": infra_value, "weight": _cfg.p("w_infrastructure")}
	var source := PublicWorksState.infra_source(state, _region_codes[_region_of[i]])
	if source != &"":
		factor["source_ref"] = source
	return factor


func _emit_parcel_event(state: GameState, d: Dictionary, i: int, message_key: StringName, reason_id: int) -> void:
	var owner_id: int = (d["owner_id"] as PackedInt32Array)[i]
	var args := {
		"use": String(EconomyState.use_name((d["use"] as PackedByteArray)[i])),
		"units": (d["units"] as PackedInt32Array)[i],
	}
	SimEventLog.emit(state, &"parcel.changed", message_key,
		PackedStringArray([String(SimContract.parcel_ref(_ids[i]))]), args, PackedInt64Array([reason_id]), 0,
		StringName("actor.investor.%d" % owner_id))
