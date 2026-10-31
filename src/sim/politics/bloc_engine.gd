class_name BlocEngine
extends RefCounted
## Seçmen/çıkar kesimleri (T-017 ölçüt 1, characters-npc §6.5-§6.6, SIM-05/SIM-09/SIM-12): kesimi hane kohortundan
## türetir, bölge sinyallerinden ayrı iki defter (şikâyet, memnuniyet) biriktirir ve değişimde `bloc.react`
## (basamaklı) ile `bloc.support` kararlarını gerekçeli verir.
##
## Tek skor yok: şikâyet ve memnuniyet ayrı defterlerdir; bir kesim aynı anda ikisini de taşıyabilir. Tepki yalnız
## durum DEĞİŞİMİNDE ya da sakin değilse `recheck_days`ta değerlendirilir; her değerlendirme basamak başına kayıt yazar,
## bu yüzden tarama başına kayıt üst sınırı vardır (ReasonLog hacmi, T-013/T-016 riski).
## Kesim kimliği roster'daki `actor.bloc.<n>` yuvasıdır (kimlik sürekliliği); yuva -> kohort eşlemesi veridir.

const SCALE := 1000


## Başlangıç (PoliticsSystem, her gün başlayana dek): ekonomi hazırsa bölge başına başlangıç konut arzını (baseline)
## kaydeder; `supply_added` bundan sonra eklenen arzı ölçer. Başladıysa ya da ekonomi hazır değilse hiçbir şey yapmaz.
static func ensure_started(state: GameState, ctx: PoliticsContext) -> void:
	var pol := PoliticsState.data(state)
	if int(pol["started_tick"]) >= 0:
		return
	var rows := EconomyQuery.region_stats(state, ctx.economy)
	if rows.is_empty():
		return
	pol["started_tick"] = state.tick
	_region_signals(pol, rows)


## Haftalık tarama (PoliticsSystem). Ekonomi hazır değilse (ilk tick geçmedi) hiçbir şey yapmaz.
static func scan(state: GameState, ctx: PoliticsContext) -> void:
	var rows := EconomyQuery.region_stats(state, ctx.economy)
	if rows.is_empty():
		return
	var pol := PoliticsState.data(state)
	var by_region := _region_signals(pol, rows, _reaction_signals(state, ctx, rows))
	_update_service(pol, rows, int(ctx.politics.cadence["scan_days"]))
	var total_size := 0
	var order: Array[String] = PoliticsState.bloc_keys(state)
	for key in order:
		var cohort := ctx.politics.cohort(pol["blocs"][key]["cohort"])
		var exposure := BlocSignals.exposure(rows, cohort["size_source"])
		var bloc: Dictionary = pol["blocs"][key]
		bloc["exposure"] = exposure["shares"]
		bloc["size"] = exposure["size"]
		total_size += int(exposure["size"])
	var budget := int(ctx.politics.cadence["max_react_records_per_scan"])
	for key in order:
		budget -= _scan_bloc(state, ctx, key, by_region, total_size, budget)


## Kesimin güncel görünümü (salt okunur kopya): GroupReactionView üretimi için ham değerler.
static func bloc_view(state: GameState, key: String) -> Dictionary:
	var bloc: Variant = PoliticsState.data(state).get("blocs", {}).get(key, null)
	return (bloc as Dictionary).duplicate(true) if bloc is Dictionary else {}


# --- Sinyaller ---

## {bölge: {sinyal: pm}} ve ilk taramada başlangıç konut arzı (baseline).
static func _region_signals(pol: Dictionary, rows: Array[Dictionary], extra: Dictionary = {}) -> Dictionary:
	var baselines: Dictionary = pol["baselines"]
	var out := {}
	for row in rows:
		var code := String(row["code"])
		if not baselines.has(code):
			baselines[code] = int(row["res_built"]) + int(row["res_pipe"])
		out[code] = BlocSignals.of_region(row, int(baselines[code]))
		if extra.has(code):  # T-042b: yalnız kamulaştırma olduysa (yolsuz koşuda bu anahtarlar HİÇ yazılmaz)
			(out[code] as Dictionary).merge(extra[code])
	return out


## T-042b · Yerinden edilme/yakınlık sinyalleri {bölge: {displacement, proximity}} (kamulaştırma yoksa boş).
static func _reaction_signals(state: GameState, ctx: PoliticsContext, rows: Array[Dictionary]) -> Dictionary:
	var out := {}
	if not PublicWorksState.has_reactions(state):
		return out
	var window := int(ctx.politics.blocs["reaction_window"])
	for row in rows:
		var code := String(row["code"])
		var latent := int(row["latent_hh"])
		out[code] = {
			"displacement": BlocSignals.reaction_pm(PublicWorksState.reaction_rows(state, "displaced", code),
				state.tick, window, latent, BlocSignals.SCALE),
			"proximity": BlocSignals.reaction_pm(PublicWorksState.reaction_rows(state, "nearby", code),
				state.tick, window, latent, 1),
		}
	return out


## Hizmet aşımı günleri ve hane büyümesi (PE-07 girdileri): aşım sürerken gün sayacı tarama aralığı kadar ilerler.
@warning_ignore("integer_division")
static func _update_service(pol: Dictionary, rows: Array[Dictionary], scan_days: int) -> void:
	var service: Dictionary = pol["service"]
	for row in rows:
		var code := String(row["code"])
		var overloaded := int(row["infra_load_pm"]) > SCALE
		service["overload_days"][code] = int(service["overload_days"].get(code, 0)) + scan_days if overloaded else 0
		var before := int(service["latent"].get(code, int(row["latent_hh"])))
		service["growth"][code] = clampi((int(row["latent_hh"]) - before) * SCALE / maxi(before, 1), -SCALE, SCALE)
		service["latent"][code] = int(row["latent_hh"])


## Şikâyet kurallarının seviye toplamı en yüksek bölge (payı `min_share` ve üstü); hepsi sıfırsa en büyük paylı bölge.
@warning_ignore("integer_division")
static func _hot_region(cohort: Dictionary, by_region: Dictionary, shares: Dictionary, min_share: int) -> String:
	var codes: Array = shares.keys()
	codes.sort()
	var best := ""
	var best_level := 0
	var largest := ""
	var largest_share := 0
	for code: String in codes:
		if int(shares[code]) > largest_share:
			largest_share = int(shares[code])
			largest = code
		if int(shares[code]) < min_share:
			continue
		var level := 0
		for rule: Dictionary in cohort["grievance_rules"]:
			var span: int = int(rule["hi"]) - int(rule["lo"])
			var value := int(by_region.get(code, {}).get(rule["signal"], 0))
			level += clampi((value - int(rule["lo"])) * SCALE / span, 0, SCALE) * int(rule["gain"]) / SCALE
		if level > best_level:
			best_level = level
			best = code
	return best if not best.is_empty() else largest


# --- Kesim taraması ---

## Kesimi günceller; harcanan gerekçe kaydı sayısını döner.
static func _scan_bloc(state: GameState, ctx: PoliticsContext, key: String, by_region: Dictionary, total_size: int,
		budget: int) -> int:
	var pol := PoliticsState.data(state)
	var bloc: Dictionary = pol["blocs"][key]
	var cohort := ctx.politics.cohort(bloc["cohort"])
	var actor := ActorStore.actor_ref(state, key)
	var signals := {}
	var peak: bool = ctx.politics.blocs["blend_mode"] == "peak"
	var min_share := int(ctx.politics.blocs["min_share"])
	var names: Array[String] = BlocSignals.NAMES.duplicate()
	if PublicWorksState.has_reactions(state):
		names.append_array(BlocSignals.OPTIONAL_NAMES)
	for signal_name in names:
		signals[signal_name] = BlocSignals.blend(by_region, bloc["exposure"], signal_name, peak, min_share)
	bloc["signals"] = signals
	bloc["hot_region"] = _hot_region(cohort, by_region, bloc["exposure"], min_share)
	actor["state"]["size"] = bloc["size"]
	var rederive := int(ctx.politics.cadence["rederive_days"])
	if int(bloc["derived_tick"]) < 0 or state.tick - int(bloc["derived_tick"]) >= rederive:
		derive(actor, cohort, signals)
		bloc["derived_tick"] = state.tick
	_apply_rules(actor["state"], "grievances", cohort["grievance_rules"], signals,
		int(ctx.politics.blocs["decay_grievance"]))
	_apply_rules(actor["state"], "satisfaction", cohort["satisfaction_rules"], signals,
		int(ctx.politics.blocs["decay_satisfaction"]))
	bloc["G"] = _weighted(actor["salience"], actor["state"]["grievances"])
	bloc["S"] = _weighted(actor["salience"], actor["state"]["satisfaction"])
	bloc["amp"] = MediaEngine.amp_for(state, ctx, key)
	var share := int(bloc["size"]) * SCALE / maxi(total_size, 1)
	bloc["org"] = clampi(int(ctx.politics.blocs["organizer_base"])
		+ int(ctx.politics.blocs["organizer_k"]) * share / SCALE, 0, SCALE)
	if not _should_evaluate(state, ctx, bloc) or budget <= 0:
		return 0
	return _evaluate(state, ctx, key, bloc, actor)


## Öncelik ve eksen konumunu kohort kurallarından yeniden türetir: base + k * (kaynak - 500) / 500.
@warning_ignore("integer_division")
static func derive(actor: Dictionary, cohort: Dictionary, signals: Dictionary) -> void:
	var priorities := {}
	for rule: Dictionary in cohort["priorities"]:
		if _usable(rule["source"], signals):
			priorities[rule["id"]] = clampi(_rule_value(rule, signals), 0, SCALE)
	actor["salience"] = priorities
	var stances := {}
	for rule: Dictionary in cohort["stances"]:
		if _usable(rule["source"], signals):
			stances[rule["id"]] = clampi(_rule_value(rule, signals), -SCALE, SCALE)
	actor["stance"] = stances
	for book_name in ["grievances", "satisfaction"]:
		if not actor["state"].has(book_name):
			actor["state"][book_name] = {}


## T-042b · İsteğe bağlı sinyale (`displacement`/`proximity`) bağlı kural, sinyal henüz yokken (kamulaştırma olmadı)
## hiç çalışmaz: durum anahtarı bile yazılmaz (kamulaştırmasız koşuların hash'i değişmez).
static func _usable(signal_name: Variant, signals: Dictionary) -> bool:
	return not (BlocSignals.OPTIONAL_NAMES.has(str(signal_name)) and not signals.has(str(signal_name)))


@warning_ignore("integer_division")
static func _rule_value(rule: Dictionary, signals: Dictionary) -> int:
	if str(rule["source"]).is_empty():
		return int(rule["base"])
	return int(rule["base"]) + int(rule["k"]) * (int(signals.get(rule["source"], 0)) - 500) / 500


## Defter = önceki * (1000 - çürüme) / 1000 + Σ seviye * kazanç / 1000 (seviye = sinyalin lo..hi'ye göre 0..1000'i).
@warning_ignore("integer_division")
static func _apply_rules(astate: Dictionary, book_name: String, rules: Array, signals: Dictionary,
		decay: int) -> void:
	var book: Dictionary = astate.get(book_name, {})
	var topics: Array = book.keys()
	var active: Array = rules.filter(func(rule: Dictionary) -> bool: return _usable(rule["signal"], signals))
	for rule: Dictionary in active:
		if not topics.has(rule["topic"]):
			topics.append(rule["topic"])
	topics.sort()
	for topic: String in topics:
		book[topic] = int(book.get(topic, 0)) * (SCALE - decay) / SCALE
	for rule: Dictionary in active:
		var span: int = int(rule["hi"]) - int(rule["lo"])
		var level := clampi((int(signals.get(rule["signal"], 0)) - int(rule["lo"])) * SCALE / span, 0, SCALE)
		book[rule["topic"]] = clampi(int(book[rule["topic"]]) + level * int(rule["gain"]) / SCALE, 0, SCALE)
	astate[book_name] = book


## Öncelik ağırlıklı defter düzeyi, 0..1000 (characters-npc §6.5): G = Σ öncelik/1000 x defter, tavan 1000.
@warning_ignore("integer_division")
static func _weighted(priorities: Dictionary, book: Dictionary) -> int:
	var topics: Array = priorities.keys()
	topics.sort()
	var total := 0
	for topic: String in topics:
		total += int(priorities[topic]) * int(book.get(topic, 0)) / SCALE
	return clampi(total, 0, SCALE)


## Konu: öncelik * defter değeri en büyük olan (eşitlikte sözlük sırası).
static func dominant_topic(priorities: Dictionary, book: Dictionary) -> String:
	var topics: Array = priorities.keys()
	topics.sort()
	var best := ""
	var best_value := 0
	for topic: String in topics:
		var value := int(priorities[topic]) * int(book.get(topic, 0))
		if value > best_value:
			best_value = value
			best = topic
	return best


# --- Tepki kararı ---

static func _should_evaluate(state: GameState, ctx: PoliticsContext, bloc: Dictionary) -> bool:
	var last: Dictionary = bloc["eval"]
	var activity := maxi(int(bloc["G"]), int(bloc["S"]))
	if int(last["tick"]) < 0:
		return activity >= int(ctx.politics.cadence["activity_floor"])
	var trigger := int(ctx.politics.cadence["react_trigger_min"])
	var changed := absi(int(bloc["G"]) - int(last["G"])) >= trigger or absi(int(bloc["S"]) - int(last["S"])) >= trigger \
		or absi(int(bloc["amp"]) - int(last["amp"])) >= trigger
	var restless: bool = last["reaction"] != PoliticsState.NEUTRAL \
		and state.tick - int(last["tick"]) >= int(ctx.politics.cadence["recheck_days"])
	return changed or restless


## Kararı verir, durumu ve olayları yazar; yazılan gerekçe kaydı sayısını döner.
@warning_ignore("integer_division")
static func _evaluate(state: GameState, ctx: PoliticsContext, key: String, bloc: Dictionary,
		actor: Dictionary) -> int:
	var player := ActorStore.protagonist_key(state, ctx.actors)
	var trust: Dictionary = ActorInputs.relation_factors(state, ctx.actors, key, player)["trust_in_player"]
	var causes := EventCauses.region_projects(state, ctx, bloc["exposure"])
	var subjects := PackedStringArray([key])
	subjects.append_array(causes["parcel_refs"])
	var parents: PackedInt64Array = causes["reason_ids"]
	var react_id: String = ctx.politics.blocs["react_decision"]
	var shared := {"grievance_level": bloc["G"], "satisfaction_level": bloc["S"],
		"media_amplification": {"value": bloc["amp"], "source_ref": MediaEngine.organ_key(ctx)},
		"trust_in_player": trust}
	var react_factors := shared.duplicate()
	react_factors["organizer_capacity"] = bloc["org"]
	var react := ActorDecision.evaluate(state, ctx.actors, key, react_id, react_factors, subjects, parents)
	var support := ActorDecision.evaluate(state, ctx.actors, key, ctx.politics.blocs["support_decision"], shared,
		subjects, parents)
	if not react["ok"] or not support["ok"]:
		push_error("BlocEngine: karar verilemedi (%s / %s)" % [react.get("error", ""), support.get("error", "")])
		return 0
	var written: int = react["records"].size() + support["records"].size()
	PoliticsState.count(state, "reason_records", written)
	var previous: Dictionary = bloc["eval"]
	var topic := dominant_topic(actor["salience"], actor["state"]["grievances"] if int(bloc["G"]) >= int(bloc["S"])
		else actor["state"]["satisfaction"])
	var outcome := _reaction_of(ctx, react, support)
	var ids := PackedInt64Array()
	for rec: Dictionary in react["records"]:
		ids.append(rec["reason_id"])
	ids.append(support["records"][0]["reason_id"])
	var net := int(bloc["S"]) - int(bloc["G"])
	var shift := net - (int(previous["S"]) - int(previous["G"]))
	if absi(shift) > 0 and not player.is_empty():
		ActorMemory.apply_event(state, ctx.actors, key, {"topic_id": topic if not topic.is_empty()
			else ctx.actors.topic_ids[0], "valence": clampi(shift, -SCALE, SCALE), "magnitude": clampi(absi(shift), 0, SCALE),
			"attribution": int(ctx.politics.blocs["attribution"]), "attributed_to": player, "source_ref": "reason.%d" % ids[0]})
	var trust_after := int(ActorStore.relation(state, ctx.actors, key, player)["trust"]) if not player.is_empty() else 0
	# Tutum (kesim başına, toplam skor değil): oyuncuya güven + bu kesimin gördüğü medya tonu + ayrı defterlerin farkı.
	var stance := ActorMath.clamp_permille(trust_after + MediaEngine.tone_for(state, ctx, key) / 2 + net / 2)
	var cause_refs := PackedStringArray()
	cause_refs.append_array(causes["parcel_refs"])
	bloc["eval"] = {
		"tick": state.tick, "G": bloc["G"], "S": bloc["S"], "amp": bloc["amp"], "tier": outcome["tier"],
		"reaction": outcome["reaction"], "intensity": outcome["intensity"], "stance": stance,
		"stance_delta": stance - int(previous["stance"]), "topic": topic, "reason_ids": Array(ids),
		"cause_refs": Array(cause_refs),
	}
	if outcome["reaction"] != previous["reaction"] or outcome["tier"] != previous["tier"]:
		_publish(state, ctx, key, bloc, ids, subjects)
	return written


## Basamak ya da destek sonucu -> tepki. Tepki yoğunluğu o kararın skoru (0..1000); eşit/yüksekte basamak kazanır.
static func _reaction_of(ctx: PoliticsContext, react: Dictionary, support: Dictionary) -> Dictionary:
	var tier := str(react["reached_tier"])
	var tier_score := 0
	for rec: Dictionary in react["records"]:
		if rec["tier"] == tier and rec["outcome"] == ReasonLog.OUTCOME_POSITIVE:
			tier_score = int(rec["score"])
	var support_rec: Dictionary = support["records"][0]
	var supported: bool = support_rec["outcome"] == ReasonLog.OUTCOME_POSITIVE
	if not tier.is_empty() and (not supported or tier_score >= int(support_rec["score"])):
		return {"tier": tier, "reaction": ctx.politics.blocs["tier_reactions"][tier],
			"intensity": clampi(tier_score, 0, SCALE)}
	if supported:
		return {"tier": "", "reaction": "support", "intensity": clampi(int(support_rec["score"]), 0, SCALE)}
	return {"tier": "", "reaction": PoliticsState.NEUTRAL, "intensity": 0}


## Tepki değişimi: `group.reacted` olayı ve medya haber adayı.
@warning_ignore("integer_division")
static func _publish(state: GameState, ctx: PoliticsContext, key: String, bloc: Dictionary, ids: PackedInt64Array,
		subjects: PackedStringArray) -> void:
	var eval_data: Dictionary = bloc["eval"]
	var reaction: String = eval_data["reaction"]
	var message := "event.group.%s" % reaction if reaction != PoliticsState.NEUTRAL else "event.group.calmed"
	SimEventLog.emit(state, SimEvent.KIND_GROUP_REACTED, StringName(message), subjects,
		{"tier": eval_data["tier"], "intensity": eval_data["intensity"], "topic": eval_data["topic"]}, ids, 0,
		StringName(key))
	PoliticsState.count(state, "events_emitted")
	if reaction == PoliticsState.NEUTRAL:
		return
	var total := 0
	for other in PoliticsState.bloc_keys(state):
		total += int(PoliticsState.data(state)["blocs"][other]["size"])
	MediaEngine.queue_story(state, {
		"kind": "support" if reaction == "support" else "protest", "topic": eval_data["topic"], "subject": key,
		"conflict": eval_data["intensity"], "scale": int(bloc["size"]) * SCALE / maxi(total, 1),
		"fact": int(bloc["S"]) - int(bloc["G"]), "parent_ids": Array(ids).slice(0, int(ctx.politics.cadence["cause_cap"])),
		"key": "bloc|%s|%s" % [key, reaction],
	})
