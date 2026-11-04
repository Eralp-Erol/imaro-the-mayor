extends SceneTree
## T-029 ölçüm probu. Saf sim API'sini kullanır; duvar saati yalnız ölçüm içindir. Çıktı, bir kabul kararı
## değildir: `scope` alanı hangi sistemlerin gerçekten kurulduğunu açıkça taşır.

const SAMPLE_SIZES := [2000, 10000, 30000]


func _init() -> void:
	var rows: Array = []
	for count in SAMPLE_SIZES:
		rows.append(_measure(count))
	var out := {"task": "T-029", "scope": "EconomyBootstrap + columnar parcel state; politics/reason volume not included",
			"samples": rows}
	DirAccess.make_dir_recursive_absolute("res://artifacts/verify")
	var file := FileAccess.open("res://artifacts/verify/t029-perf.json", FileAccess.WRITE)
	if file == null:
		push_error("T-029: artifacts/verify/t029-perf.json yazılamadı")
		quit(1)
		return
	file.store_string(JSON.stringify(out, "\t") + "\n")
	file.close()
	print("T029_PERF ", JSON.stringify(out))
	quit(0)


func _measure(count: int) -> Dictionary:
	var views: Array[ParcelView] = []
	for i in count:
		var v := ParcelView.new()
		v.id = i + 1
		v.region_code = &"D1" if i % 2 == 0 else &"D2"
		v.center = Vector2(i % 250, i / 250)
		v.area_m2 = 100
		v.zone = &"zone.residential"
		views.append(v)
	var source := ListParcelSource.create(&"t029-perf", views)
	var facade := EconomyBootstrap.create_facade(17, source)
	if facade == null:
		return {"parcels": count, "error": "EconomyBootstrap failed"}
	# Ekonomi sütunları ilk sim tick'inde kurulur; aksi halde yalnız boş başlangıç durumu ölçülmüş olur.
	facade.advance(1)
	# T-013/T-017 raporundaki hacme yakın, serileşen gerçek ReasonLog kayıtları 10k kabul örneğinde eklenir.
	# Actor/politics karar motorlarını burada taklit etmiyoruz; probun kapsam metni bunu açıkça belirtir.
	var state := facade.game_state()
	if count == 10000:
		for i in 9000:
			state.record_reason(&"actor.investor.1", &"decision.perf.probe", [{"name": &"demand", "value": 1000,
				"weight": 1000, "source_ref": &"parcel.1"}], 0, &"perf_probe", PackedStringArray(["parcel.1"]))
	# Isıtma: ilk hash'in sınıf/bytecode maliyeti ölçüme girmez.
	facade.state_hash()
	var hash_start := Time.get_ticks_usec()
	var hash := facade.state_hash()
	var hash_ms := (Time.get_ticks_usec() - hash_start) / 1000.0
	var save_start := Time.get_ticks_usec()
	var bytes := facade.export_save()
	var decoded := facade.import_save(bytes)
	var save_load_ms := (Time.get_ticks_usec() - save_start) / 1000.0
	return {"parcels": count, "reason_records": state.reasons.size(), "state_hash_ms": snappedf(hash_ms, 0.1),
			"save_load_ms": snappedf(save_load_ms, 0.1), "save_bytes": bytes.size(),
			"hash_ok": not hash.is_empty(), "load_ok": decoded.ok}
