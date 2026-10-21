extends SceneTree
## QA T-040 (e): CAN-03 kötü niyetli komut yolları + duraklatma (M2RenderSupport küçük gerçek dünya, izole rejim).

var fails := 0


func check(ok: bool, label: String) -> void:
	print("QA_CAN03 %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _initialize() -> void:
	var h := M2RenderSupport.handle(M2RenderSupport.ISOLATE)
	var f: SimFacadeImpl = h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, 4, false)
	f.advance(2)
	var forged := [
		SimCommand.make(&"zoning.propose", {"parcel_ids": ids, "land_use": &"zone.mixed", "develop": true}),
		SimCommand.make(&"zoning.propose", {"parcel_ids": ids, "land_use": &"zone.mixed", "units": 40}),
		SimCommand.make(&"building.place", {"parcel_ids": ids, "module": 3}),
		SimCommand.make(&"parcel.develop", {"parcel_ids": ids}),
		SimCommand.make(&"budget.propose", {"lines": {&"budget.line.construction": 999999}}),
		SimCommand.make(&"zoning.propose", {"parcel_ids": ids, "land_use": &"zone.mixed", "density": -5}),
	]
	for c in forged:
		var r := f.submit_command(c)
		print("QA_CAN03 cmd kind=%s params=%s -> %s %s" % [c.kind, c.params.keys(), r.status, r.reason_key])
	f.advance(10)
	proj.sync(true)
	# Hiçbir zoning kabul edildiyse yapı yalnız yatırımcı kararından doğmalı
	var rows_now := proj.columns().count
	var rows_without_decision := 0
	for pid in proj.parcel_ids():
		var has_dec := false
		for r in f.reasons_for(SimContract.parcel_ref(int(pid))):
			if r.decision_key == &"decision.investor.develop" and r.outcome == ReasonRecord.OUTCOME_POSITIVE:
				has_dec = true
		if not has_dec:
			rows_without_decision += 1
	print("QA_CAN03 after forged commands +10d: rows=%d rows_without_investor_decision=%d" % [rows_now, rows_without_decision])
	check(rows_without_decision == 0, "no row without a positive investor decision")
	# Duraklatma: tick ilerlemez, projector kuyruğu boşaltır, satırlar değişmez
	f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
	f.advance(40)
	f.set_speed(SimFacade.SPEED_PAUSED)
	var t := f.current_tick()
	for i in 200:
		f.drive_usec(16000)
		proj.step(1200)
	var hash_a := proj.columns().state_hash()
	for i in 200:
		f.drive_usec(16000)
		proj.step(1200)
	check(f.current_tick() == t and not proj.busy() and proj.columns().state_hash() == hash_a,
			"pause: tick frozen (%d), projector drained, rows stable" % f.current_tick())
	# En yüksek hız: kare başına birden çok tick (drive_usec büyük) -> sonuç exact ile aynı
	f.set_speed(SimFacade.SPEED_FASTEST)
	for i in 300:
		f.drive_usec(100000)   # yavaş kareler (100 ms): kare başına çok tick
		proj.step(1200)
	while proj.busy():
		proj.step(1200)
	var settled := proj.columns().state_hash()
	var fresh := M2RenderSupport.projector(f)
	fresh.sync(true)
	check(settled == fresh.columns().state_hash(), "fastest speed + slow frames: settled rows == fresh exact (tick %d)" % f.current_tick())
	print("QA_DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
