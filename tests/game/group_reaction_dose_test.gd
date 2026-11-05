extends GdUnitTestSuite
## B-130 / D-026 (sahip Q-040 "A") · GERÇEK Ismeral D2'de belediye kararından sonra ikinci halk grubu da tepki verir,
## ama yalnız yoğun yol yapımında: karar yokken (taban) ve tek bir yolda tepki OLMAZ (tepki karara bağlı kalır).
## Başsız, sahnesiz; kurulum `tests/sim/perf/qa_world_support.gd` (oyunun siyaset/ekonomi yapılandırması + gerçek
## kamulaştırma köprüsü; `tools/godot/group_reaction_probe.gd` ölçümünün aynısı). Eşik VERİDE
## (`data/actors/decision_tables.json` `bloc.react`); bu dosya sayı içermez, yalnız davranışı kilitler.
## Tepki = `group.reacted` olayı (nötr değil: `event.group.calmed` DEĞİL) ya da günlük taranan nötr olmayan
## `GroupReactionView`. SIM-12: her tepki olayının gerekçe kaydı var, olumlu `decision.bloc.react.*`, tutarlı ve
## o kesime ait. Yavaş suite (gerçek dünya ~90 sn + ~5 sim koşusu): `tools/verify-areas.tsv` `slow` listesinde.

const Q := preload("res://tests/sim/perf/qa_world_support.gd")
const REGION := "D2"
const NEAR_M := 150.0
const PLAN_N := 12
const STRESS_ROADS := 6
const DAYS := 360  # 1 oyun yılı: taban sürüklenmesi (konut talebi açığı) dahil; tepki yine karara bağlı kalmalı
const WARM_DAYS := 30
const POOL := 150
const BLOC_HOUSED := "actor.bloc.1"
const BLOC_SEEKING := "actor.bloc.2"
const CALMED := "event.group.calmed"

static var _w: Q.WorldCtx = null
static var _plan: Dictionary = {}


static func _world() -> Q.WorldCtx:
	if _w == null:
		_w = Q.build_world(int(WorldControlData.load_dir(Q.DATA_DIR)["world"]["default_seed"]))
		_plan = _build_plan(_w)
	return _w


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Probe ile aynı seçim: hane sayısına göre artan adaylar; tek yol = q90, doz = en çok hane yerinden eden 6 yol.
static func _build_plan(w: Q.WorldCtx) -> Dictionary:
	var s0 := Q.new_sim(w, 1)
	s0.step(WARM_DAYS)
	var cands := Q.region_candidates(w, s0, REGION, POOL, "t067_queue_probe")
	cands = cands.filter(func(c: Dictionary) -> bool: return int(c["hh"]) > 0)
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["hh"]) != int(y["hh"]):
			return int(x["hh"]) < int(y["hh"])
		return int(x["order"]) < int(y["order"]))
	var cand: Dictionary = cands[mini(cands.size() - 1, cands.size() * 9 / 10)]
	var pts: PackedVector2Array = cand["pts"]
	var taken := {}
	for pid in RoadDraftCheck.taken_parcels(w.net, pts, RoadDrawTool.ROAD_CLASS):
		taken[int(pid)] = true
	var occupied := {}
	for pid in w.settlement.columns.occupied_parcels():
		occupied[int(pid)] = true
	var scored: Array = []
	for v in w.views:
		if occupied.has(v.id) or taken.has(v.id):
			continue
		var d := _dist_to_segment(v.center, pts[0], pts[pts.size() - 1])
		if d <= NEAR_M * 2.0:
			scored.append([d, v.id])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var plan_ids := PackedInt64Array()
	for k in mini(PLAN_N, scored.size()):
		plan_ids.append(int(scored[k][1]))
	var stress: Array = []
	for k in STRESS_ROADS:
		stress.append((cands[cands.size() - 1 - k] as Dictionary)["cm"])
	return {"road": cand["cm"], "plan_ids": plan_ids, "stress": stress}


## Senaryo: "base" (karar yok), "road" (tek kamulaştırmalı yol, 1. gün), "stress" (6 yol 1-6. gün + imar 8. gün).
## Dönüş: {grups: {kesim: {events: [satır], view_nonneutral: bool}}, hh_events: n}; ağ taban grafına döndürülür.
func _run(kind: String, sim_seed: int, days: int = DAYS) -> Dictionary:
	var w := _world()
	var s := Q.new_sim(w, sim_seed)
	assert_object(s).override_failure_message("sim kurulamadı").is_not_null()
	s.step(WARM_DAYS)
	var groups := {}
	var roads_built := 0
	for d in range(1, days + 1):
		if kind == "road" and d == 1:
			roads_built += 1 if not s.facade.submit_command(
					SimCommand.public_work_road(_plan["road"], RoadDrawTool.ROAD_CLASS, true)).is_rejected() else 0
		if kind == "stress" and d <= STRESS_ROADS:
			roads_built += 1 if not s.facade.submit_command(SimCommand.public_work_road(
					(_plan["stress"] as Array)[d - 1], RoadDrawTool.ROAD_CLASS, true)).is_rejected() else 0
		if kind == "stress" and d == 8:
			s.facade.submit_command(SimCommand.zoning_propose(_plan["plan_ids"], &"zone.residential"))
		var seq0 := s.seen_event_seq
		s.step(1)
		for e in s.facade.events_since(seq0):
			if String(e.kind) == "group.reacted" and e.actor != null:
				var g: Dictionary = groups.get(String(e.actor.ref()), {"events": [], "view_nonneutral": false})
				(g["events"] as Array).append(_event_row(s, e))
				groups[String(e.actor.ref())] = g
		for gv in PoliticsQuery.group_views(s.facade.game_state()):
			if gv.group == null:
				continue
			var gk := String(gv.group.ref())
			var g2: Dictionary = groups.get(gk, {"events": [], "view_nonneutral": false})
			if String(gv.reaction) != "neutral" or gv.intensity > 0:
				g2["view_nonneutral"] = true
			groups[gk] = g2
	var restored := false
	var guard := 0
	while not w.net.delta.ops.is_empty() and guard < 12:
		if not bool(s.ctx.undo_live_op()["ok"]):
			break
		guard += 1
	restored = w.net.graph_hash() == w.base_hash
	assert_bool(restored).override_failure_message("ağ taban grafına dönmedi (%s)" % kind).is_true()
	return {"groups": groups, "roads": roads_built, "hash": s.facade.state_hash()}


## Olayın gerekçesi karar anında okunur (ReasonLog sınırlı süre tutar, B-027).
func _event_row(s: Q.SimCtx, e: SimEvent) -> Dictionary:
	var rows: Array = []
	for rid in e.reason_ids:
		var rec := s.facade.reason(int(rid))
		if rec != null:
			rows.append({"decision": String(rec.decision_key), "outcome": String(rec.outcome), "consistent": rec.is_consistent(),
				"actor": String(rec.actor.ref()) if rec.actor != null else "", "score": rec.score, "threshold": rec.threshold})
	return {"tick": e.tick, "message": String(e.message_key), "reason_n": e.reason_ids.size(), "reasons": rows}


static func _nonneutral_events(g: Dictionary) -> Array:
	return (g.get("events", []) as Array).filter(func(r: Dictionary) -> bool: return String(r["message"]) != CALMED)


## Tepki gösteren kesimler: nötr olmayan `group.reacted` olayı VEYA nötr olmayan görünüm.
static func _reacting(groups: Dictionary) -> Array:
	var out: Array = []
	for gk: String in groups:
		var g: Dictionary = groups[gk]
		if not _nonneutral_events(g).is_empty() or bool(g["view_nonneutral"]):
			out.append(gk)
	out.sort()
	return out


# --- 1) Doz testi: yoğun yol yapımı -> konut arayanlar da dilekçe/protesto verir, gerekçesi var --------------------

func test_heavy_road_building_makes_the_housing_seekers_bloc_react_with_a_reason_record() -> void:
	for sim_seed in [1, 2]:
		var r := _run("stress", sim_seed)
		assert_int(int(r["roads"])).override_failure_message("doz yolları kabul edilmedi (tohum %d)" % sim_seed) \
				.is_equal(STRESS_ROADS)
		var groups: Dictionary = r["groups"]
		assert_bool(groups.has(BLOC_SEEKING)).override_failure_message("kesim görünümü yok").is_true()
		var evs := _nonneutral_events(groups[BLOC_SEEKING])
		assert_int(evs.size()).override_failure_message(
				"tohum %d: konut arayanlar ağır yol yapımından sonra tepki vermedi (group.reacted yok)" % sim_seed) \
				.is_greater(0)
		assert_bool(bool(groups[BLOC_SEEKING]["view_nonneutral"])).override_failure_message(
				"tohum %d: GroupReactionView nötr kaldı" % sim_seed).is_true()
		for row: Dictionary in evs:  # SIM-12: gerekçe kaydı var, olumlu tepki kararı, tutarlı, bu kesime ait
			assert_int(int(row["reason_n"])).override_failure_message("tepki olayı gerekçesiz").is_greater(0)
			var react: Array = (row["reasons"] as Array).filter(func(x: Dictionary) -> bool:
				return String(x["decision"]).begins_with("decision.bloc.react.") and String(x["outcome"]) == "positive")
			assert_array(react).override_failure_message("olumlu decision.bloc.react.* kaydı yok: %s" % [row]).is_not_empty()
			for x: Dictionary in react:
				assert_bool(bool(x["consistent"])).is_true()
				assert_str(String(x["actor"])).is_equal(BLOC_SEEKING)
				assert_int(int(x["score"])).is_greater_equal(int(x["threshold"]))


## NOT (B-130, D-026): ">= 2 farklı grup `group.reacted`" VERİ-YALNIZ ile ulaşılamaz: barınanlar (`actor.bloc.1`) doz
## testinde bile 31-71 puan alır, taban/tek yolda 8-42 (örtüşür): global eşik onları karara bağlı ayıramaz. Barınanların
## karara bağlı tepkisi şimdilik gündem öğesi PE-01 + haber (grup tepkisi sayılmaz). Açık: Q-040 notu / B-130.


# --- 2) Karara bağlılık: taban ve tek yol konut arayanları tepkiye geçirmez -----------------------------------------

func test_no_decision_baseline_does_not_trigger_the_housing_seekers_reaction() -> void:
	var groups: Dictionary = _run("base", 1)["groups"]
	assert_bool(groups.has(BLOC_SEEKING)).is_true()
	assert_array(_nonneutral_events(groups[BLOC_SEEKING])).override_failure_message(
			"karar yokken konut arayanlar tepki verdi (kendiliğinden gürültü, karara bağlı değil)").is_empty()
	assert_bool(bool(groups[BLOC_SEEKING]["view_nonneutral"])).is_false()
	assert_array(_reacting(groups)).is_empty()


func test_a_single_road_does_not_trigger_the_housing_seekers_reaction() -> void:
	var r := _run("road", 1)
	assert_int(int(r["roads"])).is_equal(1)
	var groups: Dictionary = r["groups"]
	assert_array(_nonneutral_events(groups[BLOC_SEEKING])).override_failure_message(
			"tek yol konut arayanları tepkiye geçirdi").is_empty()
	assert_bool(bool(groups[BLOC_SEEKING]["view_nonneutral"])).is_false()


# --- 3) Negatif: yoğun yolda bile barınanlar ve taban sabit/deterministik -------------------------------------------

func test_same_seed_and_commands_give_the_same_reaction_and_hash() -> void:
	var a := _run("stress", 1, 60)
	var b := _run("stress", 1, 60)
	assert_str(String(a["hash"])).is_equal(String(b["hash"]))
	assert_array(_reacting(a["groups"])).is_equal(_reacting(b["groups"]))
