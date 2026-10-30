extends GdUnitTestSuite
## T-043A köprüsü · Oynanabilir kurulumun siyaset yapılandırması: "meclis yok" (Q-014 AÇIK kalır; bayrak veri,
## `data/game/playable_politics.json`). Yalnız `requires_council.zoning.propose` değişir; sim varsayılanı
## (GOLDEN A/B'nin kullandığı `data/politics/council.json`) ve bütçe yolu dokunulmaz.


func test_playable_config_is_valid_and_turns_only_the_zoning_council_off() -> void:
	var cfg := PlayablePolitics.config()
	assert_object(cfg).is_not_null()
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_bool(cfg.requires_council("zoning.propose")).is_false()
	assert_bool(cfg.requires_council("budget.propose")).is_true()


func test_sim_default_politics_still_requires_the_council_and_stays_unmutated_after_building_the_playable_one() -> void:
	PlayablePolitics.config()
	PlayablePolitics.config()
	var base := PoliticsConfig.load_default(ActorConfig.load_default())
	assert_bool(base.is_valid()).is_true()
	assert_bool(base.requires_council("zoning.propose")).override_failure_message("paylaşılan JSON kaynağı bozulmuş") \
		.is_true()


func test_proposal_takes_force_without_a_council_vote_on_the_playable_politics() -> void:
	var econ := EconomyTestSupport.config({"decision": {"unplanned_land_enabled": 1}})
	var h := PoliticsBootstrap.create(7, FacadeTestSupport.fixture_source(6), econ, null, null, PlayablePolitics.config())
	assert_object(h).is_not_null()
	var id := int(h.facade.parcel_ids()[0])
	h.facade.advance(1)
	var result := h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([id]), &"zone.mixed"))
	assert_bool(result.is_rejected()).is_false()
	h.facade.advance(6)
	var pending := CouncilEngine.pending_vote_for_parcel(h.state(), id)
	assert_int(pending).override_failure_message("meclis yok: oylama açılmaz").is_equal(0)
	assert_str(String(h.facade.plan_state(id).state)).is_equal("planned")
