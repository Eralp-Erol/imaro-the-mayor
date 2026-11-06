extends "res://tests/sim/politics/reaction_world_base.gd"
## B-081 (D-021, SIM-12): yıkım sonrası meclis güveni düşünce NEDENİ HUD şeridinde görünür. GERÇEK `SimFacadeImpl`:
## satır yalnız sim'in `decision.council.displacement_trust` neden kaydından (positive = kesinti yürürlükte) gelir.
## Yıkım yoksa / toparlanınca satır yoktur. Ham anahtar ekrana çıkmaz.

const TRUST := {"enabled": true, "decision": "decision.council.displacement_trust", "cohorts": ["housed"],
	"window_days": 30, "threshold_households": 2, "drop_per_household_pm": 10, "cap_pm": 400,
	"recover_per_scan_pm": 400}


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = true


func after_test() -> void:
	UiText.reset()


func _road_world(expropriate: bool) -> PoliticsHandle:
	var edit := func(files: Dictionary) -> void:
		files["reactions"] = _raw_reactions()
		files["reactions"]["council_trust"] = TRUST.duplicate(true)
	return _world(expropriate, edit)["handle"]


func _strip() -> NotificationStrip:
	var s := NotificationStrip.create(UiContext.for_profile_name(&"desktop"))
	add_child(s)
	return auto_free(s)


func test_a_demolition_trust_drop_shows_one_plain_line_with_the_recorded_member_count() -> void:
	var h := _road_world(true)
	h.facade.advance(14)
	var members := CouncilTrustNotice.affected_members(h.facade)
	assert_int(members).override_failure_message("housed kesimini temsil eden 3 üye etkilenmeli").is_equal(3)
	var strip := _strip()
	strip.set_trust_notice(members)
	assert_bool(strip.visible).is_true()
	assert_str(strip.trust_text()).is_equal("Meclis güveni düştü: yıkım kararı, evsiz kalan aileler (3 üye)")
	assert_bool(strip.trust_text().contains("reason.") or strip.trust_text().contains("strip.")).is_false()


func test_no_demolition_means_no_line_and_a_hidden_strip() -> void:
	var h := _road_world(false)
	h.facade.advance(14)
	assert_int(CouncilTrustNotice.affected_members(h.facade)).is_equal(0)
	var strip := _strip()
	strip.set_trust_notice(0)
	assert_bool(strip.visible).is_false()
	assert_str(strip.trust_text()).is_equal("")
	assert_int(CouncilTrustNotice.strip_text(0).length()).is_equal(0)


func test_the_line_disappears_once_the_trust_has_recovered() -> void:
	var h := _road_world(true)
	h.facade.advance(14)
	assert_int(CouncilTrustNotice.affected_members(h.facade)).is_greater(0)
	h.facade.advance(400)
	assert_int(CouncilTrustNotice.affected_members(h.facade))\
		.override_failure_message("toparlanınca (son kayıt negative) satır olmamalı").is_equal(0)
	var strip := _strip()
	strip.set_trust_notice(3)
	strip.set_trust_notice(0)
	assert_str(strip.trust_text()).is_equal("")


func test_a_negative_member_count_is_treated_as_no_notice() -> void:
	var strip := _strip()
	strip.set_trust_notice(-1)
	assert_bool(strip.visible).is_false()
	assert_str(strip.trust_text()).is_equal("")
	assert_int(CouncilTrustNotice.strip_text(-5).length()).is_equal(0)


func test_a_changed_member_count_updates_the_one_line_in_place() -> void:
	var strip := _strip()
	strip.set_trust_notice(3)
	var rows_before := strip.get_child_count()
	assert_str(strip.trust_text()).contains("3 üye")
	strip.set_trust_notice(1)
	assert_str(strip.trust_text()).contains("1 üye")
	assert_str(strip.trust_text()).not_contains("3 üye")
	assert_bool(strip.visible).is_true()
	assert_int(strip.get_child_count()).override_failure_message(
		"sayı değişince satır çoğalmamalı, aynı satır güncellenmeli").is_equal(rows_before)


func test_repeating_the_same_member_count_adds_no_row() -> void:
	var strip := _strip()
	strip.set_trust_notice(2)
	var rows_before := strip.get_child_count()
	for _i in 5:
		strip.set_trust_notice(2)
	assert_int(strip.get_child_count()).is_equal(rows_before)
	assert_str(strip.trust_text()).contains("2 üye")
