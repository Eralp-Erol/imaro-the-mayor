# gdlint:disable=max-line-length
extends SceneTree
## QA 2026-11-01 · GERÇEK Ismeral D2'de DOĞAL meclis RED oylaması + `vote["why"]` nedenlerinin tutarlılığı + panelde (gerçek
## sim -> `CouncilPanel` / `ReasonPanel`) hatasız görünmesi. DOĞAL = hiçbir üye duruşu/sayı değiştirilmez (`--hostile` YOK);
## oyuncunun gerçek seçimi: yol çiz + 12 parsellik plan, imar kullanımı farklı. Kurulum `qa_world_support.gd` (oyunun siyaset/
## ekonomi yapılandırması, yol yetki alanı D2). Sim/oyun kodu DEĞİŞMEZ. KOŞAN ASSERTLER vardır (çıkış 1 = en az bir `QA_FAIL`).
## Çalıştır (tek süreç ~3-8 dk):
##   tools/godot.sh --headless --path . --script res://tests/sim/perf/qa_council_reject_probe.gd -- \
##       [--world-seed=N] [--only=label] [--late-days=200] [--warm=30]
## Çıktı: `QA_COUNCIL ` + JSON satırları, `QA_FAIL`, `QA_WARN`, `QA_SUMMARY`.

const Support := preload("res://tests/sim/perf/qa_world_support.gd")
const NEAR_M := 150.0
const CANDIDATES := 600
const MIN_VACANT := 6
const FORBIDDEN := ["mutluluk", "puan", "skor", "₺", " tl"]
## Çözülme için üst sınır (oturum aralığı 14 gün; teklif gününe göre 3-16 gün).
const MAX_VOTE_DAYS := 30

var _args: Dictionary = {}
var _fails: Array = []
var _warns: Array = []
var _checks: int = 0
var _w: Support.WorldCtx = null
var _vacant: Array[ParcelView] = []
var _results: Array = []
var _det: Dictionary = {}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	UiText.reset()
	var control := WorldControlData.load_dir(Support.DATA_DIR)
	var world_seed := int(_args.get("world-seed", str(int(control["world"]["default_seed"]))))
	_w = Support.build_world(world_seed)
	var occupied := {}
	for pid in _w.settlement.columns.occupied_parcels():
		occupied[int(pid)] = true
	for v in _w.views:
		if not occupied.has(v.id):
			_vacant.append(v)
	var cands := _candidates()
	print("QA_COUNCIL ", JSON.stringify({"kind": "setup", "world_seed": world_seed, "vacant": _vacant.size(), "road_candidates": cands.size(),
		"jurisdiction": str(_w.game_jurisdiction)}))
	_check(cands.size() >= 2, "setup_has_two_road_candidates", "aday yol %d" % cands.size())
	if cands.size() < 2:
		_finish()
		return
	var scenarios: Array = [
		{"label": "green_r0", "zone": "zone.green", "rank": 0, "plan_n": 12, "sim_seed": world_seed, "late": true},
		{"label": "green_r0_repeat", "zone": "zone.green", "rank": 0, "plan_n": 12, "sim_seed": world_seed},
		{"label": "green_r1", "zone": "zone.green", "rank": 1, "plan_n": 12, "sim_seed": world_seed},
		{"label": "green_r0_s2", "zone": "zone.green", "rank": 0, "plan_n": 12, "sim_seed": 2},
		{"label": "green_r0_s3", "zone": "zone.green", "rank": 0, "plan_n": 12, "sim_seed": 3},
		{"label": "mixed_r0", "zone": "zone.mixed", "rank": 0, "plan_n": 12, "sim_seed": world_seed},
		{"label": "residential_r0", "zone": "zone.residential", "rank": 0, "plan_n": 12, "sim_seed": world_seed},
		{"label": "commercial_r0", "zone": "zone.commercial", "rank": 0, "plan_n": 12, "sim_seed": world_seed},
	]
	var only := str(_args.get("only", ""))
	for sc: Dictionary in scenarios:
		if only != "" and only != str(sc["label"]):
			continue
		_scenario(sc, cands[int(sc["rank"])])
	if _det.has("green_r0") and _det.has("green_r0_repeat"):
		_check(_det["green_r0"] == _det["green_r0_repeat"], "determinism_same_scenario_same_vote_and_hash",
			"iki koşu farklı: %s vs %s" % [str(_det["green_r0"]).left(300), str(_det["green_r0_repeat"]).left(300)])
	_finish()


# --- Senaryo ---

func _scenario(sc: Dictionary, cand: Dictionary) -> void:
	var label := str(sc["label"])
	var zone := StringName(str(sc["zone"]))
	var s := Support.new_sim(_w, int(sc["sim_seed"]))
	s.step(int(_args.get("warm", str(Support.WARM_DAYS))))
	var pts: PackedVector2Array = cand["pts"]
	var near_ids := _nearest_vacant(pts, int(sc["plan_n"]))
	var road := s.facade.submit_command(SimCommand.public_work_road(Support.points_cm(pts), RoadDrawTool.ROAD_CLASS))
	_check(road.status != CommandResult.STATUS_REJECTED, "%s road_accepted" % label, "status=%s %s" % [road.status, road.reason_key])
	s.step(1)
	var preview := s.facade.plan_preview(near_ids, zone, -1)
	_check(preview.ok and preview.council_required, "%s plan_goes_to_council" % label, "ok=%s council_required=%s parcels=%d" % [preview.ok, preview.council_required, near_ids.size()])
	var plan := s.facade.submit_command(SimCommand.zoning_propose(near_ids, zone))
	_check(plan.status == CommandResult.STATUS_QUEUED, "%s plan_queued" % label, "status=%s %s" % [plan.status, plan.reason_key])
	var t_plan := s.tick()
	var load_at_resolve := -1
	var votes: Array = []
	for _d in MAX_VOTE_DAYS:
		s.step(1)
		votes = PoliticsState.data(s.facade.game_state())["council"]["votes"]
		if not votes.is_empty() and votes[votes.size() - 1]["status"] != "pending":
			load_at_resolve = s.region_stat("D2", "infra_load_pm")
			break
	_check(votes.size() == 1 and votes[0]["status"] != "pending", "%s vote_resolved_in_time" % label, "oylama %d, durum %s" % [votes.size(), str(votes[0]["status"]) if not votes.is_empty() else "yok"])
	if votes.is_empty() or votes[0]["status"] == "pending":
		_w.restore_net(s.ctx, 1)
		return
	var vote: Dictionary = votes[0]
	var row := _verify_vote(label, s, vote, near_ids, t_plan, load_at_resolve)
	row["label"] = label
	row["zone"] = String(zone)
	row["sim_seed"] = int(sc["sim_seed"])
	row["rank"] = int(sc["rank"])
	row["road_len_m"] = snappedf(float(cand["len"]), 0.1)
	_det[label] = {"why": vote.get("why", {}), "yes": vote["yes"], "no": vote["no"], "status": vote["status"], "hash": s.facade.state_hash()}
	row["state_hash"] = _det[label]["hash"]
	_ui_checks(label, s, vote, row)
	if bool(sc.get("late", false)):
		_late_checks(label, s, vote, row)
	_check(_w.restore_net(s.ctx, 1), "%s net_restored" % label, "ağ özeti tabana dönmedi")
	_results.append(row)
	print("QA_COUNCIL ", JSON.stringify(row))


## Çözülen oylamanın sim kaydını bağımsız yeniden hesapla ve `why` ile karşılaştır.
func _verify_vote(label: String, s: Support.SimCtx, vote: Dictionary, near_ids: PackedInt64Array, t_plan: int, load_at_resolve: int) -> Dictionary:
	var failed: bool = vote["status"] == "failed"
	var why: Dictionary = vote.get("why", {})
	_check(not why.is_empty(), "%s vote_has_why_record" % label, "vote[\"why\"] boş (unplanned_land_enabled bayrağı?)")
	var members: Array = vote["positions"]
	var recomputed_net := {}
	var recomputed_for := {}
	var recomputed_against := {}
	var score_sum := 0
	var yes_n := 0
	var no_n := 0
	var member_rows: Array = []
	for pos: Dictionary in members:
		var rec := s.facade.reason(int(pos["reason_id"]))
		_check(rec != null, "%s member_reason_%s_retained" % [label, pos["member"]], "gerekçe kaydı yok (id %d)" % int(pos["reason_id"]))
		if rec == null:
			continue
		score_sum += rec.score
		var positive := rec.score >= rec.threshold
		_check((String(pos["position"]) == "yes") == positive, "%s position_matches_score_%s" % [label, pos["member"]], "oy %s, skor %d eşik %d" % [pos["position"], rec.score, rec.threshold])
		yes_n += 1 if String(pos["position"]) == "yes" else 0
		no_n += 1 if String(pos["position"]) == "no" else 0
		var facs := {}
		for fx in rec.factors:
			var key := String(fx.name_key)
			var c := fx.contribution()
			facs[key] = c
			recomputed_net[key] = int(recomputed_net.get(key, 0)) + c
			if c > 0:
				recomputed_for[key] = int(recomputed_for.get(key, 0)) + 1
			elif c < 0:
				recomputed_against[key] = int(recomputed_against.get(key, 0)) + 1
		member_rows.append({"member": String(pos["member"]), "pos": String(pos["position"]), "score": rec.score, "factors": facs})
	_check(yes_n == int(vote["yes"]) and no_n == int(vote["no"]), "%s tally_matches_positions" % label, "kayıt %d-%d, pozisyonlardan %d-%d" % [vote["yes"], vote["no"], yes_n, no_n])
	_check((vote["status"] == "passed") == (int(vote["yes"]) > int(vote["no"])), "%s status_matches_tally_tie_fails" % label, "durum %s, %d-%d" % [vote["status"], vote["yes"], vote["no"]])
	if why.is_empty():
		return {"status": String(vote["status"]), "yes": vote["yes"], "no": vote["no"], "members": member_rows}
	_check(int(why["members"]) == members.size(), "%s why_members_equals_seats" % label, "why.members %d, koltuk %d" % [why["members"], members.size()])
	var total := 0
	var prev_abs := 1 << 30
	var prev_name := ""
	var listed := {}
	for f: Dictionary in why["factors"]:
		var n := String(f["name"])
		listed[n] = true
		total += int(f["net"])
		_check(int(f["net"]) == int(recomputed_net.get(n, 0)), "%s why_net_%s" % [label, n], "why %d, bağımsız hesap %d" % [f["net"], recomputed_net.get(n, 0)])
		_check(int(f["for"]) == int(recomputed_for.get(n, 0)) and int(f["against"]) == int(recomputed_against.get(n, 0)), "%s why_member_counts_%s" % [label, n],
			"why %d/%d, bağımsız %d/%d" % [f["for"], f["against"], recomputed_for.get(n, 0), recomputed_against.get(n, 0)])
		var mag := absi(int(f["net"]))
		_check(mag < prev_abs or (mag == prev_abs and n > prev_name), "%s why_sorted_by_abs_net_then_name" % label, "%s sıra bozuk" % n)
		prev_abs = mag
		prev_name = n
	_check(total == score_sum, "%s sum_of_why_net_equals_sum_of_member_scores" % label, "Σ net %d, Σ üye skoru %d" % [total, score_sum])
	for n: String in recomputed_net:
		if int(recomputed_net[n]) != 0 or int(recomputed_for.get(n, 0)) + int(recomputed_against.get(n, 0)) > 0:
			_check(listed.has(n), "%s why_lists_every_active_factor_%s" % [label, n], "kayıtlı etken why'de yok")
	# Altyapı: kayıtlı yük == çözüldüğü gündeki D2 yükü
	_check(String(why.get("infra_region", "")) == "D2", "%s why_infra_region_is_D2" % label, "bölge %s" % str(why.get("infra_region", "")))
	_check(int(why.get("infra_load_pm", -1)) == load_at_resolve, "%s why_infra_load_equals_region_load_at_resolve" % label, "why %s, D2 çözülme günü %d" % [str(why.get("infra_load_pm", -1)), load_at_resolve])
	# Ret ise plan durumu ve olaylar
	var plan_states := {}
	for id in near_ids:
		var ps := s.facade.plan_state(int(id))
		plan_states[String(ps.state)] = int(plan_states.get(String(ps.state), 0)) + 1
	if failed:
		_check(int(plan_states.get("plan_rejected", 0)) == near_ids.size(), "%s all_plan_parcels_rejected_state" % label, "durumlar %s" % str(plan_states))
		_check(int(s.counts.get("event.zoning.plan_rejected", 0)) == 1 and int(s.counts.get("event.council.vote_failed", 0)) == 1, "%s rejection_events_emitted_once" % label,
			"olaylar plan_rejected=%s vote_failed=%s" % [s.counts.get("event.zoning.plan_rejected", 0), s.counts.get("event.council.vote_failed", 0)])
		# Açıklayıcılık: hayır oylarını açıklayabilecek (>= no üye aleyhine) ve net < 0 bir etken var mı
		var explainer := ""
		for f: Dictionary in why["factors"]:
			if int(f["net"]) < 0 and int(f["against"]) >= int(vote["no"]):
				explainer = String(f["name"])
				break
		_warn(explainer != "", "%s failed_vote_has_a_negative_factor_carried_by_all_no_voters" % label, "hayır oyu %d; net<0 olup en az o kadar üyede eksi olan etken yok" % int(vote["no"]))
	else:
		_check(int(plan_states.get("plan_rejected", 0)) == 0, "%s passed_vote_leaves_no_rejected_parcel" % label, "durumlar %s" % str(plan_states))
		_check(bool(vote["applied"]), "%s passed_vote_applied" % label, "applied false")
	return {"status": String(vote["status"]), "yes": vote["yes"], "no": vote["no"], "abstain": vote["abstain"], "opened": vote["opened_tick"],
		"closes": vote["closes_tick"], "resolved_rel_plan": int(vote["resolved_tick"]) - t_plan, "why": why, "load_at_resolve": load_at_resolve,
		"members": member_rows, "plan_states": plan_states, "stance": _stances(s), "events": s.counts}


func _stances(s: Support.SimCtx) -> Dictionary:
	var out := {}
	for k in 5:
		var mk := "actor.council.%d" % (k + 1)
		if ActorStore.has_actor(s.facade.game_state(), mk):
			out[mk] = int(ActorStore.actor_ref(s.facade.game_state(), mk)["stance"].get("growth_vs_preservation", 0))
	return out


# --- UI ---

func _ui_checks(label: String, s: Support.SimCtx, vote: Dictionary, row: Dictionary) -> void:
	var snap := s.facade.snapshot()
	var view: CouncilVoteView = null
	for v: CouncilVoteView in snap.council.votes:
		if v.vote_id == int(vote["id"]):
			view = v
	_check(view != null, "%s snapshot_has_vote_view" % label, "snapshot.council.votes içinde yok")
	if view == null:
		return
	# Sözleşme eşlemesi: why_factors == kayıt
	var why: Dictionary = vote.get("why", {})
	var raw: Array = why.get("factors", [])
	_check(view.why_factors.size() == raw.size(), "%s view_why_factor_count" % label, "görünüm %d, kayıt %d" % [view.why_factors.size(), raw.size()])
	for i in mini(view.why_factors.size(), raw.size()):
		var f: CouncilWhyFactor = view.why_factors[i]
		_check(String(f.name_key) == String(raw[i]["name"]) and f.net == int(raw[i]["net"]) and f.for_members == int(raw[i]["for"]) and f.against_members == int(raw[i]["against"]),
			"%s view_why_factor_%d_matches_record" % [label, i], "%s" % str(f.to_dict()))
	_check(view.infra_load_pm == int(why.get("infra_load_pm", -2)) and String(view.infra_region) == String(why.get("infra_region", "")), "%s view_infra_matches_record" % label, "görünüm %d/%s" % [view.infra_load_pm, view.infra_region])
	var panel_text := _council_text(s)
	row["panel_text"] = panel_text
	var split := CouncilModel.why_split(view)
	_check(panel_text.contains(UiText.t(&"council.why.title")), "%s panel_has_why_title" % label, panel_text.left(400))
	_check(not panel_text.contains(UiText.t(&"council.why.none")), "%s panel_does_not_claim_why_missing" % label, "neden kaydı var ama panel 'kaydedilmedi' diyor")
	var rejected: bool = vote["status"] == "failed"
	_check(panel_text.contains(UiText.t(&"council.outcome.rejected" if rejected else &"council.outcome.approved")), "%s panel_shows_outcome" % label, panel_text.left(300))
	_check(panel_text.contains(UiText.t(&"council.tally", {"yes": view.yes, "no": view.no, "abstain": view.abstain})), "%s panel_shows_tally" % label, "sayım metni yok")
	for side in ["against", "for"]:
		var factors: Array = split[side]
		if not factors.is_empty():
			_check(panel_text.contains(UiText.t(&"council.why.against" if side == "against" else &"council.why.for")), "%s panel_has_%s_header" % [label, side], "başlık yok")
		for f: CouncilWhyFactor in factors:
			var label_text := UiText.t(f.name_key)
			_check(panel_text.contains(label_text), "%s panel_lists_%s_%s" % [label, side, f.name_key], "'%s' panelde yok" % label_text)
			_check(label_text != String(f.name_key), "%s factor_label_is_turkish_%s" % [label, f.name_key], "ham anahtar: %s" % f.name_key)
			_check(panel_text.contains(UiText.t(&"council.why.members", {"against_n": f.against_members, "for_n": f.for_members})), "%s panel_member_counts_%s" % [label, f.name_key],
				"%d aleyhine/%d lehine satırı yok" % [f.against_members, f.for_members])
	if view.infra_load_pm >= 0:
		_check(panel_text.contains(UiText.t(&"council.why.infra", {"region": UiText.humanize("D2"), "load": view.infra_load_pm})), "%s panel_shows_infra_line" % label, "altyapı satırı yok (binde %d)" % view.infra_load_pm)
	_check(not panel_text.contains("reason.factor.") and not panel_text.contains("council."), "%s panel_has_no_raw_keys" % label, panel_text.left(500))
	var low := panel_text.to_lower()
	for word in FORBIDDEN:
		_check(not low.contains(word), "%s panel_has_no_forbidden_word_%s" % [label, word.strip_edges()], "yasak sözcük: " + word)
	# ReasonPanel: "Oylamanın gerekçeleri" düğmesi = 5 üyenin kaydı. Liste satırlarında ve ayrıntıda ham anahtar OLMAMALI.
	var rp_text := _reason_text(s, view.reason_ids, false)
	row["reason_panel_list_text"] = rp_text.left(1200)
	_check(not rp_text.contains("decision.") and not rp_text.contains("reason.factor."), "%s reason_panel_list_has_no_raw_keys" % label,
		"liste: %s" % rp_text.left(600).replace("\n", " / "))
	var rd_text := _reason_text(s, view.reason_ids, true)
	row["reason_panel_detail_text"] = rd_text.left(1200)
	_check(not rd_text.contains("decision.") and not rd_text.contains("reason.factor."), "%s reason_panel_detail_has_no_raw_keys" % label,
		"ayrıntı: %s" % rd_text.left(600).replace("\n", " / "))
	_check(rd_text.contains(UiText.t(&"reason.factor.budget_realism")) and rd_text.contains(UiText.t(&"reason.factor.stance_distance")), "%s reason_panel_detail_shows_turkish_factor_labels" % label,
		"ayrıntı: %s" % rd_text.left(600).replace("\n", " / "))
	# Olay ve parsel durumu metinleri
	for key in ["event.council.vote_opened", "event.council.vote_failed" if rejected else "event.council.vote_passed", "event.zoning.plan_rejected" if rejected else "event.zoning.applied"]:
		if s.event_samples.has(key):
			var text := UiText.event_text(s.event_samples[key])
			_check(text != "" and not text.contains("event."), "%s event_text_%s" % [label, key], "metin: '%s'" % text)
			row["text_" + key] = text
		elif key != "event.zoning.applied":
			_fail("%s event_sample_%s" % [label, key], "olay hiç gelmedi")
	if rejected:
		var ps := s.facade.plan_state(int(vote["proposal"]["parcel_ids"][0]))
		var pt := PlanStateText.label(ps)
		row["plan_state_text"] = pt
		_check(pt != "" and not pt.contains("plan.state"), "%s rejected_parcel_status_text" % label, "metin '%s'" % pt)
	_check(UiText.missing_keys().is_empty(), "%s no_missing_ui_keys" % label, str(UiText.missing_keys()))


func _council_text(s: Support.SimCtx) -> String:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 2400.0)
	root.add_child(holder)
	var panel := CouncilPanel.create(ctx, s.facade)
	holder.add_child(panel)
	panel.size = holder.size
	var text := panel.joined_text()
	panel.refresh()  # aynı veride yeniden çizim hatasız
	_check(panel.joined_text() == text, "council_panel_refresh_is_stable", "refresh sonrası metin değişti")
	holder.queue_free()
	return text


func _reason_text(s: Support.SimCtx, ids: PackedInt64Array, detail: bool) -> String:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 2400.0)
	root.add_child(holder)
	var panel := ReasonPanel.create(ctx, s.facade)
	holder.add_child(panel)
	panel.size = holder.size
	if detail:
		panel.show_record(int(ids[0]))
	else:
		panel.show_reason_ids(ids)
	var text := " | ".join(panel.texts())
	holder.queue_free()
	return text


## Oylamadan çok sonra: neden kaydı (`why`) kalır, üye gerekçeleri budanmış olabilir; panel dürüst kalmalı.
func _late_checks(label: String, s: Support.SimCtx, vote: Dictionary, row: Dictionary) -> void:
	var late := int(_args.get("late-days", "200"))
	s.step(late)
	var votes: Array = PoliticsState.data(s.facade.game_state())["council"]["votes"]
	var found := {}
	for v: Dictionary in votes:
		if int(v["id"]) == int(vote["id"]):
			found = v
	_check(not found.is_empty(), "%s late_vote_still_in_history" % label, "oylama %d gün sonra kayıttan düştü" % late)
	if found.is_empty():
		return
	var why: Dictionary = found.get("why", {})
	_check(why == vote.get("why", {}), "%s late_why_unchanged" % label, "why %d gün sonra değişti" % late)
	var first_id := s.facade.game_state().reasons.first_id()
	var retained := 0
	for rid in found["reason_ids"]:
		if int(rid) >= first_id:
			retained += 1
	var text := _council_text(s)
	row["late"] = {"days": late, "reason_ids_retained": retained, "of": (found["reason_ids"] as Array).size(), "panel_has_why": text.contains(UiText.t(&"council.why.title")) and text.contains(UiText.t(&"council.why.against")),
		"panel_has_vote_reason_button": text.contains(UiText.t(&"council.why_vote")), "panel_text": text.left(1500)}
	_check(bool(row["late"]["panel_has_why"]), "%s late_panel_still_shows_why" % label, text.left(500))
	if retained == 0:
		_check(not text.contains(UiText.t(&"council.why_vote")), "%s late_panel_hides_reason_button_when_records_pruned" % label, "gerekçeler budandı ama düğme duruyor")
	_check(UiText.missing_keys().is_empty(), "%s late_no_missing_ui_keys" % label, str(UiText.missing_keys()))


# --- Aday yol (council_real_probe ile aynı seçim) ---

func _candidates() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(_w.world_seed, "t043b_real_probe")
	var ids: Array = _w.net.edges.keys()
	ids.sort()
	var out: Array = []
	for n in CANDIDATES:
		var e: WorldRoadEdge = _w.net.edges[ids[rng.randi() % ids.size()]]
		var a := _w.net.node_pos(e.a).lerp(_w.net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 250.0)
		var res := RoadDraftCheck.check(_w.net, PackedVector2Array([a, b]), RoadDrawTool.ROAD_CLASS, _w.road_rules)
		if not bool(res["ok"]):
			continue
		var count := 0
		for v in _vacant:
			if _dist_to_segment(v.center, a, b) <= NEAR_M:
				count += 1
		if count < MIN_VACANT:
			continue
		out.append({"pts": res["points"], "count": count, "len": res["length_m"], "order": n})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["count"]) != int(y["count"]):
			return int(x["count"]) > int(y["count"])
		return int(x["order"]) < int(y["order"]))
	return out


func _nearest_vacant(pts: PackedVector2Array, count: int) -> PackedInt64Array:
	var scored: Array = []
	for v in _vacant:
		var d := _dist_to_segment(v.center, pts[0], pts[pts.size() - 1])
		if d <= NEAR_M:
			scored.append([d, v.id])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out := PackedInt64Array()
	for k in mini(count, scored.size()):
		out.append(int(scored[k][1]))
	return out


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 <= 0.0 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- Yardımcılar ---

func _check(cond: bool, label: String, detail: String) -> void:
	_checks += 1
	if not cond:
		_fail(label, detail)


func _warn(cond: bool, label: String, detail: String) -> void:
	if not cond:
		_warns.append([label, detail])
		print("QA_WARN ", label, " :: ", detail)


func _fail(label: String, detail: String) -> void:
	_fails.append([label, detail])
	print("QA_FAIL ", label, " :: ", detail)


func _finish() -> void:
	var natural_rejects := 0
	for r: Dictionary in _results:
		natural_rejects += 1 if r.get("status", "") == "failed" else 0
	# Görevin ana iddiası: gerçek D2'de doğal RED üretilebilir.
	_check(natural_rejects > 0 or str(_args.get("only", "")) != "", "natural_council_rejection_was_produced", "hiçbir senaryoda doğal ret çıkmadı")
	print("QA_SUMMARY ", JSON.stringify({"checks": _checks, "fails": _fails.size(), "warns": _warns.size(), "scenarios": _results.size(),
		"natural_rejects": natural_rejects, "missing_ui_keys": Array(UiText.missing_keys())}))
	quit(1 if not _fails.is_empty() else 0)


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
