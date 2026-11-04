extends SceneTree
## T-045 ölçüm probu: değişen-parsel halkasının tick başına ek maliyeti ve `parcel_changes_since` sorgu maliyeti.
## Saf sim API'si; duvar saati yalnız ölçüm içindir (kabul kararı değildir, makineye bağlıdır).
## Çalıştır: godot --headless --path . --script res://tests/sim/perf/t045_change_feed_probe.gd

const E := preload("res://tests/sim/economy/economy_test_support.gd")
const P := preload("res://tests/sim/parcel_changes_test.gd")
const PARCELS := 10000
const DAYS := 120
const REPEATS := 3
const NOTE_CALLS := 2000000


## Halkayı devre dışı bırakan eşdeğer (yalnız A/B ölçümü için): aynı sim, `note`/`begin_tick` yapmaz.
class NullLog:
	extends ParcelChangeLog

	func begin_tick(_tick: int) -> void:
		pass

	func note(_parcel_id: int) -> void:
		pass


func _init() -> void:
	var out := {"task": "T-045", "parcels": PARCELS, "days": DAYS}
	var with_ring := []
	var without_ring := []
	var changes_per_tick := 0
	var peak_changes := 0
	for rep in REPEATS:
		for ring_on in [true, false]:
			var h := E.synthetic_handle(PARCELS, 2, P.LOAD_PATCH)
			if not ring_on:
				h.system._changes = NullLog.new()
			var total := 0
			var changed_total := 0
			for _day in DAYS:
				var t0 := Time.get_ticks_usec()
				h.facade.advance(1)
				total += Time.get_ticks_usec() - t0
				if ring_on and rep == 0:
					var n := h.system.change_log().ids_since(h.facade.current_tick() - 1).size()
					changed_total += n
					peak_changes = maxi(peak_changes, n)
			(with_ring if ring_on else without_ring).append(float(total) / DAYS)
			if ring_on and rep == 0:
				changes_per_tick = changed_total / DAYS
	with_ring.sort()
	without_ring.sort()
	out["tick_us_with_ring_median"] = with_ring[REPEATS / 2]
	out["tick_us_without_ring_median"] = without_ring[REPEATS / 2]
	out["tick_overhead_us_median_ab"] = with_ring[REPEATS / 2] - without_ring[REPEATS / 2]
	out["changes_per_tick_avg"] = changes_per_tick
	out["changes_per_tick_peak"] = peak_changes
	# Mikro ölçüm: note() çağrısı başına maliyet ve tick başına (tepe değişim sayısı kadar not + begin_tick).
	var log := ParcelChangeLog.new(512)
	var t1 := Time.get_ticks_usec()
	for k in NOTE_CALLS:
		if k % 64 == 0:
			log.begin_tick(k / 64)
		log.note(k % 9973)
	var note_us := float(Time.get_ticks_usec() - t1) / NOTE_CALLS
	out["note_us_per_call_incl_begin_tick_amortized"] = note_us
	out["note_ms_per_tick_at_peak_changes"] = note_us * peak_changes / 1000.0
	# Sorgu maliyeti: son tick'in değişimleri ve tüm pencere (10k parsel dünyası).
	var q := E.synthetic_handle(PARCELS, 2, P.LOAD_PATCH).facade
	q.advance(DAYS)
	var q_one := _time_query(q, q.current_tick() - 1)
	var q_window := _time_query(q, q.current_tick() - 512 if q.current_tick() > 512 else -1)
	out["query_last_tick_ms"] = q_one["ms"]
	out["query_last_tick_ids"] = q_one["ids"]
	out["query_all_history_ms"] = q_window["ms"]
	out["query_all_history_ids"] = q_window["ids"]
	DirAccess.make_dir_recursive_absolute("res://artifacts/verify")
	var file := FileAccess.open("res://artifacts/verify/t045-perf.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(out, "\t") + "\n")
		file.close()
	print("T045_PERF ", JSON.stringify(out))
	quit(0)


func _time_query(f: SimFacadeImpl, since: int) -> Dictionary:
	var best := 1.0e12
	var ids := 0
	for _i in 20:
		var t := Time.get_ticks_usec()
		var feed := f.parcel_changes_since(since)
		best = minf(best, float(Time.get_ticks_usec() - t) / 1000.0)
		ids = feed.ids.size()
	return {"ms": best, "ids": ids}
