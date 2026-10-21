class_name SimContractChecks
extends RefCounted
## Herhangi bir SimFacade uygulamasının sözleşmeye uyumunu denetleyen saf kontroller (ADR-0005 §uyum).
## Aynı kontroller mock'a (tests/contracts) ve gerçek `SimFacadeImpl`'e (T-027, tests/sim) uygulanır.
## Her kontrol bulunan ihlalleri açıklayan satırlar döner; boş dizi = uyumlu.

## SIM-09: tek bir toplam memnuniyet/onay skoru sözleşmenin hiçbir yerinde alan olarak bulunmaz.
const FORBIDDEN_AGGREGATE_KEYS: Array[String] = [
	"happiness", "approval", "approval_rating", "satisfaction", "popularity", "mood_total", "overall_score",
]


## Tüm kontroller.
static func check_facade(facade: SimFacade) -> PackedStringArray:
	var out := PackedStringArray()
	if not SimContract.is_compatible(facade.contract_version()):
		out.append("facade contract_version %s incompatible with %s" % [facade.contract_version(), SimContract.VERSION])
	var snap := facade.snapshot()
	if snap == null:
		out.append("snapshot() returned null")
		return out
	out.append_array(check_snapshot(facade, snap))
	out.append_array(check_events(facade))
	out.append_array(check_parcels(facade, snap))
	return out


static func check_snapshot(facade: SimFacade, snap: SimSnapshot) -> PackedStringArray:
	var out := PackedStringArray()
	if snap.provenance != facade.provenance():
		out.append("snapshot provenance %s != facade %s" % [snap.provenance, facade.provenance()])
	if snap.clock.tick != facade.current_tick():
		out.append("snapshot tick %d != current_tick %d" % [snap.clock.tick, facade.current_tick()])
	if snap.last_event_seq != facade.last_event_seq():
		out.append("snapshot last_event_seq %d != %d" % [snap.last_event_seq, facade.last_event_seq()])
	var speeds := facade.available_speeds()
	if not speeds.has(SimFacade.SPEED_PAUSED) or not speeds.has(facade.speed()):
		out.append("available_speeds %s must contain PAUSED and current speed %d" % [speeds, facade.speed()])
	var seen := {}
	for g in snap.group_reactions:
		if g.group == null or not g.group.is_valid():
			out.append("group reaction without valid group ActorRef")
		elif seen.has(g.group.ref()):
			out.append("duplicate group reaction %s" % g.group.ref())
		else:
			seen[g.group.ref()] = true
	out.append_array(check_no_aggregate_score(snap.to_dict(), "snapshot"))
	return out


## Olay sırası boşluksuz/artan, kaynak tutarlı, bağlı gerekçeler çözülebilir ve tutarlı.
static func check_events(facade: SimFacade) -> PackedStringArray:
	var out := PackedStringArray()
	var events := facade.events_since(0)
	var expected_seq := facade.first_retained_event_seq()
	for e in events:
		if e.seq != expected_seq:
			out.append("event seq %d, expected %d" % [e.seq, expected_seq])
		expected_seq = e.seq + 1
		if e.provenance != facade.provenance():
			out.append("event %d provenance %s" % [e.seq, e.provenance])
		for rid in e.reason_ids:
			out.append_array(check_reason_id(facade, rid, "event %d" % e.seq))
	if not events.is_empty() and events[-1].seq != facade.last_event_seq():
		out.append("last event seq %d != last_event_seq %d" % [events[-1].seq, facade.last_event_seq()])
	return out


static func check_parcels(facade: SimFacade, snap: SimSnapshot) -> PackedStringArray:
	var out := PackedStringArray()
	var ids := facade.parcel_ids()
	if ids.size() != snap.parcel_count:
		out.append("parcel_ids size %d != snapshot parcel_count %d" % [ids.size(), snap.parcel_count])
	for i in range(1, ids.size()):
		if ids[i] <= ids[i - 1]:
			out.append("parcel_ids not strictly ascending at %d" % i)
	var views := facade.parcel_views(ids)
	out.append_array(check_parcel_projects(views))
	out.append_array(check_parcel_decisions(views))
	for p in views:
		if p.provenance != facade.provenance():
			out.append("parcel %d provenance %s" % [p.id, p.provenance])
		for rid in p.reason_ids:
			out.append_array(check_reason_id(facade, rid, "parcel %d" % p.id))
		if p.decision_reason_id > 0:
			out.append_array(check_reason_id(facade, p.decision_reason_id, "parcel %d decision" % p.id))
	return out


## v1.1: `ParcelView` proje alanlarının (`use/units/progress_pm/developed_by_sim`) aşamayla tutarlılığı.
static func check_parcel_projects(views: Array[ParcelView]) -> PackedStringArray:
	var out := PackedStringArray()
	for p in views:
		var where := "parcel %d" % p.id
		if not [ParcelView.USE_NONE, ParcelView.USE_RESIDENTIAL, ParcelView.USE_COMMERCIAL].has(p.use):
			out.append("%s use '%s' unknown" % [where, p.use])
		if p.progress_pm < 0 or p.progress_pm > ParcelView.PROGRESS_FULL:
			out.append("%s progress_pm %d outside 0..%d" % [where, p.progress_pm, ParcelView.PROGRESS_FULL])
		if p.developed_by_sim and p.development == ParcelView.DEVELOPMENT_VACANT:
			out.append("%s developed_by_sim on a vacant parcel" % where)
		match p.development:
			ParcelView.DEVELOPMENT_VACANT:
				if p.use != ParcelView.USE_NONE or p.units != 0 or p.progress_pm != 0:
					out.append("%s vacant but has project fields" % where)
			ParcelView.DEVELOPMENT_PLANNED, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION, \
					ParcelView.DEVELOPMENT_STALLED, ParcelView.DEVELOPMENT_BUILT:
				if p.use == ParcelView.USE_NONE or p.units < 1:
					out.append("%s %s without use/units" % [where, p.development])
				if p.development == ParcelView.DEVELOPMENT_PLANNED and p.progress_pm != 0:
					out.append("%s planned but progress_pm %d" % [where, p.progress_pm])
				if p.development == ParcelView.DEVELOPMENT_BUILT and p.progress_pm != ParcelView.PROGRESS_FULL:
					out.append("%s built but progress_pm %d" % [where, p.progress_pm])
				if p.development in [ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION, ParcelView.DEVELOPMENT_STALLED] \
						and p.progress_pm >= ParcelView.PROGRESS_FULL:
					out.append("%s under construction but progress_pm %d" % [where, p.progress_pm])
			_:
				out.append("%s unknown development '%s'" % [where, p.development])
	return out


## v1.2: `ParcelView.decision*` alanlarının birbiriyle ve aşamayla tutarlılığı. `decision_reason_id` > 0 ise
## çözülebilirliği `check_parcels` (facade ile) denetler; budanmış gerekçe 0 olarak GEÇERLİDİR.
static func check_parcel_decisions(views: Array[ParcelView]) -> PackedStringArray:
	var out := PackedStringArray()
	for p in views:
		var where := "parcel %d" % p.id
		if p.decision_reason_id < 0:
			out.append("%s decision_reason_id %d negative" % [where, p.decision_reason_id])
		match p.decision:
			ParcelView.DECISION_NONE:
				if p.decision_code != &"" or p.decision_tick != -1 or p.decision_reason_id != 0:
					out.append("%s no decision but code/tick/reason set" % where)
			ParcelView.DECISION_APPROVED:
				if p.decision_code != &"approved":
					out.append("%s approved with code '%s'" % [where, p.decision_code])
				if p.development == ParcelView.DEVELOPMENT_VACANT:
					out.append("%s approved but vacant" % where)
			ParcelView.DECISION_DECLINED:
				if p.decision_code == &"" or p.decision_code == &"approved":
					out.append("%s declined with code '%s'" % [where, p.decision_code])
				if p.development != ParcelView.DEVELOPMENT_VACANT:
					out.append("%s declined but %s" % [where, p.development])
			_:
				out.append("%s unknown decision '%s'" % [where, p.decision])
		if p.decision != ParcelView.DECISION_NONE and p.decision_tick < 0:
			out.append("%s decision without tick" % where)
	return out


static func check_reason_id(facade: SimFacade, reason_id: int, where: String) -> PackedStringArray:
	var out := PackedStringArray()
	var r := facade.reason(reason_id)
	if r == null:
		out.append("%s references missing reason %d" % [where, reason_id])
		return out
	if not r.is_consistent():
		out.append("reason %d inconsistent: %s" % [reason_id, r.consistency_error()])
	if r.provenance != facade.provenance():
		out.append("reason %d provenance %s" % [reason_id, r.provenance])
	for pid in r.parent_ids:
		if pid >= reason_id or facade.reason(pid) == null:
			out.append("reason %d has invalid parent %d" % [reason_id, pid])
	return out


## Sözlük ağacında yasak toplam-skor anahtarı var mı (SIM-09)?
static func check_no_aggregate_score(value: Variant, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Dictionary:
		for k: Variant in value:
			if FORBIDDEN_AGGREGATE_KEYS.has(str(k).to_lower()):
				out.append("%s.%s: single aggregate score field is forbidden (SIM-09)" % [path, k])
			out.append_array(check_no_aggregate_score(value[k], "%s.%s" % [path, k]))
	elif value is Array:
		for i in (value as Array).size():
			out.append_array(check_no_aggregate_score(value[i], "%s[%d]" % [path, i]))
	return out


## Facade'ın dışarıdan gözlenebilir durumunun kanonik sözlüğü (hash/karşılaştırma için; her uygulamada aynı).
static func observable_state(facade: SimFacade) -> Dictionary:
	var events := facade.events_since(0)
	var reason_ids := {}
	for e in events:
		for rid in e.reason_ids:
			reason_ids[rid] = true
	var parcels := facade.parcel_views(facade.parcel_ids())
	for p in parcels:
		for rid in p.reason_ids:
			reason_ids[rid] = true
	var sorted_ids: Array = reason_ids.keys()
	sorted_ids.sort()
	var reasons: Array = []
	for rid: int in sorted_ids:
		var r := facade.reason(rid)
		reasons.append(null if r == null else r.to_dict())
	return {
		"snapshot": facade.snapshot().to_dict(), "parcels": SimDto.dicts_of(parcels),
		"events": SimDto.dicts_of(events), "reasons": reasons,
	}
