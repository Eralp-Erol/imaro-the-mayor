extends SceneTree
## T-043B ölçüm probu (ölçüt 4): öncelikli değerlendirme kuyruğunun tetik ve dağıtım tick maliyeti. Saf sim API'si;
## duvar
## saati yalnız ölçüm içindir (kabul kararı değildir, makineye bağlıdır). Kare bütçesi: 4 gün/sn'de bir tick bir karede
## (16,6 ms) işlenir; ölçüt = tetik ve kuyruk tick'leri bu bütçeyi (taban tick ile birlikte) aşmaz.
## Çalıştır: godot --headless --path . --script res://tests/sim/perf/t043b_priority_trigger_probe.gd
## Senaryo: oynanabilir ölçekte dünya (YOLA UZAK `FILLER` plansız boş parsel + yola yakın planlı parseller), 4 plan
## komutu
## (her biri `PLAN_PARCELS` yakın parsel), 40 gün sonra yol. Tick süreleri: taban (yol öncesi), tetik tick'i (komut +
## onay),
## kuyruk tick'leri (vade ve dağıtım).

const E := preload("res://tests/sim/economy/economy_priority_support.gd")
const FILLER := 10000
const REPEATS := 3
const BASE_TICKS := 30
const AFTER_TICKS := 12
const BUDGET_MS := 16.6


func _init() -> void:
	var out := {"task": "T-043B", "filler_parcels": FILLER, "queue_k": 0, "runs": []}
	var worst := 0.0
	for queue_on in [true, false]:  # kuyruk kapalı = aynı senaryoda yol komutu/ağ maliyeti (kuyruğun payı farktır)
		for rep in REPEATS:
			var patch := {"decision": {"max_reviews_per_tick": 8, "priority_review_enabled": 1 if queue_on else 0}}
			var run := E.setup(patch, 20261030 + rep, FILLER)
			var f := E.f(run)
			out["queue_k"] = (run["handle"] as EconomyHandle).config.p("priority_max_parcels")
			E.plan(f, E.NEAR_A)
			f.advance(40 - BASE_TICKS)
			var base: Array[float] = []
			for _day in BASE_TICKS:
				base.append(_tick_ms(f))
			E.road_a(f)
			var after: Array[float] = []
			for _day in AFTER_TICKS:
				after.append(_tick_ms(f))
			var sorted_base := base.duplicate()
			sorted_base.sort()
			var entry := {
				"queue": queue_on, "base_median_ms": _r(sorted_base[sorted_base.size() / 2]),
				"base_max_ms": _r(sorted_base.max()), "trigger_tick_ms": _r(after[0]),
				"after_ticks_ms": after.map(func(v: float) -> float: return _r(v)), "after_max_ms": _r(after.max()),
				"queue_left": E.queue(f).size(), "approvals": E.approvals(f),
			}
			out["runs"].append(entry)
			if queue_on:
				worst = maxf(worst, maxf(float(entry["after_max_ms"]), float(entry["base_max_ms"])))
	print("T043B_PERF ", JSON.stringify(out))
	print("T043B_PERF worst_tick_ms(queue on)=%.2f budget_ms=%.1f %s" % [worst, BUDGET_MS,
		"WITHIN" if worst <= BUDGET_MS else "OVER"])
	quit()


func _r(v: float) -> float:
	return snappedf(v, 0.01)


func _tick_ms(f: SimFacadeImpl) -> float:
	var t0 := Time.get_ticks_usec()
	f.advance(1)
	return float(Time.get_ticks_usec() - t0) / 1000.0
