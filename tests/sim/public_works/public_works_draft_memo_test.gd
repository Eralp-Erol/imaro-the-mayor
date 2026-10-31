extends GdUnitTestSuite
## Tick maliyeti işi (T-049): `PublicWorksContext.draft` aynı ağ sürümünde (graph_version) AYNI taslağı bir kez denetler
## (doğrulama + uygulama + RoadDraftCheck.apply üç kez denetlemesin), ama ağ değişince eski cevabı ASLA vermez.
## Sonuç değerleri önbelleksiz hesapla aynıdır; `apply_checked` = `apply`.

const P := preload("res://tests/sim/public_works/public_works_support.gd")


func test_repeated_draft_gives_equal_results_and_caller_mutation_cannot_poison_it() -> void:
	var run := P.setup()
	var ctx: PublicWorksContext = run["ctx"]
	var first := ctx.draft(P.spur_a_cm(), &"local")
	assert_bool(first["ok"]).is_true()
	var snapshot := first.duplicate(true)
	first["ok"] = false
	first["length_cm"] = -1
	var second := ctx.draft(P.spur_a_cm(), &"local")
	assert_dict(second).is_equal(snapshot)


func test_draft_follows_the_network_after_it_changes_and_after_undo() -> void:
	var run := P.setup()
	var ctx: PublicWorksContext = run["ctx"]
	var net: WorldNetwork = run["net"]
	assert_bool(ctx.draft(P.spur_a_cm(), &"local")["ok"]).is_true()
	var applied := RoadDraftCheck.apply(net, RoadDraftCheck.points_from_cm(P.spur_a_cm()), &"local", ctx.rules)
	assert_bool(applied["applied"]).is_true()
	var after := ctx.draft(P.spur_a_cm(), &"local")  # aynı yol artık çift: eski "ok" cevabı verilemez
	assert_bool(after["ok"]).is_false()
	assert_str(String(after["reason"])).is_equal(String(RoadDraftCheck.REASON_DUPLICATE))
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_bool(ctx.draft(P.spur_a_cm(), &"local")["ok"]).is_true()


func test_draft_distinguishes_class_and_points() -> void:
	var run := P.setup()
	var ctx: PublicWorksContext = run["ctx"]
	var a := ctx.draft(P.spur_a_cm(), &"local")
	var b := ctx.draft(P.spur_b_cm(), &"local")
	assert_array(b["points"]).is_not_equal(a["points"])
	assert_bool(ctx.draft(P.detached_cm(), &"local")["ok"]).is_false()
	var bad_class := ctx.draft(P.spur_a_cm(), &"no_such_class")
	assert_bool(bad_class["ok"]).is_false()


func test_apply_checked_equals_apply() -> void:
	var ra := P.setup()
	var rb := P.setup()
	var net_a: WorldNetwork = ra["net"]
	var net_b: WorldNetwork = rb["net"]
	var rules: RoadDraftRules = (ra["ctx"] as PublicWorksContext).rules
	var pts := RoadDraftCheck.points_from_cm(P.spur_a_cm())
	var via_apply := RoadDraftCheck.apply(net_a, pts, &"local", rules)
	var checked := RoadDraftCheck.check(net_b, pts, &"local", rules)
	var checked_copy := checked.duplicate(true)
	var via_checked := RoadDraftCheck.apply_checked(net_b, checked, &"local", rules)
	assert_bool(via_apply["applied"]).is_true()
	assert_bool(via_checked["applied"]).is_true()
	assert_str(net_b.state_hash()).is_equal(net_a.state_hash())
	assert_str(net_b.graph_hash()).is_equal(net_a.graph_hash())
	assert_dict(checked).is_equal(checked_copy)  # girdi sonucu değiştirilmez (önbellek kopyası bozulmaz)


func test_apply_checked_refuses_a_failed_check_without_touching_the_network() -> void:
	var run := P.setup()
	var net: WorldNetwork = run["net"]
	var rules: RoadDraftRules = (run["ctx"] as PublicWorksContext).rules
	var before := net.graph_hash()
	var bad := RoadDraftCheck.check(net, RoadDraftCheck.points_from_cm(P.detached_cm()), &"local", rules)
	assert_bool(bad["ok"]).is_false()
	var out := RoadDraftCheck.apply_checked(net, bad, &"local", rules)
	assert_bool(out["applied"]).is_false()
	assert_str(net.graph_hash()).is_equal(before)
	assert_int(net.delta.ops.size()).is_equal(0)
