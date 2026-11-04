extends SceneTree
## T-029 uzun-yük ölçümü. Economy + Actor + Politics aynı gerçek facade içinde iki oyun yılı yürür.
## Ölçüm saf sim API'sine girmez; duvar saati yalnız raporlama içindir.

const SAMPLE_SIZES := [2000, 10000, 30000]
const DAYS := 730


func _init() -> void:
	var rows: Array = []
	for count in SAMPLE_SIZES:
		rows.append(_measure(count))
	var out := {
		"task": "T-029",
		"scope": "PoliticsBootstrap (Economy + Actors + Politics), two game years",
		"days": DAYS,
		"samples": rows,
	}
	DirAccess.make_dir_recursive_absolute("res://artifacts/verify")
	var file := FileAccess.open("res://artifacts/verify/t029-combined-perf.json", FileAccess.WRITE)
	if file == null:
		push_error("T-029: combined artifacts yazılamadı")
		quit(1)
		return
	file.store_string(JSON.stringify(out, "\t") + "\n")
	file.close()
	print("T029_COMBINED_PERF ", JSON.stringify(out))
	quit(0)


func _measure(count: int) -> Dictionary:
	var views: Array[ParcelView] = []
	for i in count:
		var view := ParcelView.new()
		view.id = i + 1
		view.region_code = &"D1" if i % 2 == 0 else &"D2"
		view.center = Vector2(i % 250, i / 250)
		view.area_m2 = 100
		view.zone = &"zone.residential"
		views.append(view)
	var source := ListParcelSource.create(&"t029-combined", views)
	var handle := PoliticsBootstrap.create(17, source)
	if handle == null:
		return {"parcels": count, "error": "PoliticsBootstrap failed"}
	var facade := handle.facade
	var state := facade.game_state()
	var tick_start := Time.get_ticks_usec()
	facade.advance(DAYS)
	var tick_ms := (Time.get_ticks_usec() - tick_start) / 1000.0
	# İlk hash'in sınıf/bytecode maliyeti kabul ölçümüne girmez.
	facade.state_hash()
	var hash_start := Time.get_ticks_usec()
	var hash := facade.state_hash()
	var hash_ms := (Time.get_ticks_usec() - hash_start) / 1000.0
	var body := state.to_dict()
	var hash_profile := _hash_profile(body)
	var save_start := Time.get_ticks_usec()
	var bytes := facade.export_save()
	var decoded := facade.import_save(bytes)
	var save_load_ms := (Time.get_ticks_usec() - save_start) / 1000.0
	return {
		"parcels": count,
		"days": DAYS,
		"tick_total_ms": snappedf(tick_ms, 0.1),
		"tick_avg_ms": snappedf(tick_ms / DAYS, 0.1),
		"reason_records": state.reasons.size(),
		"event_count": facade.last_event_seq(),
		"state_hash_ms": snappedf(hash_ms, 0.1),
		"hash_profile_ms": hash_profile,
		"save_load_ms": snappedf(save_load_ms, 0.1),
		"save_bytes": bytes.size(),
		"hash_ok": not hash.is_empty(),
		"load_ok": decoded.ok,
	}


func _hash_profile(body: Dictionary) -> Dictionary:
	var profile := {}
	for key: String in ["reasons", "systems", "command_log", "config", "rng"]:
		var start := Time.get_ticks_usec()
		StateHash.of(body[key])
		profile[key] = snappedf((Time.get_ticks_usec() - start) / 1000.0, 0.1)
	return profile
