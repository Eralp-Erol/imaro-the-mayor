extends "res://tests/sim/politics/reaction_world_base.gd"
## B-010: gerekçe panelinde sim'in yazdığı HİÇBİR etken adı, aktör veya öğe başvurusu ham görünmez.
## Kaynaklar (VERİ ODAKLI): karar tabloları + olay şablonu sürücüleri + sim sabitleri (etken adları), aktör kadrosu
## ve olay sistemi aktörü (aktör türleri), `agenda.N`/`command.N`/`parcel.N` başvuruları. Yeni etken, tür ya da
## başvuru türü eklenip metni unutulursa bu test KIRILIR. Gerçek simde tepki zinciri de panelde taranır.

const RAW := "[a-z_]+(\\.[a-z0-9_]+)+"
const SYS_RAW := "\\bsys \\d"


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _factor_names() -> PackedStringArray:
	var out := PackedStringArray()
	var tables: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/decision_tables.json"))
	for id: String in (tables["decisions"] as Dictionary):
		for f: Dictionary in (tables["decisions"][id] as Dictionary).get("factors", []):
			out.append("reason.factor." + String(f["name"]))
	var events: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/politics/events.json"))
	for template_id: String in events["templates"]:
		var raw: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/politics/events/%s.json" % template_id))
		for d: Dictionary in raw.get("drivers", []):
			out.append("reason.factor." + String(d["name"]))
	out.append("reason.factor.hazard")
	out.append("reason.factor." + ReactionAgenda.SOURCE)
	out.append(String(ActorDecision.NOISE_FACTOR))
	out.append(EventEngine.FACTOR_PREFIX + "rng_draw")
	return out


func _actor_refs() -> PackedStringArray:
	var out := PackedStringArray()
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/roster_m2.json"))
	for a: Dictionary in roster["actors"]:
		out.append(String(a["key"]))
	var pol: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/politics/events.json"))
	out.append(String(pol["system_actor"]))
	return out


func test_every_factor_name_the_sim_can_record_has_a_turkish_label() -> void:
	var names := _factor_names()
	assert_bool(names.has("reason.factor.newsworthiness")).is_true()
	assert_bool(names.has("reason.factor.hazard")).is_true()
	var bad := PackedStringArray()
	for n in names:
		if not UiText.has(StringName(n)):
			bad.append(n)
	assert_array(bad).override_failure_message("etken adı metni yok: %s" % ", ".join(bad)).is_empty()


func test_every_actor_and_item_reference_reads_as_plain_turkish() -> void:
	var refs := _actor_refs()
	refs.append("agenda.1")
	refs.append("command.3")
	assert_bool(refs.has("actor.protagonist")).is_true()
	assert_bool(refs.has("actor.sys.1")).is_true()
	var bad := PackedStringArray()
	for r in refs:
		var text := UiText.humanize(r)
		var rx := RegEx.create_from_string(RAW)
		if rx.search(text) != null or text.begins_with("sys ") or text.is_empty():
			bad.append("%s -> '%s'" % [r, text])
		var parsed := ReasonAdapter.actor_of(StringName(r))
		if parsed != null and rx.search(UiText.actor_name(parsed)) != null:
			bad.append("actor_name(%s) -> '%s'" % [r, UiText.actor_name(parsed)])
	assert_array(bad).override_failure_message("ham başvuru: %s" % ", ".join(bad)).is_empty()
	assert_str(UiText.humanize("agenda.2")).is_equal("Gündem öğesi 2")


func test_actor_name_never_shows_a_raw_kind_for_any_roster_kind() -> void:
	var kinds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/kinds.json"))["kinds"]
	var bad := PackedStringArray()
	for kind: String in kinds:
		var text := UiText.actor_name(ActorRef.make(StringName(kind), 1))
		if text.begins_with(kind + " ") or text == kind:
			bad.append("%s -> '%s'" % [kind, text])
	var sys := UiText.actor_name(ActorRef.make(&"sys", 1))
	if sys.begins_with("sys"):
		bad.append("sys -> '%s'" % sys)
	assert_array(bad).override_failure_message("ham aktör türü: %s" % ", ".join(bad)).is_empty()


## Gerçek sim: yol -> 21+ gün sonrası kaydedilen HER gerekçe panelde taranır.
func test_real_sim_reaction_chain_reasons_show_no_raw_text() -> void:
	UiText.report_missing = true
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(30)
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(480.0, 1600.0)
	add_child(holder)
	auto_free(holder)
	var panel := ReasonPanel.create(ctx, h.facade)
	holder.add_child(panel)
	panel.size = holder.size
	var rx := RegEx.create_from_string(RAW)
	var sys_rx := RegEx.create_from_string(SYS_RAW)
	var bad := PackedStringArray()
	var seen := 0
	var seen_decisions := {}
	for id in range(1, 400):
		var rec := h.facade.reason(id)
		if rec == null:
			continue
		seen += 1
		seen_decisions[String(rec.decision_key)] = true
		panel.show_record(id)
		for t in panel.texts():
			if rx.search(t) != null or sys_rx.search(t) != null:
				bad.append("#%d %s: '%s'" % [id, rec.decision_key, t])
	assert_int(seen).is_greater(0)
	assert_bool(seen_decisions.has("decision.event.fire")).override_failure_message(
		"bu dünyada olay tetiklenmedi; tarama anlamsız (%s)" % ", ".join(seen_decisions.keys())).is_true()
	assert_array(bad).override_failure_message("ham metin:\n" + "\n".join(bad)).is_empty()
	assert_array(UiText.missing_keys()).override_failure_message(
		"eksik anahtarlar: %s" % ", ".join(UiText.missing_keys())).is_empty()
