extends SceneTree
## QA T-040: varsayılan (otonom) rejimde "Döngü sonucu" modelinin karar satırı doğruluğu.
## (1) Öneri anında, öneriden ÖNCEKİ otonom ret kaydı "vazgeçildi" sayılıyor mu?
## (2) Gerekçe günlüğü dönünce (günde ~60 karar) inşa edilmiş parselin yatırımcı kararı kayboluyor mu?

const QW := preload("qa_world.gd")


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
		fresh.append(int(pid))
	print("QA_HUDDEF fresh submit %s" % f.submit_command(SimCommand.zoning_propose(fresh, &"zone.mixed")).status)
	f.advance(28)
	# Otonom değerlendirilip reddedilmiş, hâlâ boş, yerleşebilir parseller
	var prior := PackedInt64Array()
	for pid in f.parcel_ids():
		if prior.size() >= 8:
			break
		if t0.has(int(pid)) or not proj.placer().can_place(int(pid), &"residential", 3):
			continue
		var v := f.parcel_views(PackedInt64Array([pid]))[0]
		if v.development != ParcelView.DEVELOPMENT_VACANT or v.pending_zone != &"":
			continue
		var rec := M2ResultModel.latest_investor_decision(f, int(pid))
		if rec != null and rec.outcome != ReasonRecord.OUTCOME_POSITIVE:
			prior.append(int(pid))
	var tick0 := f.current_tick()
	var r := f.submit_command(SimCommand.zoning_propose(prior, &"zone.mixed"))
	var base := f.economy_outcome()
	var m := M2ResultModel.build(f, prior, base, tick0, {})
	var c := m.counts_decided()
	var stale := 0
	for p in m.parcels:
		if p.record != null and p.record.tick < tick0:
			stale += 1
	print("QA_HUDDEF proposal tick=%d parcels=%d status=%s -> AT PROPOSAL model says approved=%d declined=%d waiting=%d (records older than proposal: %d) primary=%d primary_rec_tick=%d" % [
			tick0, prior.size(), r.status, c["approved"], c["declined"], c["waiting"], stale,
			m.primary.id() if m.primary != null else -1, m.primary.record.tick if m.primary != null and m.primary.record != null else -1])
	for day in 130:
		f.advance(1)
		if day % 10 == 9:
			var mm := M2ResultModel.build(f, prior, base, tick0, {})
			var cc := mm.counts_decided()
			var built := 0
			var uc := 0
			var none_but_developed := 0
			var stale2 := 0
			for p in mm.parcels:
				if p.view.development == ParcelView.DEVELOPMENT_BUILT:
					built += 1
				if p.view.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION or p.view.development == ParcelView.DEVELOPMENT_PLANNED:
					uc += 1
				if p.record == null and p.view.developed_by_sim:
					none_but_developed += 1
				if p.record != null and p.record.tick < tick0:
					stale2 += 1
			var fm := M2ResultModel.build(f, fresh, null, 2, {})
			var fc := fm.counts_decided()
			var fb := 0
			var fnone := 0
			for p in fm.parcels:
				if p.view.developed_by_sim:
					fb += 1
					if p.record == null:
						fnone += 1
			print("QA_HUDDEF fresh day=%d developed=%d approved=%d declined=%d waiting=%d developed_but_no_record=%d" % [f.current_tick(), fb, fc["approved"], fc["declined"], fc["waiting"], fnone])
			print("QA_HUDDEF day=%d built=%d inflight=%d model approved=%d declined=%d waiting=%d developed_but_no_decision_record=%d stale_pre_proposal=%d" % [
					f.current_tick(), built, uc, cc["approved"], cc["declined"], cc["waiting"], none_but_developed, stale2])
	quit(0)
