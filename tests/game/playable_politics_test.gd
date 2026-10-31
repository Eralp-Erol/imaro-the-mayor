extends GdUnitTestSuite
## T-043A köprüsü + D-011 Soru 4 · Oynanabilir kurulumun siyaset yapılandırması: "küçük plan doğrudan, BÜYÜK plan
## meclise" (eşikler veri, `data/game/playable_politics.json`; ÇALIŞMA DEĞERİ, kanon değil). Yalnız imar meclis yolu
## ve eşikler değişir; sim varsayılanı (GOLDEN A/B'nin kullandığı `data/politics/council.json`) ve bütçe yolu
## dokunulmaz.

const ENABLED := {"decision": {"unplanned_land_enabled": 1}}
const MIXED := &"zone.mixed"
const MEMBERS: Array[String] = ["actor.council.1", "actor.council.2", "actor.council.3", "actor.council.4",
	"actor.council.5"]


func _playable_handle(per_region: int = 6) -> PoliticsHandle:
	var econ := EconomyTestSupport.config(ENABLED)
	var h := PoliticsBootstrap.create(7, FacadeTestSupport.fixture_source(per_region), econ, null, null,
		PlayablePolitics.config())
	assert_object(h).is_not_null()
	return h


func _ids(h: PoliticsHandle, count: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for i in count:
		out.append(h.facade.parcel_ids()[i])
	return out


func test_playable_config_is_valid_and_gates_the_zoning_council_by_plan_size() -> void:
	var cfg := PlayablePolitics.config()
	assert_object(cfg).is_not_null()
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_bool(cfg.requires_council("zoning.propose")).override_failure_message("meclis yolu var (büyük planlar için)") \
		.is_true()
	assert_bool(cfg.requires_council("budget.propose")).is_true()
	assert_bool(cfg.plan_council_thresholds_active()).is_true()
	assert_int(cfg.council["plan_council_min_parcels"]).is_greater(1)


func test_sim_default_politics_still_requires_the_council_and_stays_unmutated_after_building_the_playable_one() -> void:
	PlayablePolitics.config()
	PlayablePolitics.config()
	var base := PoliticsConfig.load_default(ActorConfig.load_default())
	assert_bool(base.is_valid()).is_true()
	assert_bool(base.requires_council("zoning.propose")).override_failure_message("paylaşılan JSON kaynağı bozulmuş") \
		.is_true()
	assert_bool(base.plan_council_thresholds_active()).override_failure_message("sim varsayılanında eşik kapalı") \
		.is_false()


func test_small_proposal_takes_force_without_a_council_vote_on_the_playable_politics() -> void:
	var h := _playable_handle()
	var id := int(h.facade.parcel_ids()[0])
	h.facade.advance(1)
	var result := h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([id]), &"zone.mixed"))
	assert_bool(result.is_rejected()).is_false()
	h.facade.advance(6)
	var pending := CouncilEngine.pending_vote_for_parcel(h.state(), id)
	assert_int(pending).override_failure_message("küçük plan: oylama açılmaz").is_equal(0)
	assert_str(String(h.facade.plan_state(id).state)).is_equal("planned")


func test_large_proposal_goes_to_the_council_on_the_playable_politics_and_a_rejection_is_recorded() -> void:
	var h := _playable_handle()
	var min_parcels: int = PlayablePolitics.config().council["plan_council_min_parcels"]
	assert_int(h.facade.parcel_ids().size()).override_failure_message("fixture yetersiz").is_greater(min_parcels - 1)
	var ids := _ids(h, min_parcels)
	for member in MEMBERS:
		if ActorStore.has_actor(h.state(), member):
			ActorStore.actor_ref(h.state(), member)["stance"]["growth_vs_preservation"] = 1000
	h.facade.advance(1)
	assert_bool(h.facade.plan_preview(ids, MIXED).council_required).is_true()
	assert_bool(h.facade.plan_preview(_ids(h, 1), MIXED).council_required).is_false()
	var result := h.facade.submit_command(SimCommand.zoning_propose(ids, MIXED))
	assert_bool(result.is_rejected()).is_false()
	h.facade.advance(2)
	assert_int(CouncilEngine.pending_vote_for_parcel(h.state(), ids[0])).override_failure_message("oylama açılmalı") \
		.is_greater(0)
	assert_str(String(h.facade.plan_state(ids[0]).state)).is_equal("proposed")
	h.facade.advance(40)
	var resolved := String(h.facade.plan_state(ids[0]).state)
	assert_str(resolved).override_failure_message("muhafazakâr meclis büyük planı reddeder: " + resolved) \
		.is_equal("plan_rejected")
	var rejected := 0
	for e in h.facade.events_since(0):
		if e.message_key == &"event.zoning.plan_rejected":
			rejected += 1
	assert_int(rejected).is_equal(1)
	assert_int(EconomyQuery.totals(h.state()).get("approvals", 0)) \
		.override_failure_message("CAN-03: meclis bina yaratmaz").is_equal(0)
