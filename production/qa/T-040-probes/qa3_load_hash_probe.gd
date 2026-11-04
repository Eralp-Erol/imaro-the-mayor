extends SceneTree
## QA T-040 3. tur (B-005): gerçek playable.tscn --demo --no-smoke-save-load; N gün ilerlet, projector'ı eşitle, sim state_hash + TÜM sütunların
## satır hash'ini al; export_save -> import_save -> resync_sim_buildings_after_load; state_hash ve satır hash'i aynı mı? Süre.
## Ayrıca yüklemeden sonra M gün ilerletip, kesintisiz koşunun satır hash'iyle (aynı tohum) karşılaştırılmaz (kapsam dışı).

func _row_hash(c: BuildingColumns) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedByteArray([c.count & 255, (c.count >> 8) & 255, (c.count >> 16) & 255, 1]))
	for part: PackedByteArray in [c.parcel_id.to_byte_array(), c.module_idx.to_byte_array(), c.x.to_byte_array(),
			c.z.to_byte_array(), c.yaw.to_byte_array(), c.floors, c.wall_row, c.roof_row, c.accent_row, c.bright, c.flags, c.era]:
		if not part.is_empty():
			ctx.update(part)
	return ctx.finish().hex_encode()


func _initialize() -> void:
	var days := 120
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-days="):
			days = int(a.split("=")[1])
	var scene: Node = load("res://scenes/game/playable.tscn").instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var f: SimFacade = scene.get("_facade")
	var impl := f as SimFacadeImpl
	var proj: SimBuildingProjector = scene.get("_projector")
	f.set_speed(SimFacade.SPEED_PAUSED)
	# gün gün ilerlet; zone önerisi ver ki onay/inşaat olsun
	scene.call("_submit_demo")
	f.advance(days)
	proj.sync(true)
	var h0 := impl.state_hash()
	var r0 := _row_hash(proj.columns())
	var n0 := proj.columns().count
	var p0 := proj.parcel_ids().size()
	var bytes := impl.export_save()
	var loaded := impl.import_save(bytes)
	var t := Time.get_ticks_usec()
	scene.call("resync_sim_buildings_after_load")
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	var h1 := impl.state_hash()
	var r1 := _row_hash(proj.columns())
	# bağımsız kâhin: sıfırdan kurulmuş eşitleme (exact)
	proj.sync(true)
	var r2 := _row_hash(proj.columns())
	print("QA3_LOAD days=%d tick=%d load_ok=%s resync_ms=%.1f rows=%d->%d shown_parcels=%d->%d" % [days, impl.current_tick(), loaded.ok, ms, n0,
			proj.columns().count, p0, proj.parcel_ids().size()])
	print("QA3_LOAD state_hash before=%s after=%s equal=%s" % [h0, h1, h0 == h1])
	print("QA3_LOAD row_hash  before=%s after=%s after_exact=%s equal=%s equal_exact=%s" % [r0, r1, r2, r0 == r1, r0 == r2])
	quit(0 if (h0 == h1 and r0 == r1 and r0 == r2 and loaded.ok) else 1)
