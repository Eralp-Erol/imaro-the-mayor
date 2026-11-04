extends SceneTree
## QA T-040 2. tur (B-001): VARSAYILAN otonom rejimde (review_enabled=1) "Döngü sonucu" modeli, gerçek Ismeral dünyası.
## Bağımsız kâhin: her sim günü takip edilen parsellerin `reasons_for` kayıtları okunur ve budanmadan ÖNCE saklanır
## (ParcelView.decision* alanlarına bakılmadan). Model (M2ResultModel) ve ParcelView kâhinle karşılaştırılır.
## Kümeler: fresh (gün 2'de önerilen 8 taze D1 parseli), prior (gün 30'da otonom reddi OLAN 8 boş parsel),
## same (gün 30'da TAM O tick'te reddedilmiş boş parseller: öneri anında zaten verilmiş karar = öneri öncesi).

const QW := preload("qa_world.gd")
const DEVELOP := &"decision.investor.develop"

var fails := 0
## parsel -> Array[{id, tick, positive}] (gün gün yakalanan develop kayıtları, tekrarsız)
var oracle := {}


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("QA2_B001 FAIL ", what)


func _capture(f: SimFacade, ids: PackedInt64Array) -> void:
	for pid in ids:
		var arr: Array = oracle.get(int(pid), [])
		var seen := {}
		for e in arr:
			seen[int(e["id"])] = true
		for rec in f.reasons_for(SimContract.parcel_ref(int(pid))):
			if rec.decision_key != DEVELOP or seen.has(rec.id):
				continue
			arr.append({"id": rec.id, "tick": rec.tick, "positive": rec.outcome == ReasonRecord.OUTCOME_POSITIVE})
		oracle[int(pid)] = arr


## Kâhine göre öneri SONRASI (tick > submit_tick) son karar: 1 onay, -1 ret, 0 yok.
func _post(pid: int, submit_tick: int) -> Dictionary:
	var last := {}
	for e in oracle.get(pid, []):
		if int(e["tick"]) > submit_tick:
			last = e
	return last


func _compare(f: SimFacade, label: String, ids: PackedInt64Array, submit_tick: int, base: EconomyOutcomeView) -> void:
	var results_tick := submit_tick   # playable: track_parcels(submitted_tick = current_tick at submit)
	var m := M2ResultModel.build(f, ids, base, submit_tick, results_tick)
	var c := m.counts_decided()
	var exp := {"approved": 0, "declined": 0, "waiting": 0}
	var pruned := 0
	var with_btn := 0
	var dev_none := 0
	for row in m.parcels:
		var pid := row.id()
		var post := _post(pid, submit_tick)
		if post.is_empty():
			exp["waiting"] += 1
		elif bool(post["positive"]):
			exp["approved"] += 1
		else:
			exp["declined"] += 1
		var v := row.view
		if v.developed_by_sim and row.recorded != M2ResultModel.Decision.APPROVED:
			dev_none += 1
		# Kayıtlı kararın (öneri öncesi dahil) kâhindeki son develop kaydıyla eşleşmesi
		if row.recorded != M2ResultModel.Decision.NONE:
			var match_rec := {}
			for e in oracle.get(pid, []):
				if int(e["tick"]) == row.tick:
					match_rec = e
			_check(not match_rec.is_empty(), "%s p%d karar tick %d kâhinde yok" % [label, pid, row.tick])
			if not match_rec.is_empty():
				_check(bool(match_rec["positive"]) == (row.recorded == M2ResultModel.Decision.APPROVED),
						"%s p%d karar yönü kâhinle farklı" % [label, pid])
				var alive := f.reason(int(match_rec["id"])) != null
				if row.reason_id > 0:
					with_btn += 1
					_check(row.reason_id == int(match_rec["id"]), "%s p%d reason_id %d != kâhin %d" % [label, pid,
							row.reason_id, int(match_rec["id"])])
					_check(alive, "%s p%d reason_id var ama kayıt yok" % [label, pid])
				else:
					pruned += 1
					_check(not alive, "%s p%d 'budandı' diyor ama kayıt %d hâlâ var" % [label, pid, int(match_rec["id"])])
			if row.recorded == M2ResultModel.Decision.DECLINED:
				_check(row.cause != &"" and row.cause != M2ResultModel.CAUSE_UNKNOWN, "%s p%d ret nedeni '%s' (kod %s)" % [
						label, pid, row.cause, row.code])
		elif not oracle.get(pid, []).is_empty():
			# Model kayıt yok diyor: kâhinde kayıt varsa bu yalnız imar sıfırlamasıyla açıklanabilir (vacant + karar sıfırlandı)
			var last: Dictionary = oracle[pid][oracle[pid].size() - 1]
			_check(v.development == ParcelView.DEVELOPMENT_VACANT and not bool(last["positive"]) and int(last["tick"]) <= submit_tick + 1,
					"%s p%d model 'karar yok' ama kâhinde son kayıt tick %d positive=%s dev=%s" % [label, pid,
					int(last["tick"]), last["positive"], v.development])
	_check(c == exp, "%s sayım model=%s kâhin=%s" % [label, c, exp])
	_check(dev_none == 0, "%s sim-geliştirilmiş ama karar 'onay' değil: %d" % [label, dev_none])
	print("QA2_B001 %s tick=%d n=%d model=%s oracle=%s pruned=%d with_button=%d log_first_seq=%d" % [label, f.current_tick(),
			m.parcels.size(), c, exp, pruned, with_btn, f.first_retained_event_seq()])


func _initialize() -> void:
	var t0: Dictionary = QW.base()["t0"]
	var h: PoliticsHandle = QW.handle()
	var f: SimFacade = h.facade
	var proj: SimBuildingProjector = QW.projector(f)
	f.advance(2)
	var fresh := PackedInt64Array()
	for pid in f.parcel_ids(&"D1"):
		if fresh.size() >= 8:
			break
		if t0.has(int(pid)) or not proj.placer().can_place(int(pid), &"residential", 3):
			continue
		var v0 := f.parcel_views(PackedInt64Array([pid]))[0]
		if v0.development != ParcelView.DEVELOPMENT_VACANT or v0.pending_zone != &"":
			continue
		fresh.append(int(pid))
	_capture(f, fresh)
	var fresh_tick := f.current_tick()
	var fresh_base := f.economy_outcome()
	print("QA2_B001 fresh submit tick=%d %s ids=%s" % [fresh_tick, f.submit_command(SimCommand.zoning_propose(fresh, &"zone.mixed")).status, fresh])
	var prior := PackedInt64Array()
	var same := PackedInt64Array()
	var prior_tick := -1
	var prior_base: EconomyOutcomeView = null
	var all := fresh.duplicate()
	for day in range(3, 181):
		f.advance(1)
		_capture(f, all)
		var tick := f.current_tick()
		if tick == 30:
			# Bu tick'te değişen parseller (feed) + tüm parseller arasından öneri öncesi retli boş parseller.
			var changed := f.parcel_changes_since(tick - 1)
			for v in f.parcel_views(changed.ids):
				if same.size() >= 8:
					break
				if t0.has(v.id) or v.development != ParcelView.DEVELOPMENT_VACANT or v.pending_zone != &"":
					continue
				if v.decision == ParcelView.DECISION_DECLINED and v.decision_tick == tick and not fresh.has(v.id):
					same.append(v.id)
			for pid in f.parcel_ids():
				if prior.size() >= 8:
					break
				if t0.has(int(pid)) or fresh.has(int(pid)) or same.has(int(pid)):
					continue
				var v := f.parcel_views(PackedInt64Array([pid]))[0]
				if v.development != ParcelView.DEVELOPMENT_VACANT or v.pending_zone != &"":
					continue
				if v.decision == ParcelView.DECISION_DECLINED and v.decision_tick < tick:
					prior.append(int(pid))
			all.append_array(prior)
			all.append_array(same)
			_capture(f, all)
			prior_tick = tick
			prior_base = f.economy_outcome()
			var r1 := f.submit_command(SimCommand.zoning_propose(prior, &"zone.mixed"))
			var r2 := f.submit_command(SimCommand.zoning_propose(same, &"zone.mixed"))
			print("QA2_B001 prior/same submit tick=%d prior=%s (%s) same=%s (%s) cmd.tick=%d/%d" % [tick, prior, r1.status,
					same, r2.status, r1.tick, r2.tick])
			# Öneri ANINDA: yatırımcı öneriyi değerlendirmedi -> hepsi kararsız olmalı
			_compare(f, "prior@proposal", prior, prior_tick, prior_base)
			_compare(f, "same@proposal", same, prior_tick, prior_base)
		if tick in [30, 45, 60, 90, 120, 150, 180]:
			_compare(f, "fresh", fresh, fresh_tick, fresh_base)
			if prior_tick >= 0:
				_compare(f, "prior", prior, prior_tick, prior_base)
				_compare(f, "same", same, prior_tick, prior_base)
	print("QA2_B001 DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
