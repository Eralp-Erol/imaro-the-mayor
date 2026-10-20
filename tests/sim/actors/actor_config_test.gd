extends ActorTestBase
## T-016 ölçüt 1-2 · Aktör veri dosyaları (data/actors/*.json): yer tutucu içerik, şema doğrulama ve bozuk veride
## anlaşılır hata (SIM-05, SIM-11, CAN-06, CAN-10). Kanon koruması: ad/geçmiş/parti/rakip yok (Q-005..Q-010).


func test_default_data_loads_valid_and_exposes_the_m2_placeholder_roster() -> void:
	var cfg := config()
	assert_array(cfg.errors).is_empty()
	assert_int(cfg.roster.size()).is_equal(9)
	var keys: Array[String] = []
	for a: Dictionary in cfg.roster:
		keys.append(a["key"])
	var sorted_keys := keys.duplicate()
	sorted_keys.sort()
	assert_array(keys).override_failure_message("kadro anahtar sırasına göre sıralı olmalı").is_equal(sorted_keys)
	assert_str(cfg.campaign_template).is_equal("m2_test")
	assert_int(cfg.digest.length()).is_equal(64)
	assert_array(cfg.trait_ids).contains(["volatility", "integrity"])
	assert_array(cfg.table_ids()).is_equal(["bloc.react", "council.vote", "interest.lobby", "media.coverage",
		"remote.policy_move"])


func test_protagonist_is_a_bare_placeholder_without_name_or_background() -> void:
	var cfg := config()
	var player := cfg.actor_template(PLAYER)
	assert_bool(player.is_empty()).is_false()
	assert_str(player["kind"]).is_equal("protagonist")
	assert_str(player["name_key"]).override_failure_message("ad anahtarı türetilir, ad değil").is_equal(PLAYER + ".name")
	assert_dict(player["traits"]).is_empty()
	assert_dict(player["stance"]).is_empty()
	assert_array(player["state"]["profile_slots"]).override_failure_message("geçmiş AÇIK: boş").is_empty()
	var protagonists := 0
	for a: Dictionary in cfg.roster:
		protagonists += 1 if a["kind"] == "protagonist" else 0
	assert_int(protagonists).is_equal(1)


func test_data_files_carry_no_names_parties_rivals_money_symbols_or_the_deleted_poc_name() -> void:
	var text := raw_text_of_all_files()
	# Parçalı yazım: bu dosya tarama kapsamında olmasa da yasak ad bir yerde düz metin olarak durmasın.
	var banned: Array[String] = ["Il" + "gın", "Il" + "gin", "Orv" + "en", "₺", "€", "$", "lira", "party.a", "party.b"]
	for token in banned:
		assert_bool(text.contains(token)).override_failure_message("yasak/AÇIK içerik veride: %s" % token).is_false()
	var cfg := config()
	for a: Dictionary in cfg.roster:
		if a["kind"] == "council" or a["kind"] == "bloc":
			assert_bool(a["state"].get("party_key", null) == null) \
				.override_failure_message("M2'de parti yok: %s" % a["key"]).is_true()
		assert_bool(a["kind"] == "rival" or a["kind"] == "story") \
			.override_failure_message("M2'de rakip/hikâye yok").is_false()


func test_actor_templates_carry_defaults_for_omitted_optional_fields() -> void:
	var cfg := config()
	var media := cfg.actor_template(MEDIA_1)
	assert_str(media["campaign_id"]).is_equal("m2_test")
	assert_str(media["lod"]).is_equal("full")
	assert_dict(media["resources"]).is_equal({"political": 0, "money": 0, "organization": 0})
	assert_int(media["state"]["credibility"]).is_equal(600)
	assert_int(media["state"]["reach"][BLOC_1]).is_equal(600)
	assert_dict(media["relations"]).is_empty()
	assert_array(media["memory"]).is_empty()


func test_decision_tables_are_data_with_normalized_defaults() -> void:
	var cfg := config()
	var vote := cfg.table("council.vote")
	assert_int(vote["factors"].size()).is_equal(7)
	assert_int(vote["theta"]).is_equal(0)
	assert_int(vote["hysteresis"]).is_equal(30)
	assert_int(vote["noise_amp"]).is_equal(80)
	assert_str(vote["kind"]).is_equal("council")
	var react := cfg.table("bloc.react")
	assert_int(react["tiers"].size()).is_equal(3)
	assert_str(react["tiers"][2]["id"]).is_equal("boycott")
	assert_bool(cfg.table("nonexistent.decision").is_empty()).is_true()


func test_retention_tables_are_integer_half_lives_with_resentment_outliving_trust() -> void:
	var cfg := config()
	var trust := cfg.retention_ppm("trust")
	var resent := cfg.retention_ppm("resentment")
	assert_int(resent).override_failure_message("kırgınlık güvenden yavaş silinir").is_greater(trust)
	assert_int(ActorMath.pow_ppm(trust, 360)).is_between(499_000, 501_000)
	assert_int(ActorMath.pow_ppm(resent, 900)).is_between(499_000, 501_000)
	assert_int(ActorMath.pow_ppm(cfg.retention_ppm("memory_short"), 90)).is_between(499_000, 501_000)
	assert_int(ActorMath.pow_ppm(resent, 0)).is_equal(1_000_000)


func test_integral_floats_from_json_become_ints_and_digest_is_stable() -> void:
	var a := ActorConfig.from_files(raw_files())
	var b := ActorConfig.from_files(raw_files())
	assert_bool(a.is_valid()).is_true()
	assert_str(a.digest).is_equal(b.digest)
	var vote := a.table("council.vote")
	assert_int(typeof(vote["theta"])).is_equal(TYPE_INT)
	assert_int(typeof(a.memory["K_mem"])).is_equal(TYPE_INT)
	var changed := mutated(func(f: Dictionary) -> void: f["memory_params"]["k_gain"] = 401)
	assert_str(changed.digest).override_failure_message("sayı değişince özet değişmeli").is_not_equal(a.digest)


## [etiket, düzenleme, hata metninde aranacak parça]. Her biri bozuk veri için ANLAŞILIR (yol + kimlik) hata verir.
func _broken_cases() -> Array:
	return [
		["şema sürümü yanlış", func(f: Dictionary) -> void: f["traits"]["schema"] = 2, "traits"],
		["kesirli sayı", func(f: Dictionary) -> void: roster_actor(f, COUNCIL_1)["traits"]["integrity"] = 600.5,
			"roster_m2"],
		["özellik aralık dışı", func(f: Dictionary) -> void: roster_actor(f, COUNCIL_2)["traits"]["self_interest"] = 1200,
			"self_interest"],
		["bilinmeyen özellik", func(f: Dictionary) -> void: roster_actor(f, COUNCIL_1)["traits"]["bogus_trait"] = 5,
			"bogus_trait"],
		["tür için izinsiz özellik", func(f: Dictionary) -> void: roster_actor(f, MEDIA_1)["traits"]["self_interest"] = 5,
			"self_interest"],
		["yinelenen anahtar", func(f: Dictionary) -> void: roster_actor(f, COUNCIL_3)["key"] = COUNCIL_2, COUNCIL_2],
		["anahtar türle uyuşmuyor", func(f: Dictionary) -> void: roster_actor(f, COUNCIL_3)["key"] = "actor.bloc.9",
			"actor.bloc.9"],
		["tekil türe indeks", func(f: Dictionary) -> void: roster_actor(f, PLAYER)["key"] = PLAYER + ".1",
			PLAYER + ".1"],
		["protagonistte ad alanı", func(f: Dictionary) -> void: roster_actor(f, PLAYER)["name"] = "x", "name"],
		["protagonistte eksen duruşu", func(f: Dictionary) -> void:
			roster_actor(f, PLAYER)["stance"] = {"growth_vs_preservation": 10}, "stance"],
		["çift protagonist", func(f: Dictionary) -> void:
			f["roster_m2"]["actors"].append({"key": "actor.protagonist", "kind": "protagonist", "profile_slots": []}),
			"actor.protagonist"],
		["bilinmeyen eksen", func(f: Dictionary) -> void: roster_actor(f, COUNCIL_1)["stance"]["no_axis"] = 1, "no_axis"],
		["bilinmeyen konu", func(f: Dictionary) -> void: roster_actor(f, COUNCIL_1)["salience"]["no_topic"] = 1,
			"no_topic"],
		["asılı ilişki: seçmen kesimi", func(f: Dictionary) -> void:
			roster_actor(f, COUNCIL_1)["constituency_blocs"] = ["actor.bloc.99"], "actor.bloc.99"],
		["bilinmeyen tür", func(f: Dictionary) -> void: roster_actor(f, COUNCIL_1)["kind"] = "wizard", "wizard"],
		["bilinmeyen alan", func(f: Dictionary) -> void: roster_actor(f, COUNCIL_1)["backstory"] = "x", "backstory"],
		["ilişki geçersiz aktör", func(f: Dictionary) -> void:
			f["relations_init"]["overrides"].append({"from": "actor.council.99", "to": PLAYER, "trust": 1}),
			"actor.council.99"],
		["ilişki kendine", func(f: Dictionary) -> void:
			f["relations_init"]["overrides"].append({"from": COUNCIL_1, "to": COUNCIL_1, "trust": 1}), "kendine"],
		["ilişki kampanya sınırı (CAN-09)", func(f: Dictionary) -> void:
			roster_actor(f, COUNCIL_2)["campaign_id"] = "other_campaign"
			f["relations_init"]["overrides"].append({"from": COUNCIL_2, "to": PLAYER, "trust": 1}), "campaign"],
		["ilişki değeri aralık dışı", func(f: Dictionary) -> void:
			f["relations_init"]["overrides"][0]["trust"] = 1001, "trust"],
		["tek faktörlü karar", func(f: Dictionary) -> void:
			f["decision_tables"]["decisions"]["council.vote"]["factors"] = [{"name": "stance_distance", "weight": 300}],
			"council.vote"],
		["tekrarlı faktör adı", func(f: Dictionary) -> void:
			f["decision_tables"]["decisions"]["media.coverage"]["factors"][1]["name"] = "newsworthiness",
			"newsworthiness"],
		["basamak eşikleri artan değil", func(f: Dictionary) -> void:
			f["decision_tables"]["decisions"]["bloc.react"]["tiers"][1]["theta"] = 100, "bloc.react"],
		["karar vermeyen tür", func(f: Dictionary) -> void:
			f["decision_tables"]["decisions"]["protagonist.vote"] = f["decision_tables"]["decisions"]["council.vote"],
			"protagonist.vote"],
		["tabloda bilinmeyen özellik kaydırması", func(f: Dictionary) -> void:
			f["decision_tables"]["decisions"]["council.vote"]["factors"][0]["trait_mod"] = {"nope": 5}, "nope"],
		["tabloda eşik yok", func(f: Dictionary) -> void:
			f["decision_tables"]["decisions"]["media.coverage"].erase("theta"), "media.coverage"],
		["yarı ömür sırası", func(f: Dictionary) -> void:
			f["memory_params"]["half_life_days"]["resentment"] = 100, "resentment"],
		["eksik hafıza parametresi", func(f: Dictionary) -> void: f["memory_params"].erase("K_mem"), "K_mem"],
		["kesirli hafıza parametresi", func(f: Dictionary) -> void: f["memory_params"]["k_gain"] = 0.4, "k_gain"],
		["dosya yok", func(f: Dictionary) -> void: f["roster_m2"] = null, "roster_m2"],
	]


func test_every_broken_data_variant_is_rejected_with_a_path_and_id_in_the_message() -> void:
	for case_data: Array in _broken_cases():
		var label: String = case_data[0]
		var cfg := mutated(case_data[1])
		assert_bool(cfg.is_valid()).override_failure_message("bozuk veri kabul edildi: %s" % label).is_false()
		var all_errors := "\n".join(cfg.errors)
		assert_bool(all_errors.contains(case_data[2])) \
			.override_failure_message("'%s' hatası anlaşılır değil (aranan '%s'): %s" % [label, case_data[2], all_errors]) \
			.is_true()
		assert_int(cfg.roster.size()).override_failure_message("geçersiz yapılandırma kadro sızdırıyor: %s" % label) \
			.is_equal(0)


func test_all_problems_are_collected_not_only_the_first() -> void:
	var cfg := mutated(func(f: Dictionary) -> void:
		roster_actor(f, COUNCIL_1)["traits"]["integrity"] = 5000
		roster_actor(f, COUNCIL_2)["salience"]["no_topic"] = 1
		f["memory_params"].erase("K_mem"))
	assert_bool(cfg.is_valid()).is_false()
	assert_int(cfg.errors.size()).is_greater_equal(3)
	assert_bool(cfg.error.contains("+")).override_failure_message("ilk hata + kalan sayısı").is_true()


func test_valid_variants_at_the_edges_are_accepted() -> void:
	var cfg := mutated(func(f: Dictionary) -> void:
		roster_actor(f, COUNCIL_1)["traits"]["integrity"] = 0
		roster_actor(f, COUNCIL_2)["traits"]["integrity"] = 1000
		roster_actor(f, COUNCIL_3)["stance"]["growth_vs_preservation"] = -1000
		roster_actor(f, COUNCIL_3).erase("name_key")
		f["relations_init"]["overrides"] = []
		var lone := roster_actor(f, COUNCIL_1)
		lone["constituency_blocs"] = []
		lone["affiliations"] = []
		f["roster_m2"]["actors"] = [roster_actor(f, PLAYER), lone])
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_int(cfg.roster.size()).is_equal(2)
