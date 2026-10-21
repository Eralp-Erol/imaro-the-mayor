class_name M2ResultModel
extends RefCounted
## "Döngü sonucu" (T-040, M2) görünüm modeli: SAF okuma, görünümden bağımsız ve testlidir. Hiçbir sayı uydurulmaz:
## her değer `SimFacade` okumasıdır (parcel_views, reasons_for, economy_outcome, snapshot).
##
## Okunan sim alanları:
## - Parsel: `ParcelView.zone/pending_zone/development/use/units/progress_pm/region_code/reason_ids`.
## - Yatırımcı kararı: `facade.reasons_for(parcel_ref)` süzülür `decision_key == decision.investor.develop` (en yeni).
##   `ParcelView.reason_ids` yalnız son 5 gerekçedir; inşaat sonrası grup tepkileri kararı listeden iter.
##   Ret nedeni KODU (imar/altyapı/finansman/talep/getiri) kaydedilen ETKENLERDEN okunur (`decline_cause`): engel
##   etkeni (değer -FIXED_SCALE) imar > altyapı > finansman sırasıyla; engel yoksa talep/getiri katkısı düşük olan
##   (sim kuralıyla aynı; test sim'in `event.investor.declined` kodu ile eşitliği denetler).
## - Bölge/şehir: `economy_outcome()` (`metrics(region)`, `delta_since(baseline, region)`, sayaçlar,
##   `municipal_revenue_available`).
## - Siyasi: `snapshot().group_reactions` (grup başına AYRI; toplam skor yok), `snapshot().council`.
## Karşılaştırma başlangıcı (`baseline`) null ise: birikimli alanlar (yeni birim, sayaçlar) zaten simülasyon başından
## beri toplamdır; "stok" alanlar (hane) için fark GÖSTERİLMEZ, yalnız şu anki değer.

## Karar durumu.
enum Decision { NONE, APPROVED, DECLINED }

const DECISION_KEY := &"decision.investor.develop"
const FACTOR_ZONING := &"reason.factor.zoning_fit"
const FACTOR_INFRA := &"reason.factor.infrastructure_capacity"
const FACTOR_FINANCING := &"reason.factor.financing"
const FACTOR_DEMAND := &"reason.factor.demand"
const FACTOR_RETURN := &"reason.factor.expected_return"
## Ret nedeni kodları (UI sözlüğü): `m2.decline.<kod>`.
const CAUSE_ZONING := &"zoning"
const CAUSE_INFRASTRUCTURE := &"infrastructure"
const CAUSE_FINANCING := &"financing"
const CAUSE_DEMAND := &"demand"
const CAUSE_RETURN := &"return"
const CAUSE_UNKNOWN := &"unknown"
## Ayrıntılı okunan en çok parsel (gerekçe taraması kopyalar; sınır bilinçli).
const MAX_DETAIL_PARCELS := 12
const MAX_REACTION_ROWS := 3


var tick: int = 0
var parcels: Array[ParcelRow] = []
var primary: ParcelRow = null
var parcels_capped: bool = false
var region_code: StringName = &""
var outcome: EconomyOutcomeView = null
var outcome_available: bool = false
var baseline_valid: bool = false
var baseline_tick: int = -1
var metrics: Array[MetricRow] = []
var counters: Array[MetricRow] = []
var pipeline_residential: int = 0
var pipeline_commercial: int = 0
var municipal_available: bool = false
var municipal_value: int = 0
var municipal_reason_key: StringName = &""
var reactions: Array[GroupReactionView] = []
var reactions_hidden: int = 0
var council_built: bool = false
var council_open: int = 0
var council_done: int = 0

var _cache: Dictionary = {}


## `tracked`: takip edilen parsel kimlikleri (imar önerisi verilenler). `baseline`: karşılaştırma başlangıcı ya da null.
## `cache`: parsel -> {sig, record} (aynı parselin gerekçe taramasını tekrarlamamak için; çağıran saklar).
static func build(facade: SimFacade, tracked: PackedInt64Array, baseline: EconomyOutcomeView, baseline_at: int,
		cache: Dictionary = {}) -> M2ResultModel:
	var m := M2ResultModel.new()
	m._cache = cache
	var snap := facade.snapshot()
	m.tick = snap.tick()
	m._read_parcels(facade, tracked)
	m._read_outcome(facade, baseline, baseline_at)
	m._read_politics(snap)
	return m


## Ret nedeni kodu, KAYDEDİLEN etkenlerden. Olumlu kayıt için boş.
static func decline_cause(rec: ReasonRecord) -> StringName:
	if rec == null or rec.outcome == ReasonRecord.OUTCOME_POSITIVE:
		return &""
	var veto := -SimContract.FIXED_SCALE
	var demand_part := 0
	var return_part := 0
	var found_core := 0
	var vetoes := {}
	for f in rec.factors:
		if f.value <= veto:
			vetoes[f.name_key] = true
		if f.name_key == FACTOR_DEMAND:
			demand_part = f.contribution()
			found_core += 1
		elif f.name_key == FACTOR_RETURN:
			return_part = f.contribution()
			found_core += 1
	if vetoes.has(FACTOR_ZONING):
		return CAUSE_ZONING
	if vetoes.has(FACTOR_INFRA):
		return CAUSE_INFRASTRUCTURE
	if vetoes.has(FACTOR_FINANCING):
		return CAUSE_FINANCING
	if found_core < 2:
		return CAUSE_UNKNOWN
	return CAUSE_DEMAND if demand_part <= return_part else CAUSE_RETURN


## Yatırımcı kararlarının en yenisi (kimliği en büyük); yoksa null.
static func latest_investor_decision(facade: SimFacade, parcel_id: int) -> ReasonRecord:
	var best: ReasonRecord = null
	for r in facade.reasons_for(SimContract.parcel_ref(parcel_id)):
		if r.decision_key == DECISION_KEY and (best == null or r.id > best.id):
			best = r
	return best


## Aşama (`parcel.development.*`) için UI anahtarı.
static func stage_key(development: StringName) -> StringName:
	return StringName("parcel.development.%s" % development)


## Panelin yeniden çizim imzası: gösterilen değerlerin özeti (tick tek başına yeniden çizdirmez).
func signature() -> String:
	var parts: Array[String] = [str(outcome_available), str(baseline_valid), str(region_code)]
	for p in parcels:
		parts.append("%d:%s:%d:%d:%s" % [p.id(), p.view.development, p.view.progress_pm, p.decision,
				p.view.pending_zone])
	for r in metrics + counters:
		parts.append("%s=%d/%d" % [r.key, r.value, r.delta])
	parts.append("%d/%d" % [pipeline_residential, pipeline_commercial])
	parts.append("%s%d" % [municipal_available, municipal_value])
	for g in reactions:
		parts.append(var_to_str(g.to_dict()))
	parts.append("%d/%d/%d/%s" % [reactions_hidden, council_open, council_done, council_built])
	return "|".join(parts)


func counts_decided() -> Dictionary:
	var out := {"approved": 0, "declined": 0, "waiting": 0}
	for p in parcels:
		match p.decision:
			Decision.APPROVED:
				out["approved"] += 1
			Decision.DECLINED:
				out["declined"] += 1
			_:
				out["waiting"] += 1
	return out


func metric(key: StringName) -> MetricRow:
	for r in metrics + counters:
		if r.key == key:
			return r
	return null


# --- okuma ---

func _read_parcels(facade: SimFacade, tracked: PackedInt64Array) -> void:
	if tracked.is_empty():
		return
	var ids := tracked.slice(0, MAX_DETAIL_PARCELS)
	parcels_capped = tracked.size() > MAX_DETAIL_PARCELS
	var views := facade.parcel_views(ids)
	for v in views:
		var row := ParcelRow.new()
		row.view = v
		_read_decision(facade, row)
		parcels.append(row)
	if parcels.is_empty():
		return
	# Asıl parsel: karar almış ilk (yoksa ilk) — öneri sırası korunur.
	primary = parcels[0]
	for p in parcels:
		if p.decision != Decision.NONE:
			primary = p
			break
	region_code = primary.view.region_code


func _read_decision(facade: SimFacade, row: ParcelRow) -> void:
	var v := row.view
	var newest := int(v.reason_ids[v.reason_ids.size() - 1]) if not v.reason_ids.is_empty() else 0
	var sig := "%s|%s|%d|%d" % [v.development, v.pending_zone, v.reason_ids.size(), newest]
	var cached: Dictionary = _cache.get(v.id, {})
	var rec: ReasonRecord = null
	if cached.has("sig") and cached["sig"] == sig:
		rec = cached["record"]
	else:
		rec = latest_investor_decision(facade, v.id)
		_cache[v.id] = {"sig": sig, "record": rec}
	row.record = rec
	if rec == null:
		return
	if rec.outcome == ReasonRecord.OUTCOME_POSITIVE:
		row.decision = Decision.APPROVED
	else:
		row.decision = Decision.DECLINED
		row.cause = decline_cause(rec)


func _read_outcome(facade: SimFacade, baseline: EconomyOutcomeView, baseline_at: int) -> void:
	outcome = facade.economy_outcome()
	outcome_available = outcome != null and outcome.available
	if not outcome_available:
		return
	baseline_valid = baseline != null and baseline.available
	baseline_tick = baseline_at if baseline_valid else -1
	var base: EconomyOutcomeView = baseline if baseline_valid else null
	var now := outcome.metrics(region_code)
	if now.is_empty():
		region_code = &""
		now = outcome.metrics()
	var delta := outcome.delta_since(base, region_code)
	var housed := _row(&"housed_households", now, delta, baseline_valid)
	housed.total = int(now.get("households", 0))
	metrics.append(_row(&"sim_residential_units", now, delta, true))
	metrics.append(_row(&"sim_commercial_units", now, delta, true))
	metrics.append(housed)
	pipeline_residential = int(now.get("residential_pipeline", 0))
	pipeline_commercial = int(now.get("commercial_pipeline", 0))
	var city_now := outcome.metrics()
	var city_delta := outcome.delta_since(base)
	for key: StringName in [&"investments_approved", &"investments_declined", &"projects_completed", &"rent_income"]:
		counters.append(_row(key, city_now, city_delta, true))
	municipal_available = outcome.municipal_revenue_available
	municipal_value = outcome.municipal_revenue
	municipal_reason_key = outcome.municipal_revenue_reason_key


func _row(key: StringName, now: Dictionary, delta: Dictionary, delta_ok: bool) -> MetricRow:
	var r := MetricRow.new()
	r.key = key
	r.value = int(now.get(String(key), 0))
	r.delta = int(delta.get(String(key), 0))
	r.delta_valid = delta_ok
	return r


func _read_politics(snap: SimSnapshot) -> void:
	var live: Array[GroupReactionView] = []
	for g in snap.group_reactions:
		if g.reaction != GroupReactionView.REACTION_NEUTRAL or g.intensity > 0:
			live.append(g)
	live.sort_custom(func(a: GroupReactionView, b: GroupReactionView) -> bool:
		return a.intensity > b.intensity or (a.intensity == b.intensity and a.stance < b.stance))
	reactions = live.slice(0, MAX_REACTION_ROWS)
	reactions_hidden = maxi(0, live.size() - reactions.size())
	council_built = SimSections.council_built(snap)
	if council_built:
		council_open = snap.council.pending_votes().size()
		council_done = snap.council.votes.size() - council_open


## Bir takip edilen parselin satırı.
class ParcelRow:
	extends RefCounted
	var view: ParcelView = null
	var decision: Decision = Decision.NONE
	var record: ReasonRecord = null
	var cause: StringName = &""

	func id() -> int:
		return view.id if view != null else SimContract.NO_ID


## Bir ölçüm satırı: `delta_valid` false ise yalnız `value` (şu an) anlamlıdır.
class MetricRow:
	extends RefCounted
	var key: StringName = &""
	var value: int = 0
	var delta: int = 0
	var delta_valid: bool = false
	var total: int = 0
