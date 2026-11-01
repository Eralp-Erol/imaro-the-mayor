# gdlint:disable=max-line-length
extends SceneTree
## QA 2026-11-01 · GERÇEK Ismeral'da yıkım/kamulaştırma TEPKİSİ (PE-01, `reactions.json` `local`) D2 DIŞI bölgelerde,
## birden çok dünya tohumunda + yol ZİNCİRİ (art arda iki yol). Kurulum `qa_world_support.gd` (gerçek dünya + gerçek
## kamulaştırma köprüsü [`PlayableExpropriation.attach_port`] + oyunun siyaset/ekonomi yapılandırması). Sim/oyun kodu DEĞİŞMEZ.
## KOŞAN ASSERTLER vardır (çıkış kodu 1 = en az bir `QA_FAIL`); ham ölçüm `QA_REACT ` + JSON satırlarıdır.
## ÖNEMLİ: oyunun verisinde yol yetki alanı yalnız D2'dir (`network.json player_roads.jurisdiction_regions`); D2 dışında yol
## ÇİZİLEMEZ (`outside_jurisdiction`). `--jurisdiction=all` (varsayılan) kısıtı bellekte kaldırır = "başka başlangıç bölgesi"
## NE-OLUR senaryosu (CAN-08); `--jurisdiction=game` oyunun verisini korur (D2 sınır yolları komşu bölge parsellerini alabilir mi?).
## Çalıştır (tek süreç = tek dünya tohumu, ~2-6 dk):
##   tools/godot.sh --headless --path . --script res://tests/sim/perf/qa_reaction_regions_probe.gd -- \
##       [--world-seed=N] [--regions=D1,D6,D3] [--jurisdiction=all|game] [--pool=120] [--days=100] [--warm=30] [--no-chain] [--only=label]
## Senaryolar (bölge başına): max hane / orta (>=5) / tam 5 hane / tam 4 hane (iki hafta fazı) / 1-3 hane (sessiz?) /
## 0 hane ama bina yıkan / çok bölgeli yol. Zincir: A yolu, A'nın ucundan B yolu (aralık 1 gün ve 14 gün), LIFO geri alma.

const Support := preload("res://tests/sim/perf/qa_world_support.gd")
## `reactions.json` local: neighborhood_households 200, min_displacement_pm 20 (veri; test bunu OKUR, kopyalamaz).
const AGENDA_TEMPLATE := "PE-01"

var _args: Dictionary = {}
var _fails: Array = []
var _checks: int = 0
var _results: Array = []
var _w: Support.WorldCtx = null


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	UiText.reset()
	var control := WorldControlData.load_dir(Support.DATA_DIR)
	var world_seed := int(_args.get("world-seed", str(int(control["world"]["default_seed"]))))
	var regions: PackedStringArray = str(_args.get("regions", "D1,D6,D3")).split(",")
	var pool := int(_args.get("pool", "120"))
	var days := int(_args.get("days", "100"))
	var warm := int(_args.get("warm", str(Support.WARM_DAYS)))
	_w = Support.build_world(world_seed)
	var all_regions := str(_args.get("jurisdiction", "all")) == "all"
	_w.set_jurisdiction_all(all_regions)
	print("QA_REACT ", JSON.stringify({"kind": "world", "world_seed": world_seed, "regions": _w.regions, "parcels": _w.views.size(),
		"base_hash": _w.base_hash, "jurisdiction": "all" if all_regions else str(_w.game_jurisdiction)}))
	var base := Support.new_sim(_w)
	if base == null:
		_fail("setup", "sim kurulamadı")
		_finish()
		return
	base.step(warm)
	var only := str(_args.get("only", ""))
	var chain_done := false
	for region in regions:
		var tally := {}
		var cands := Support.region_candidates(_w, base, region, pool, "qa_react_%s" % region, tally)
		print("QA_REACT ", JSON.stringify({"kind": "candidate_rejects", "region": region, "tally": tally}))
		_stats_of(region, cands)
		for pick: Dictionary in _picks(cands):
			if only != "" and only != str(pick["label"]):
				continue
			_single(region, str(pick["label"]), pick["cand"], int(pick.get("warm", warm)), days)
		if not _args.has("no-chain") and not chain_done and only in ["", "chain"]:
			chain_done = _chain(region, cands, warm, days)
	_finish()


# --- Aday istatistiği ve seçim ---

func _stats_of(region: String, cands: Array) -> void:
	var hh: Array = cands.map(func(c: Dictionary) -> int: return int(c["hh"]))
	hh.sort()
	var buckets := {"0": 0, "1-3": 0, "4": 0, "5+": 0, ">=20": 0, ">=100": 0}
	var multi := 0
	for h: int in hh:
		if h == 0:
			buckets["0"] += 1
		elif h <= 3:
			buckets["1-3"] += 1
		elif h == 4:
			buckets["4"] += 1
		else:
			buckets["5+"] += 1
		if h >= 20:
			buckets[">=20"] += 1
		if h >= 100:
			buckets[">=100"] += 1
	for c: Dictionary in cands:
		if (c["regions_taken"] as Dictionary).size() > 1:
			multi += 1
	var n := hh.size()
	print("QA_REACT ", JSON.stringify({"kind": "region_stats", "region": region, "valid_roads": n, "hh_buckets": buckets,
		"hh_median": hh[n / 2] if n > 0 else -1, "hh_max": hh[n - 1] if n > 0 else -1, "multi_region_roads": multi}))
	_check(n >= 10, "region_%s_has_enough_valid_roads" % region, "geçerli kamulaştırmalı yol sayısı %d (>= 10 beklenir)" % n)


func _picks(cands: Array) -> Array:
	var sorted_c := cands.duplicate()
	sorted_c.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["hh"]) < int(b["hh"]) or (int(a["hh"]) == int(b["hh"]) and int(a["order"]) < int(b["order"])))
	var out: Array = []
	var used := {}
	if sorted_c.is_empty():
		return out
	_add_pick(out, used, "max", sorted_c[sorted_c.size() - 1])
	var ge5: Array = sorted_c.filter(func(c: Dictionary) -> bool: return int(c["hh"]) >= 5)
	if not ge5.is_empty():
		_add_pick(out, used, "median5", ge5[ge5.size() / 2])
	var exact5: Variant = _first_with(sorted_c, 5)
	_add_pick(out, used, "hh5", exact5)
	var exact4: Variant = _first_with(sorted_c, 4)
	_add_pick(out, used, "hh4_phaseA", exact4)
	if exact4 != null:
		var base_warm := int(_args.get("warm", str(Support.WARM_DAYS)))
		_add_pick(out, used, "hh4_phaseB", exact4, base_warm + 3)
		_add_pick(out, used, "hh4_phaseC", exact4, base_warm + 4)  # yol haftalık tarama günü uygulanır (yaş 0)
		_add_pick(out, used, "hh4_phaseD", exact4, base_warm + 5)
	for h in [3, 2, 1]:
		var c: Variant = _first_with(sorted_c, h)
		if c != null:
			_add_pick(out, used, "hh%d" % h, c)
			break
	var built0 := sorted_c.filter(func(c: Dictionary) -> bool: return int(c["hh"]) == 0 and int(c["built"]) > 0)
	if not built0.is_empty():
		_add_pick(out, used, "hh0_built", built0[0])
	var multi := sorted_c.filter(func(c: Dictionary) -> bool: return (c["regions_taken"] as Dictionary).size() > 1)
	if not multi.is_empty():
		_add_pick(out, used, "multi_region", multi[multi.size() - 1])
	return out


func _add_pick(out: Array, used: Dictionary, label: String, c: Variant, warm_override: int = -1) -> void:
	if c == null or (used.has(int(c["order"])) and warm_override < 0):
		return
	used[int(c["order"])] = true
	var row := {"label": label, "cand": c}
	if warm_override >= 0:
		row["warm"] = warm_override
	out.append(row)


func _first_with(sorted_c: Array, hh: int) -> Variant:
	for c: Dictionary in sorted_c:
		if int(c["hh"]) == hh:
			return c
	return null


# --- Tek yol senaryosu ---

func _single(region: String, label: String, cand: Dictionary, warm: int, days: int) -> void:
	var tag := "%d/%s/%s" % [_w.world_seed, region, label]
	var s := Support.new_sim(_w)
	if s == null:
		_fail(tag, "sim kurulamadı")
		return
	s.step(warm)
	var housed_before := s.housed_total()
	var sent := s.facade.submit_command(SimCommand.public_work_road(cand["cm"], RoadDrawTool.ROAD_CLASS, true))
	var t_road := s.tick()
	_check(sent.status != CommandResult.STATUS_REJECTED, "%s road_accepted" % tag, "status=%s reason=%s" % [sent.status, sent.reason_key])
	s.step(1)
	var works := s.facade.public_works()
	_check(works.size() == 1, "%s one_work_built" % tag, "works=%d" % works.size())
	if works.is_empty():
		_w.restore_net(s.ctx, 0)
		return
	var work := works[0]
	var housed_after := s.housed_total()
	var book := s.displaced_book()
	var ledger_hh := 0
	var by_region := {}
	for code: String in book:
		for row: Array in book[code]:
			if int(row[2]) == work.command_id:
				ledger_hh += int(row[1])
				by_region[code] = int(by_region.get(code, 0)) + int(row[1])
	# Önizleme == sim kaydı == defter == konut stoku düşüşü
	_check(work.displaced_households == int(cand["hh"]), "%s preview_matches_work" % tag, "önizleme %d, kayıt %d" % [cand["hh"], work.displaced_households])
	_check(ledger_hh == work.displaced_households, "%s ledger_equals_work_households" % tag, "defter %d, yol kaydı %d" % [ledger_hh, work.displaced_households])
	_check(housed_before - housed_after == work.displaced_households, "%s housed_drop_equals_displaced" % tag,
		"konutlu hane %d -> %d (düşüş %d), yerinden edilen %d" % [housed_before, housed_after, housed_before - housed_after, work.displaced_households])
	var panel_text := ""
	var open_max := 0
	for _d in days:
		s.step(1)
		var open_now := _open_pe01(s)
		if open_now > open_max:  # panel, öğe AÇIKKEN (süre dolunca "Bekleyen gündem öğesi yok" görünür; doğru)
			open_max = open_now
			panel_text = _agenda_text(s)
	var items: Array = []
	var own_ref := "command.%d" % work.command_id
	for it: Dictionary in s.agenda_seen.values():
		if it["template"] == AGENDA_TEMPLATE and (it["cause_refs"] as Array).has(own_ref):
			items.append(it)
	var pe01_all := s.agenda_seen.values().filter(func(it: Dictionary) -> bool: return it["template"] == AGENDA_TEMPLATE)
	var max_region_hh := 0
	for code: String in by_region:
		max_region_hh = maxi(max_region_hh, int(by_region[code]))
	var row := {"kind": "single", "tag": tag, "world_seed": _w.world_seed, "region": region, "label": label,
		"road_tick": t_road, "road_tick_mod7": t_road % 7, "len_m": snappedf(float(cand["len"]), 0.1), "taken": work.taken_parcel_ids.size(),
		"built_taken": work.taken_built_parcels, "displaced_hh": work.displaced_households, "near_hh": int(cand["near_hh"]),
		"ledger_by_region": by_region, "regions_taken": cand["regions_taken"], "pe01_for_command": items.size(),
		"pe01_total": pe01_all.size(), "items": items.map(func(it: Dictionary) -> Dictionary: return {"id": it["id"], "region": it["region"],
			"opened_rel": int(it["opened"]) - t_road, "status": it["status_last"], "args": it["args"]}),
		"agenda_by_template": _by_template(s), "group_reacted": s.group_reacted.size(), "pol_events": s.pol_events.size(),
		"road_events": s.road_events.size(), "silent": work.displaced_households > 0 and items.is_empty()}
	# Sessizlik / açılma kuralları
	_check(items.size() <= 1, "%s at_most_one_pe01_per_command" % tag, "bir komut için %d PE-01 öğesi (%s)" % [items.size(), str(by_region)])
	if work.displaced_households == 0:
		_check(items.is_empty() and pe01_all.is_empty(), "%s zero_displaced_is_silent" % tag, "yerinden edilen 0 iken PE-01 var: %s" % str(items))
		_check(s.group_reacted.is_empty(), "%s zero_displaced_no_group_reaction" % tag, "group.reacted %d" % s.group_reacted.size())
	if max_region_hh >= 8:
		_check(items.size() == 1, "%s large_displacement_opens_exactly_one_pe01" % tag, "bölge hane %d, PE-01 %d" % [max_region_hh, items.size()])
	# Belgelenen eşik: reactions.json local (min_displacement_pm x neighborhood_households / 1000 = 4 hane) -> bu kadar hane PE-01 açar
	var local: Dictionary = s.pol_cfg.reactions["local"]
	var doc_min_hh := ceili(float(int(local["min_displacement_pm"])) * float(int(local["neighborhood_households"])) / 1000.0)
	row["documented_min_households"] = doc_min_hh
	if max_region_hh >= doc_min_hh and max_region_hh < 8:
		_check(items.size() == 1, "%s documented_threshold_%d_households_opens_pe01" % [tag, doc_min_hh],
			"yerinden edilen %d >= belgelenen eşik %d ama PE-01 yok (yol günü %% 7 = %d; okuma hane x 1000 x (360 - yaş) / 360 / %d < %d pm)" % [max_region_hh, doc_min_hh, t_road % 7, int(local["neighborhood_households"]), int(local["min_displacement_pm"])])
	if items.size() == 1:
		var it: Dictionary = items[0]
		_check(int(it["opened"]) - t_road <= 7, "%s pe01_within_a_week" % tag, "açılış %d gün sonra" % (int(it["opened"]) - t_road))
		var dominant := _dominant_region(by_region)
		_check(String(it["region"]) == dominant, "%s pe01_region_is_the_displaced_region" % tag, "öğe bölgesi %s, en çok hane yerinden edilen bölge %s (%s)" % [it["region"], dominant, str(by_region)])
		var cause := AgendaModel.displaced_cause(s.facade, PackedInt64Array(it["reason_ids"]))
		_check(bool(cause["found"]) and int(cause["households"]) == int(by_region.get(String(it["region"]), -1)),
			"%s pe01_cause_households_match_ledger" % tag, "neden kaydı %s, defter %s" % [str(cause), str(by_region)])
		row["agenda_panel_has_count"] = panel_text.contains("Yol yüzünden %s hane yerinden edildi." % UiText.number(int(by_region.get(String(it["region"]), -1))))
		_check(bool(row["agenda_panel_has_count"]), "%s agenda_panel_shows_household_count" % tag, "panel metni: %s" % panel_text.left(300))
	row["fingerprint"] = s.facade.state_hash()
	row["net_restored"] = _w.restore_net(s.ctx, works.size())
	_check(bool(row["net_restored"]), "%s net_restored_after_undo" % tag, "geri alınca ağ özeti tabana dönmedi")
	_results.append(row)
	print("QA_REACT ", JSON.stringify(row))


func _dominant_region(by_region: Dictionary) -> String:
	var best := ""
	var best_v := -1
	var codes: Array = by_region.keys()
	codes.sort()
	for code: String in codes:
		if int(by_region[code]) > best_v:
			best_v = int(by_region[code])
			best = code
	return best


func _open_pe01(s: Support.SimCtx) -> int:
	var n := 0
	for it in s.facade.agenda_items():
		n += 1 if String(it.template_id) == AGENDA_TEMPLATE else 0
	return n


func _by_template(s: Support.SimCtx) -> Dictionary:
	var out := {}
	for it: Dictionary in s.agenda_seen.values():
		out[it["template"]] = int(out.get(it["template"], 0)) + 1
	return out


# --- Zincir ---

func _chain(region: String, cands: Array, warm: int, days: int) -> bool:
	var best: Variant = null
	for c: Dictionary in cands:
		if int(c["hh"]) >= 6 and int(c["hh"]) <= 40 and (c["regions_taken"] as Dictionary).size() == 1:
			if best == null or absi(int(c["hh"]) - 14) < absi(int(best["hh"]) - 14):
				best = c
	if best == null:
		_fail("chain/%s" % region, "zincir için 6-40 haneli tek bölgeli A yolu bulunamadı")
		return false
	var b_cm := PackedInt64Array()
	for gap in [1, 14]:
		b_cm = _chain_run(region, best, b_cm, gap, warm, days)
	return true


## A yolunu gönder, `gap` gün sonra A'nın ucundan B yolunu gönder. B adayı ilk koşuda aranır, ikincisinde yeniden kullanılır.
func _chain_run(region: String, a: Dictionary, b_cm_in: PackedInt64Array, gap: int, warm: int, days: int) -> PackedInt64Array:
	var tag := "%d/%s/chain_gap%d" % [_w.world_seed, region, gap]
	var s := Support.new_sim(_w)
	s.step(warm)
	var housed0 := s.housed_total()
	var res_a := s.facade.submit_command(SimCommand.public_work_road(a["cm"], RoadDrawTool.ROAD_CLASS, true))
	var t_a := s.tick()
	_check(res_a.status != CommandResult.STATUS_REJECTED, "%s A_accepted" % tag, "status=%s %s" % [res_a.status, res_a.reason_key])
	s.step(1)
	var hash_after_a := _w.net.graph_hash()
	var housed_a := s.housed_total()
	var works := s.facade.public_works()
	if works.size() != 1:
		_fail(tag, "A yolu yapılmadı (works=%d)" % works.size())
		_w.restore_net(s.ctx, works.size())
		return PackedInt64Array()
	var work_a := works[0]
	var b_cm := b_cm_in
	var b_info: Dictionary = {}
	if b_cm.is_empty():
		var end_a: Vector2 = (a["pts"] as PackedVector2Array)[(a["pts"] as PackedVector2Array).size() - 1]
		b_info = _find_chain_b(s, end_a, int(a["hh"]))
		if b_info.is_empty():
			_fail(tag, "A'nın ucundan en az 5 hane yerinden eden B yolu bulunamadı")
			_w.restore_net(s.ctx, 1)
			return PackedInt64Array()
		b_cm = b_info["cm"]
	s.step(maxi(gap - 1, 0))
	var housed_b0 := s.housed_total()
	var res_b := s.facade.submit_command(SimCommand.public_work_road(b_cm, RoadDrawTool.ROAD_CLASS, true))
	var t_b := s.tick()
	_check(res_b.status != CommandResult.STATUS_REJECTED, "%s B_accepted" % tag, "status=%s %s" % [res_b.status, res_b.reason_key])
	s.step(1)
	works = s.facade.public_works()
	_check(works.size() == 2, "%s two_works_built" % tag, "works=%d" % works.size())
	if works.size() != 2:
		_w.restore_net(s.ctx, works.size())
		return b_cm
	var work_b := works[1]
	var housed_b := s.housed_total()
	_check(work_b.command_id != work_a.command_id, "%s distinct_command_ids" % tag, "aynı komut kimliği")
	# Aynı parsel iki kez alınmaz
	var overlap := 0
	for pid in work_b.taken_parcel_ids:
		if work_a.taken_parcel_ids.has(pid):
			overlap += 1
	_check(overlap == 0, "%s no_parcel_taken_twice" % tag, "A ve B ortak parsel: %d" % overlap)
	_check(work_a.taken_parcel_ids.size() > 0 and work_b.taken_parcel_ids.size() > 0, "%s both_roads_took_parcels" % tag, "A=%d B=%d" % [work_a.taken_parcel_ids.size(), work_b.taken_parcel_ids.size()])
	_check(PublicWorksState.taken_count(s.facade.game_state()) == work_a.taken_parcel_ids.size() + work_b.taken_parcel_ids.size(), "%s taken_registry_is_the_sum" % tag,
		"kayıt %d, A+B %d" % [PublicWorksState.taken_count(s.facade.game_state()), work_a.taken_parcel_ids.size() + work_b.taken_parcel_ids.size()])
	_check(housed0 - housed_a == work_a.displaced_households, "%s A_housed_drop" % tag, "A: düşüş %d, hane %d" % [housed0 - housed_a, work_a.displaced_households])
	_check(housed_b0 - housed_b == work_b.displaced_households, "%s B_housed_drop" % tag, "B: düşüş %d, hane %d" % [housed_b0 - housed_b, work_b.displaced_households])
	# Defter: iki komut, kendi hane sayılarıyla; A'nın satırları B'den etkilenmez
	var book := s.displaced_book()
	var per_cmd := {}
	for code: String in book:
		for row: Array in book[code]:
			per_cmd[int(row[2])] = int(per_cmd.get(int(row[2]), 0)) + int(row[1])
	_check(int(per_cmd.get(work_a.command_id, -1)) == work_a.displaced_households, "%s ledger_A" % tag, "defter %s, A %d" % [str(per_cmd), work_a.displaced_households])
	_check(int(per_cmd.get(work_b.command_id, -1)) == work_b.displaced_households or work_b.displaced_households == 0, "%s ledger_B" % tag, "defter %s, B %d" % [str(per_cmd), work_b.displaced_households])
	var panel_text := ""
	var open_max := 0
	for _d in days:
		s.step(1)
		var open_now := _open_pe01(s)
		if open_now > open_max:
			open_max = open_now
			panel_text = _agenda_text(s)
	var item_a := _items_for(s, work_a.command_id)
	var item_b := _items_for(s, work_b.command_id)
	var open_a: Dictionary = item_a[0] if not item_a.is_empty() else {}
	var open_b: Dictionary = item_b[0] if not item_b.is_empty() else {}
	var thr_note := "hane A=%d B=%d" % [work_a.displaced_households, work_b.displaced_households]
	_check(item_a.size() == 1, "%s A_has_exactly_one_pe01" % tag, "A için %d öğe (%s)" % [item_a.size(), thr_note])
	if work_b.displaced_households >= 8:
		_check(item_b.size() == 1, "%s B_has_exactly_one_pe01" % tag, "B için %d öğe (%s); tüm PE-01: %s" % [item_b.size(), thr_note, str(s.agenda_seen.values().filter(func(it: Dictionary) -> bool: return it["template"] == AGENDA_TEMPLATE))])
	if not open_b.is_empty():
		_check(int(open_b["opened"]) - t_b <= 14, "%s B_pe01_prompt" % tag, "B'nin öğesi %d gün sonra açıldı" % (int(open_b["opened"]) - t_b))
		var cause_b := AgendaModel.displaced_cause(s.facade, PackedInt64Array(open_b["reason_ids"]))
		_check(bool(cause_b["found"]) and int(cause_b["households"]) == work_b.displaced_households, "%s B_cause_households" % tag, "B neden %s, yerinden edilen %d" % [str(cause_b), work_b.displaced_households])
		_check(not (open_b["cause_refs"] as Array).has("command.%d" % work_a.command_id), "%s B_cause_does_not_blame_A" % tag, "B öğesi A'yı da neden gösteriyor: %s" % str(open_b["cause_refs"]))
	if not open_a.is_empty():
		var cause_a := AgendaModel.displaced_cause(s.facade, PackedInt64Array(open_a["reason_ids"]))
		_check(bool(cause_a["found"]) and int(cause_a["households"]) == work_a.displaced_households, "%s A_cause_households" % tag, "A neden %s, yerinden edilen %d" % [str(cause_a), work_a.displaced_households])
	var text := panel_text
	if open_max >= 2:
		_check(text.contains("Yol yüzünden %s hane yerinden edildi." % UiText.number(work_a.displaced_households)) and text.contains("Yol yüzünden %s hane yerinden edildi." % UiText.number(work_b.displaced_households)),
			"%s agenda_panel_lists_both_roads" % tag, "panel metni: %s" % text.left(400))
	elif not item_a.is_empty() and not item_b.is_empty():
		print("QA_NOTE ", tag, " iki PE-01 öğesi aynı anda açık olmadı (A açılış ", item_a[0]["opened"], ", B açılış ", item_b[0]["opened"], ", en çok açık ", open_max, ")")
	var row := {"kind": "chain", "tag": tag, "world_seed": _w.world_seed, "region": region, "gap": gap, "t_a": t_a, "t_b": t_b,
		"A": {"cmd": work_a.command_id, "hh": work_a.displaced_households, "taken": work_a.taken_parcel_ids.size(), "built": work_a.taken_built_parcels, "items": item_a},
		"B": {"cmd": work_b.command_id, "hh": work_b.displaced_households, "taken": work_b.taken_parcel_ids.size(), "built": work_b.taken_built_parcels, "items": item_b},
		"agenda_by_template": _by_template(s), "pe01_total": s.agenda_seen.values().filter(func(it: Dictionary) -> bool: return it["template"] == AGENDA_TEMPLATE).size(),
		"b_info": b_info.get("info", {}), "panel_text": text.left(600)}
	# LIFO geri alma: B gider, A kalır; tepki defteri ve gündem öğeleri GERİ ALINMAZ (D-011)
	var items_before_undo := s.agenda_all().size()
	var rows_before_undo := _ledger_rows(s)
	var u1 := s.facade.submit_command(SimCommand.public_work_undo_last())
	_check(u1.status != CommandResult.STATUS_REJECTED, "%s undo_B_accepted" % tag, "status=%s %s" % [u1.status, u1.reason_key])
	s.step(1)
	_check(s.facade.public_works().size() == 1 and s.facade.public_works()[0].command_id == work_a.command_id, "%s undo_removes_B_keeps_A" % tag,
		"kalan yollar: %s" % str(s.facade.public_works().map(func(x: PublicWorkView) -> int: return x.command_id)))
	_check(_w.net.graph_hash() == hash_after_a, "%s net_equals_after_A_hash" % tag, "B geri alınınca ağ özeti A sonrasına dönmedi")
	_check(PublicWorksState.taken_count(s.facade.game_state()) == work_a.taken_parcel_ids.size(), "%s taken_registry_back_to_A" % tag, "kayıt %d, A %d" % [PublicWorksState.taken_count(s.facade.game_state()), work_a.taken_parcel_ids.size()])
	_check(_ledger_rows(s) == rows_before_undo, "%s undo_does_not_erase_reaction_ledger" % tag, "defter satırları değişti")
	_check(s.agenda_all().size() >= items_before_undo, "%s undo_does_not_erase_agenda" % tag, "gündem öğeleri %d -> %d" % [items_before_undo, s.agenda_all().size()])
	var u2 := s.facade.submit_command(SimCommand.public_work_undo_last())
	s.step(1)
	_check(s.facade.public_works().is_empty(), "%s second_undo_removes_A" % tag, "kalan yol %d" % s.facade.public_works().size())
	_check(_w.net.graph_hash() == _w.base_hash, "%s net_equals_base_after_both_undone" % tag, "iki geri almadan sonra ağ tabana dönmedi (u2=%s)" % u2.status)
	_check(PublicWorksState.taken_count(s.facade.game_state()) == 0, "%s taken_registry_empty" % tag, "kayıt %d" % PublicWorksState.taken_count(s.facade.game_state()))
	row["after_both_undone"] = {"works": s.facade.public_works().size(), "ledger_rows": _ledger_rows(s), "agenda_items": s.agenda_all().size()}
	row["fingerprint"] = s.facade.state_hash()
	var restored := _w.net.graph_hash() == _w.base_hash
	if not restored:
		_fail("%s net_restore" % tag, "ağ özeti tabana dönmedi; sonraki senaryolar geçersiz olabilir")
	_results.append(row)
	print("QA_REACT ", JSON.stringify(row))
	return b_cm


func _ledger_rows(s: Support.SimCtx) -> int:
	var n := 0
	var book := s.displaced_book()
	for code: String in book:
		n += (book[code] as Array).size()
	return n


func _items_for(s: Support.SimCtx, command_id: int) -> Array:
	var out: Array = []
	for it: Dictionary in s.agenda_seen.values():
		if it["template"] == AGENDA_TEMPLATE and (it["cause_refs"] as Array).has("command.%d" % command_id):
			out.append({"id": it["id"], "region": it["region"], "opened": it["opened"], "status": it["status_last"], "args": it["args"],
				"cause_refs": it["cause_refs"], "reason_ids": it["reason_ids"]})
	return out


## A'nın ucundan 60-200 m'lik B adayı: A uygulanmış ağda geçerli, >= 5 hane yerinden eden, hanesi A'ya yakın olan.
func _find_chain_b(s: Support.SimCtx, start: Vector2, hh_a: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(_w.world_seed, "qa_chain_b")
	var best: Dictionary = {}
	for _n in 160:
		var end := start + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 200.0)
		var c := Support.candidate_for(_w, s, PackedVector2Array([start, end]))
		if c.is_empty() or int(c["hh"]) < 5:
			continue
		var pts: PackedVector2Array = c["pts"]
		if pts[0].distance_to(start) > 1.0:  # B gerçekten A'nın ucundan başlamalı (zincir)
			continue
		if best.is_empty() or absi(int(c["hh"]) - hh_a) < absi(int(best["hh"]) - hh_a):
			best = c
	if best.is_empty():
		return {}
	return {"cm": best["cm"], "info": {"hh": best["hh"], "taken": best["taken"], "built": best["built"], "len": snappedf(float(best["len"]), 0.1),
		"start": [snappedf((best["pts"] as PackedVector2Array)[0].x, 0.1), snappedf((best["pts"] as PackedVector2Array)[0].y, 0.1)]}}


# --- UI (gerçek facade -> AgendaPanel) ---

func _agenda_text(s: Support.SimCtx) -> String:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1800.0)
	root.add_child(holder)
	var panel := AgendaPanel.create(ctx, s.facade)
	holder.add_child(panel)
	panel.size = holder.size
	var text := panel.joined_text()
	holder.queue_free()
	return text


# --- Yardımcılar ---

func _check(cond: bool, label: String, detail: String) -> void:
	_checks += 1
	if not cond:
		_fail(label, detail)


func _fail(label: String, detail: String) -> void:
	_fails.append([label, detail])
	print("QA_FAIL ", label, " :: ", detail)


func _finish() -> void:
	print("QA_SUMMARY ", JSON.stringify({"checks": _checks, "fails": _fails.size(), "scenarios": _results.size(),
		"missing_ui_keys": Array(UiText.missing_keys())}))
	quit(1 if not _fails.is_empty() else 0)


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
