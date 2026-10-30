class_name InspectorModel
extends RefCounted
## Parsel/bölge denetçisi görünüm modeli (T-041, CAN-04/SIM-12): SAF okuma, düğüm yok, testlidir. Hiçbir değer
## uydurulmaz; her alan `SimFacade` okumasıdır:
## - İmar planı durumu: `plan_state(parcel_id)` (Plansız / Teklif verildi / Planlı / Reddedildi / Yapılı; T-043A).
## - Parsel: `parcel_views` -> `ParcelView.zone/pending_zone/development/use/units/progress_pm/owner/land_value/
##   area_m2/region_code/decision*` (M2ResultModel aracılığıyla; sonuç paneliyle AYNI okuma).
## - Gerekçe: `reasons_for(parcel.N)` içinden `decision.investor.develop` kayıtları (`ParcelView.reason_ids` yalnız
##   son 5 gerekçedir, karar kaynağı değildir). Karar `ParcelView.decision*`dandır; kayıt budandıysa karar yine
##   gösterilir, etkenler yoktur (`reason_pruned`).
## - Bölge: `economy_outcome()` (M2ResultModel). Belediye geliri sim'de kurulu değilse dürüst "kurulmadı".
## - Grup tepkisi: `snapshot().group_reactions` içinde `cause_refs` bu parseli içerenler + bu parsele bağlı
##   `group.reacted` olayları (geçmiş).
## Ölçek bandı yalnız SUNUMU değiştirir (`detail_level`); veri aynıdır.

enum State { EMPTY, MISSING, READY }
## Sunum ayrıntısı: sokakta parsel ayrıntısı, mahallede özet, ilçede bölge özeti.
enum Detail { PARCEL, SUMMARY, REGION }

const DECISION_KEY := &"decision.investor.develop"
const MAX_FACTORS := 3
const MAX_LINKED := 3
const MAX_PAST := 2
## Geçmiş grup olayları için taranan en çok olay sayısı (günlük sınırlı; tam tarama yok).
const EVENT_SCAN := 400

var state: State = State.EMPTY
var parcel_id: int = SimContract.NO_ID
var band: StringName = &""
var detail: Detail = Detail.PARCEL
var tick: int = 0
## Sonuç paneliyle ortak okuma (parsel satırı, bölge ölçümleri, belediye geliri).
var m2: M2ResultModel = null
var view: ParcelView = null
## İmar planı durumu (`SimFacade.plan_state`; T-043A). Kaynak plan kavramı sunmuyorsa `untracked`.
var plan: PlanStateView = null
## Son yatırımcı kararı kaydı (`decision.investor.develop`), yoksa null.
var record: ReasonRecord = null
var factors: Array[ReasonModel.Row] = []
## Karar var ama gerekçe kaydı günlükte yok.
var reason_pruned: bool = false
var linked_reactions: Array[GroupReactionView] = []
var past_reactions: Array[SimEvent] = []


## `parcel_id <= 0` boş seçimdir. Facade'de olmayan parsel `MISSING` olur (hata yok).
static func build(facade: SimFacade, parcel_id_in: int, band_in: StringName) -> InspectorModel:
	var m := InspectorModel.new()
	m.parcel_id = parcel_id_in
	m.band = band_in
	m.detail = detail_for_band(band_in)
	m.tick = facade.current_tick()
	if parcel_id_in <= 0:
		return m
	m.m2 = M2ResultModel.build(facade, PackedInt64Array([parcel_id_in]), null, -1)
	if m2_missing(m.m2):
		m.state = State.MISSING
		return m
	m.state = State.READY
	m.view = m.m2.primary.view
	m.plan = facade.plan_state(parcel_id_in)
	m._read_reason(facade)
	m._read_reactions(facade)
	return m


static func m2_missing(model: M2ResultModel) -> bool:
	return model == null or model.primary == null


## street -> parsel ayrıntısı; neighborhood -> özet; district/metro/ülke/bilinmeyen -> bölge özeti.
static func detail_for_band(band_in: StringName) -> Detail:
	match band_in:
		&"street", &"":
			return Detail.PARCEL
		&"neighborhood":
			return Detail.SUMMARY
	return Detail.REGION


func row() -> M2ResultModel.ParcelRow:
	return m2.primary if m2 != null else null


func is_ready() -> bool:
	return state == State.READY


func has_decision() -> bool:
	return is_ready() and row().recorded != M2ResultModel.Decision.NONE


func is_declined() -> bool:
	return is_ready() and row().recorded == M2ResultModel.Decision.DECLINED


## Değerler + yapı: değişmedikçe panel yeniden çizilmez.
func signature() -> String:
	if not is_ready():
		return "%d|%d" % [state, parcel_id]
	var parts: Array[String] = [str(state), str(parcel_id), str(detail), m2.signature(), str(reason_pruned),
			"%s/%d/%d/%s" % [plan.state, plan.due_tick, plan.command_id, plan.vote_ref] if plan != null else "",
			str(record.id if record != null else 0)]
	for g in linked_reactions:
		parts.append("%d/%s/%d/%d" % [g.group.id, g.reaction, g.intensity, g.tick])
	for e in past_reactions:
		parts.append(str(e.seq))
	return "|".join(parts)


func _read_reason(facade: SimFacade) -> void:
	var r := row()
	if r.recorded == M2ResultModel.Decision.NONE:
		return
	var best: ReasonRecord = null
	for rec in facade.reasons_for(view.ref()):
		if rec.decision_key != DECISION_KEY:
			continue
		# Yalnız KAYITLI kararın tick'inden bu yana yazılmış kayıtlar bu kararı açıklar (eski karar kaydı değil).
		if rec.tick < r.tick:
			continue
		if best == null or rec.tick > best.tick or (rec.tick == best.tick and rec.id > best.id):
			best = rec
	# Kararın kendi gerekçe kimliği varsa o kayıt tercih edilir (`reason_ids` yalnız son 5'tir, kaynak değil).
	if r.reason_id > 0:
		var exact := facade.reason(r.reason_id)
		if exact != null:
			best = exact
	record = best
	if record == null:
		reason_pruned = true
		return
	var rm := ReasonModel.from_record(record, MAX_FACTORS)
	for fr in rm.rows:
		if factors.size() >= MAX_FACTORS:
			break
		if not fr.is_info_only and fr.direction != ReasonModel.DIR_NEUTRAL:
			factors.append(fr)


func _read_reactions(facade: SimFacade) -> void:
	var ref := String(view.ref())
	var snap := facade.snapshot()
	var live: Array[GroupReactionView] = []
	for g in snap.group_reactions:
		if g.cause_refs.has(ref):
			live.append(g)
	live.sort_custom(func(a: GroupReactionView, b: GroupReactionView) -> bool:
		return a.intensity > b.intensity or (a.intensity == b.intensity and a.group.id < b.group.id))
	linked_reactions = live.slice(0, MAX_LINKED)
	# Geçmiş: bu parsele bağlı `group.reacted` olayları (en yeni önce); güncel satırı olan grup tekrarlanmaz.
	var covered := {}
	for g in linked_reactions:
		covered[g.group.ref()] = true
	var after := maxi(0, facade.last_event_seq() - EVENT_SCAN)
	var found: Array[SimEvent] = []
	for e in facade.events_since(after):
		if e.kind == SimEvent.KIND_GROUP_REACTED and e.subjects.has(ref) and not covered.has(_event_group_ref(e)):
			found.append(e)
	found.reverse()
	past_reactions = found.slice(0, MAX_PAST)


static func _event_group_ref(e: SimEvent) -> StringName:
	return e.actor.ref() if e.actor != null and e.actor.is_valid() else &""
