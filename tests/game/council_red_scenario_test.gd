# gdlint:disable=max-line-length
extends GdUnitTestSuite
## M2 kapanış madde 3 (F03 ölçüt 5) · Meclis RED yolu, DOĞAL koşulda ve karar gerektirmeden (production/log/
## 2026-11-04-meclis-red-senaryosu.md). Hiçbir üye duruşu, eşik, ağırlık ya da veri DEĞİŞTİRİLMEZ: oynanabilir kurulum
## (`PlayableEconomy` + `PlayablePolitics`, ≥ 10 parselli plan meclise gider) + gerçek T0 yerleşimli küçük dünya
## (`M2RenderSupport`), oyuncunun tek eylemi: boş 12 parsele YEŞİL imar teklifi.
## Bulgu: RED kural gereği üretilebilir ama YAPISAL değildir. Yeşil imar + bölge altyapısı ~%100 dolu (oyunun varsayılan
## başlangıcı: budget_realism her üyeden -99) iken noise-free tahmin 3-2 KABUL; RED yalnız oy gürültüsünün iki marjinal
## üyeyi (Meclis 4/5) çevirdiği tohumlarda çıkar (1000-1039 tohumları: 3 RED). Diğer imar türleri bu koşulda 24 tohumda hiç RED vermedi (karma/konut/ticari).
## Tohum 1020: RED 2-3. Yeni tohum gerekirse `test_red_is_chance_driven_not_structural` aralığını koşturup bakın.

const GREEN := &"zone.green"
const RESIDENTIAL := &"zone.residential"
const PLAN_PARCELS := 12
const SEED_RED := 1020
## Oy eşitliği (2-2, 1 çekimser): `council.json tie_result: fail` kuralıyla RED.
const SEED_RED_TIE := 1025
const SEED_FIRST := 1000
const SEED_COUNT := 40
const RAW_PREFIXES: Array[String] = ["reason.", "council.", "event.", "plan.", "decision."]
const FORBIDDEN: Array[String] = ["mutluluk", "puan", "skor", "₺"]
const DESKTOP := Vector2(1600, 900)


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()


func after_test() -> void:
	UiText.reset()


# --- kurulum ---

func _free_ids(count: int) -> PackedInt64Array:
	var fx := M2RenderSupport.fixture()
	var occupied := {}
	for pid in (fx["settlement"] as SettlementResult).columns.occupied_parcels():
		occupied[int(pid)] = true
	var out := PackedInt64Array()
	for v: ParcelView in fx["views"]:
		if out.size() >= count:
			break
		if not occupied.has(v.id):
			out.append(v.id)
	return out


## Oynanabilir kurulum (`patch`: ekonomi yaması; {} = oyunun kendisi). Dönüş: PoliticsHandle.
func _handle(sim_seed: int, patch: Dictionary = {}) -> PoliticsHandle:
	var fx := M2RenderSupport.fixture()
	var source := ListParcelSource.create(&"m2_fixture", fx["views"])
	var cfg := PlayableEconomy.config_for(fx["views"], fx["stock"], patch)
	var h := PoliticsBootstrap.create(sim_seed, source, cfg, fx["stock"], null, PlayablePolitics.config(), null)
	assert_object(h).is_not_null()
	h.facade.advance(2)
	return h


## Eylem: `count` boş parsele `zone` teklifi, sonra oturum bitene dek bekle. Dönüş: {h, ids, cmd}.
func _run(sim_seed: int, zone: StringName, count: int = PLAN_PARCELS, patch: Dictionary = {},
		days: int = 30) -> Dictionary:
	var h := _handle(sim_seed, patch)
	var ids := _free_ids(count)
	assert_int(ids.size()).override_failure_message("fixture yeterli boş parsel vermedi").is_equal(count)
	var cmd := h.facade.submit_command(SimCommand.zoning_propose(ids, zone))
	assert_bool(cmd.is_rejected()).override_failure_message(String(cmd.reason_key)).is_false()
	h.facade.advance(days)
	return {"h": h, "ids": ids, "cmd": cmd}


func _vote(h: PoliticsHandle) -> Dictionary:
	var votes: Array = PoliticsState.data(h.facade.game_state())["council"]["votes"]
	assert_int(votes.size()).override_failure_message("tam bir oylama beklenir").is_equal(1)
	return votes[0]


func _events(h: PoliticsHandle, message_key: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in h.facade.events_since(0):
		if e.message_key == message_key:
			out.append(e)
	return out


func _factor(why: Dictionary, key: String) -> Dictionary:
	for f: Dictionary in why["factors"]:
		if f["name"] == key:
			return f
	return {}


func _assert_clean(text: String, what: String) -> void:
	for prefix in RAW_PREFIXES:
		assert_bool(text.contains(prefix)).override_failure_message("%s: ham anahtar '%s*' görünüyor: %s" % [what, prefix, text.left(300)]).is_false()
	var low := text.to_lower()
	for word in FORBIDDEN:
		assert_bool(low.contains(word)).override_failure_message("%s: yasak sözcük '%s'" % [what, word]).is_false()


# --- 1. RED'in kendisi: sonuç, kayıt, görünür nedensellik ---

func test_green_plan_of_twelve_parcels_is_rejected_by_the_council_with_recorded_reasons() -> void:
	var r := _run(SEED_RED, GREEN)
	var h: PoliticsHandle = r["h"]
	var vote := _vote(h)
	assert_str(String(vote["status"])).is_equal("failed")
	assert_int(int(vote["no"])).is_greater(int(vote["yes"]))
	assert_int(int(vote["yes"]) + int(vote["no"]) + int(vote["abstain"])).is_equal(5)
	assert_bool(bool(vote["applied"])).override_failure_message("RED yürürlüğe bir şey yazmaz").is_false()
	# Oy dökümü = üye gerekçe kayıtları (her üyenin skoru eşiğe göre).
	var score_sum := 0
	var yes_n := 0
	var no_n := 0
	for pos: Dictionary in vote["positions"]:
		var rec := h.facade.reason(int(pos["reason_id"]))
		assert_object(rec).override_failure_message("%s gerekçe kaydı yok" % pos["member"]).is_not_null()
		score_sum += rec.score
		assert_bool((String(pos["position"]) == "yes") == (rec.score >= rec.threshold)).is_true()
		yes_n += 1 if String(pos["position"]) == "yes" else 0
		no_n += 1 if String(pos["position"]) == "no" else 0
	assert_int(yes_n).is_equal(int(vote["yes"]))
	assert_int(no_n).is_equal(int(vote["no"]))
	# Nedenler: altyapı doluluğu (uygulanabilirlik) her üyeyi aleyhe çeker, duruş uyumu lehe; toplam = skorlar.
	var why: Dictionary = vote["why"]
	assert_int(int(why["members"])).is_equal(5)
	assert_int(int(why["infra_load_pm"])).override_failure_message("bölge ~%100 dolu olmalı").is_greater_equal(990)
	var realism := _factor(why, "reason.factor.budget_realism")
	assert_int(int(realism["against"])).is_equal(5)
	assert_int(int(realism["net"])).is_less(0)
	var stance := _factor(why, "reason.factor.stance_distance")
	assert_int(int(stance["for"])).is_greater_equal(1)
	assert_int(int(stance["net"])).is_greater(0)
	var why_sum := 0
	for f: Dictionary in why["factors"]:
		why_sum += int(f["net"])
	assert_int(why_sum).override_failure_message("Σ etken net'i = Σ üye skoru").is_equal(score_sum)


func test_rejection_leaves_all_twelve_parcels_unplanned_and_makes_no_building_can03() -> void:
	var r := _run(SEED_RED, GREEN)
	var h: PoliticsHandle = r["h"]
	var cmd: CommandResult = r["cmd"]
	assert_str(String(_vote(h)["status"])).is_equal("failed")
	for id in r["ids"]:
		var st := h.facade.plan_state(int(id))
		assert_str(String(st.state)).is_equal("plan_rejected")
		assert_int(st.rejected_tick).is_greater_equal(0)
		var view: ParcelView = h.facade.parcel_views(PackedInt64Array([id]))[0]
		assert_str(String(view.zone)).override_failure_message("ret imarı yürürlüğe sokmaz").is_equal("")
		assert_str(String(view.pending_zone)).is_equal("")
		assert_str(String(view.development)).is_equal(String(ParcelView.DEVELOPMENT_VACANT))
	assert_int(EconomyQuery.totals(h.facade.game_state()).get("approvals", 0)).override_failure_message("ret bina yaratmaz").is_equal(0)
	var rejected := _events(h, &"event.zoning.plan_rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_int(rejected[0].command_id).is_equal(cmd.command_id)
	assert_int(rejected[0].subjects.size()).is_equal(PLAN_PARCELS)
	assert_int(_events(h, &"event.council.vote_failed").size()).is_equal(1)
	assert_int(_events(h, &"event.council.vote_passed").size()).is_equal(0)
	# Ret sonrası yeniden teklif mümkün (kapı kapanmaz).
	var again := h.facade.submit_command(SimCommand.zoning_propose(r["ids"], RESIDENTIAL))
	assert_bool(again.is_rejected()).override_failure_message(String(again.reason_key)).is_false()


func test_a_tied_vote_is_also_a_rejection_by_the_data_rule() -> void:
	var r := _run(SEED_RED_TIE, GREEN)
	var vote := _vote(r["h"])
	assert_str(String(vote["status"])).is_equal("failed")
	assert_int(int(vote["yes"])).is_equal(int(vote["no"]))
	assert_str(String(PlayablePolitics.config().council["tie_result"])).is_equal("fail")


# --- 2. Neden RED: nedensellik karşı örnekleri (aynı tohum, tek değişken) ---

func test_same_seed_other_zones_pass_so_the_green_axis_is_part_of_the_cause() -> void:
	for zone in [&"zone.mixed", RESIDENTIAL, &"zone.commercial"]:
		var vote := _vote(_run(SEED_RED, zone)["h"])
		assert_str(String(vote["status"])).override_failure_message("%s aynı tohumda geçmeli" % zone).is_equal("passed")


func test_same_seed_green_passes_when_the_region_has_free_infrastructure() -> void:
	# Tek değişken: bölge boş altyapı payı (M2RenderSupport.ISOLATE: eski %30 pay) => uygulanabilirlik etkeni lehe döner.
	var vote := _vote(_run(SEED_RED, GREEN, PLAN_PARCELS, {"playable": M2RenderSupport.NO_INFRA_CAP})["h"])
	assert_int(int(vote["why"]["infra_load_pm"])).override_failure_message("yük düşük olmalı").is_less(900)
	assert_str(String(vote["status"])).is_equal("passed")


func test_below_the_size_threshold_the_same_green_plan_never_reaches_the_council() -> void:
	var cfg := PlayablePolitics.config()
	var h := _handle(SEED_RED)
	var ids := _free_ids(int(cfg.council["plan_council_min_parcels"]) - 1)
	h.facade.submit_command(SimCommand.zoning_propose(ids, GREEN))
	h.facade.advance(30)
	assert_int((PoliticsState.data(h.facade.game_state())["council"]["votes"] as Array).size()).is_equal(0)
	assert_str(String(h.facade.plan_state(ids[0]).state)).is_equal("planned")


func test_noise_free_forecast_passes_the_red_vote_so_the_rejection_is_noise_driven() -> void:
	var h := _handle(SEED_RED)
	h.facade.submit_command(SimCommand.zoning_propose(_free_ids(PLAN_PARCELS), GREEN))
	h.facade.advance(3)
	var open: Dictionary = _vote(h)
	assert_str(String(open["status"])).is_equal("pending")
	var forecast := CouncilEngine.forecast(h.facade.game_state(), h.context, open)
	assert_bool(bool(forecast["passes"])).override_failure_message("gürültüsüz tahmin KABUL olmalı (RED = rastlantı payı)").is_true()
	assert_int(int(forecast["swing"])).override_failure_message("marjı gürültüden küçük üye olmalı").is_greater(0)
	h.facade.advance(27)
	assert_str(String(_vote(h)["status"])).is_equal("failed")


func test_red_is_chance_driven_not_structural() -> void:
	var reds: Array[int] = []
	for s in SEED_COUNT:
		var vote := _vote(_run(SEED_FIRST + s, GREEN)["h"])
		if String(vote["status"]) == "failed":
			reds.append(SEED_FIRST + s)
	assert_array(reds).override_failure_message("40 tohumda hiç RED yok: kural/veri değişmiş olabilir").is_not_empty()
	assert_array(reds).contains([SEED_RED, SEED_RED_TIE])
	assert_int(reds.size()).override_failure_message("RED yapısal hale gelmiş (%s)" % str(reds)).is_less(SEED_COUNT / 4)


# --- 3. Determinizm ---

func test_red_scenario_is_deterministic_and_survives_save_load() -> void:
	var a := _run(SEED_RED, GREEN)["h"] as PoliticsHandle
	var b := _run(SEED_RED, GREEN)["h"] as PoliticsHandle
	assert_str(a.facade.state_hash()).is_equal(b.facade.state_hash())
	assert_str(StateHash.of(_vote(a)["why"])).is_equal(StateHash.of(_vote(b)["why"]))
	var other := _run(SEED_RED + 1, GREEN)["h"] as PoliticsHandle
	assert_str(other.facade.state_hash()).override_failure_message("tohum kullanılmıyor").is_not_equal(a.facade.state_hash())
	var loaded := _handle(SEED_RED)
	var imported := loaded.facade.import_save(a.facade.export_save())
	assert_bool(imported.ok).override_failure_message(imported.message).is_true()
	assert_str(loaded.facade.state_hash()).is_equal(a.facade.state_hash())
	assert_str(String(_vote(loaded)["status"])).is_equal("failed")
	assert_str(String(loaded.facade.plan_state(_free_ids(1)[0]).state)).is_equal("plan_rejected")


# --- 4. RED sonrası UI / olay akışı (gerçek facade -> gerçek paneller) ---

func test_council_panel_and_event_texts_show_the_rejection_without_errors() -> void:
	var r := _run(SEED_RED, GREEN)
	var h: PoliticsHandle = r["h"]
	var vote := _vote(h)
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 2400.0)
	add_child(holder)
	auto_free(holder)
	var panel := CouncilPanel.create(ctx, h.facade)
	holder.add_child(panel)
	panel.size = holder.size
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"council.outcome.rejected"))
	assert_str(text).contains(UiText.t(&"council.tally", {"yes": vote["yes"], "no": vote["no"], "abstain": vote["abstain"]}))
	assert_str(text).contains(UiText.t(&"council.why.title"))
	assert_str(text).contains(UiText.t(&"council.why.against"))
	assert_str(text).contains(UiText.t(&"reason.factor.budget_realism"))
	assert_str(text).contains(UiText.t(&"council.why.infra", {"region": UiText.humanize(String(vote["why"]["infra_region"])), "load": vote["why"]["infra_load_pm"]}))
	assert_bool(text.contains(UiText.t(&"council.why.none"))).is_false()
	_assert_clean(text, "meclis paneli")
	panel.refresh()
	assert_str(panel.joined_text()).override_failure_message("refresh sonrası metin değişti").is_equal(text)
	# Olay metinleri ve parsel durum satırı.
	for key in [&"event.council.vote_opened", &"event.council.vote_failed", &"event.zoning.plan_rejected"]:
		var events := _events(h, key)
		assert_int(events.size()).is_equal(1)
		var line := UiText.event_text(events[0])
		assert_bool(line != "" and not line.contains("event.")).override_failure_message("%s: '%s'" % [key, line]).is_true()
	var plan_text := PlanStateText.label(h.facade.plan_state(int(r["ids"][0])))
	assert_str(plan_text).contains("reddedildi")
	assert_bool(plan_text.contains("plan.state")).is_false()
	assert_array(UiText.missing_keys()).is_empty()


func test_real_hud_zoning_panel_flow_to_a_rejection_notifies_and_allows_resubmission() -> void:
	var h := _handle(SEED_RED)
	var f := h.facade
	var ids := _free_ids(PLAN_PARCELS)
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(f, UiTestSupport.platform(&"desktop"))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = DESKTOP
	hud.refresh()
	auto_free(hud)
	var d := DecisionPanels.attach(hud, f, Callable(), false)
	d.open_zoning(ids)
	var panel := d.zoning_panel()
	panel.choose_use(GREEN)
	assert_str(panel.route_note_text()).contains("Neden meclise gidiyor")
	panel.send()
	for _day in 32:
		f.advance(1)
		hud.refresh()
	assert_str(String(_vote(h)["status"])).is_equal("failed")
	# Bildirim şeridi: ret olayları (ham anahtarsız).
	var rows := " | ".join(hud.strip.row_texts())
	assert_str(rows).contains(UiText.t(&"event.zoning.plan_rejected"))
	_assert_clean(rows, "bildirim şeridi")
	# Meclis ve gündem panelleri RED sonrası açılır, yenilenir, hatasız.
	d.open_council()
	assert_str(d.council_panel().joined_text()).contains(UiText.t(&"council.outcome.rejected"))
	hud.refresh()
	d.open_agenda()
	assert_object(d.agenda_panel()).is_not_null()
	d.agenda_panel().refresh()
	_assert_clean(d.agenda_panel().joined_text(), "gündem paneli")
	# İmar paneli aynı parsellerle yeniden açılır: ret durumu görünür, yeniden teklif gönderilebilir.
	d.open_zoning(ids)
	var again := d.zoning_panel()
	assert_str(again.joined_text()).contains("reddedildi")
	again.choose_use(RESIDENTIAL)
	again.send()
	f.advance(1)
	assert_str(String(f.plan_state(int(ids[0])).state)).is_equal("proposed")
	assert_array(UiText.missing_keys()).is_empty()
