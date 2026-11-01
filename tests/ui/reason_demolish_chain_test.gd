extends GdUnitTestSuite
## B-018: gerçek sim zinciri (kamulaştırmalı yol -> yıkım -> bütçe kalemleri) kaydedilen HER gerekçe kaydı gerekçe
## panelinde ham anahtar ya da "missing string key" üretmez. Sabit taraması: reason_decision_text_test.gd.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const B := preload("res://tests/sim/budget/budget_support.gd")
const RAW := "[a-z_]+(\\.[a-z0-9_]+)+"


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = true


func after_test() -> void:
	UiText.reset()


func test_demolish_chain_reasons_show_no_raw_text_or_missing_keys() -> void:
	var net := P.network()
	var stock := ListStockSource.create([
		{"parcel_id": 1, "use": "residential", "units": 10, "owner": 1},
		{"parcel_id": 5, "use": "residential", "units": 8, "owner": 1}])
	var handle := EconomyBootstrap.create(P.SEED, P.source(), EconomyTestSupport.config(P.economy_patch()), stock)
	var ctx := PublicWorksContext.create(net, RoadDraftRules.new(), PublicWorksConfig.load_default())
	var fake := FakeExpropriationWorld.new(net)
	fake.take(P.spur_b_cm(), [5])
	ctx.set_expropriation(fake)
	var facade: SimFacadeImpl = handle.facade
	facade.attach_public_works(ctx)
	facade.attach_budget(B.config())
	facade.advance(1)
	facade.submit_command(SimCommand.public_work_road(P.spur_b_cm(), &"local", true))
	facade.advance(2)
	var road_id := int(facade.public_works()[0].command_id)
	facade.submit_command(SimCommand.public_work_demolish(road_id))
	facade.advance(35)
	var ui := UiContext.for_profile_name(&"desktop")
	var holder: Control = auto_free(Control.new())
	holder.theme = UiTheme.build(ui)
	holder.size = Vector2(480.0, 1600.0)
	add_child(holder)
	var panel := ReasonPanel.create(ui, facade)
	holder.add_child(panel)
	panel.size = holder.size
	var rx := RegEx.create_from_string(RAW)
	var bad := PackedStringArray()
	var keys := {}
	for id in range(1, 300):
		var rec := facade.reason(id)
		if rec == null:
			continue
		keys[String(rec.decision_key)] = true
		panel.show_record(id)
		for t in panel.texts():
			if rx.search(t) != null:
				bad.append("#%d %s: '%s'" % [id, rec.decision_key, t])
	assert_bool(keys.has("decision.municipal.demolish_road")).override_failure_message(
		"yıkım gerekçesi yazılmadı: %s" % ", ".join(keys.keys())).is_true()
	assert_bool(keys.has("decision.budget.road_demolish")).is_true()
	assert_array(bad).override_failure_message("ham metin:\n" + "\n".join(bad)).is_empty()
	assert_array(UiText.missing_keys()).override_failure_message(
		"eksik anahtarlar: %s" % ", ".join(UiText.missing_keys())).is_empty()
