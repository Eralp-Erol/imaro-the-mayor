extends PoliticsTestBase
## T-017 ölçüt 1/2/4/8 · Siyaset yapılandırması VERİDİR ve doğrulanır: varsayılan veri geçerli; sayılar/kural tabloları
## dosyada (kodda değil); bozuk veri anlaşılır, yollu hata verir; kanon-dışı alanlar (ad/parti/rakip) ve KAPALI ton
## etiketleri veride bulunmaz.


func test_default_politics_data_is_valid_and_matches_the_actor_roster() -> void:
	var cfg := politics_config()
	assert_int(cfg.digest.length()).is_equal(64)
	assert_array(cfg.council["members"]).is_equal(["actor.council.1", "actor.council.2", "actor.council.3",
		"actor.council.4", "actor.council.5"])
	assert_array(cfg.blocs["cohorts"].map(func(c: Dictionary) -> String: return c["bloc"])) \
		.is_equal(["actor.bloc.1", "actor.bloc.2"])
	var ids := cfg.templates.map(func(t: Dictionary) -> String: return t["id"])
	assert_array(ids).is_equal(["PE-01", "PE-02", "PE-03", "PE-04", "PE-07"])
	assert_bool(cfg.requires_council("zoning.propose")).is_true()
	assert_bool(cfg.milestone_open("M2")).is_true()
	assert_bool(cfg.milestone_open("M3")).is_false()


func test_council_size_and_procedure_are_data_not_code() -> void:
	var seven := ActorConfig.from_files(_with_extra_members(2))
	assert_bool(seven.is_valid()).override_failure_message(seven.error).is_true()
	var cfg := PoliticsConfig.from_files(raw_politics(), seven)
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_int((cfg.council["members"] as Array).size()).is_equal(7)
	var tweaked := pol_valid(func(f: Dictionary) -> void:
		f["council"]["session_days"] = 30
		f["council"]["tie_result"] = "pass")
	assert_int(tweaked.council["session_days"]).is_equal(30)
	assert_str(tweaked.council["tie_result"]).is_equal("pass")


func _with_extra_members(extra: int) -> Dictionary:
	var files := raw_files()
	var roster: Array = files["roster_m2"]["actors"]
	for i in extra:
		var clone: Dictionary = roster_actor(files, COUNCIL_5).duplicate(true)
		clone["key"] = "actor.council.%d" % (6 + i)
		roster.append(clone)
	return files


func test_broken_data_reports_path_qualified_errors() -> void:
	var cases: Array = [
		[func(f: Dictionary) -> void: f["cadence"]["scan_days"] = 0, "cadence.scan_days"],
		[func(f: Dictionary) -> void: f["cadence"].erase("recheck_days"), "cadence.recheck_days"],
		[func(f: Dictionary) -> void: f["cadence"]["surprise"] = 1, "bilinmeyen alan 'surprise'"],
		[func(f: Dictionary) -> void: f["blocs"]["cohorts"]["housed"]["bloc"] = "actor.bloc.9", "actor.bloc.9"],
		[func(f: Dictionary) -> void: f["blocs"]["cohorts"]["housed"]["size_source"] = "tenure", "size_source"],
		[func(f: Dictionary) -> void: f["blocs"]["cohorts"]["seeking"]["bloc"] = "actor.bloc.1", "yinelenen kesim yuvası"],
		[func(f: Dictionary) -> void: f["blocs"]["cohorts"]["housed"]["grievance_rules"][0]["signal"] = "mood",
			"bilinmeyen sinyal 'mood'"],
		[func(f: Dictionary) -> void: f["blocs"]["cohorts"]["housed"]["grievance_rules"][0]["topic"] = "nope",
			"bilinmeyen konu"],
		[func(f: Dictionary) -> void: f["blocs"]["cohorts"]["housed"]["grievance_rules"][0]["hi"] = 20,
			"hi (20) lo'dan"],
		[func(f: Dictionary) -> void: f["blocs"]["tier_reactions"].erase("protest"), "tier_reactions.protest"],
		[func(f: Dictionary) -> void: f["blocs"]["tier_reactions"]["boycott"] = "riot", "oppose/protest"],
		[func(f: Dictionary) -> void: f["blocs"]["react_decision"] = "council.vote", "blocs.react_decision"],
		[func(f: Dictionary) -> void: f["council"]["requires_council"].erase("budget.propose"), "budget.propose"],
		[func(f: Dictionary) -> void: f["council"]["requires_council"]["build.house"] = true, "build.house"],
		[func(f: Dictionary) -> void: f["council"]["tie_result"] = "coin", "tie_result"],
		[func(f: Dictionary) -> void: f["council"]["proposal_effects"]["zoning"]["zone.mixed"]["ghost"] = {},
			"bilinmeyen kohort 'ghost'"],
		[func(f: Dictionary) -> void: f["media"]["organ"] = "actor.bloc.1", "media.organ"],
		[func(f: Dictionary) -> void: f["media"]["story_axes"].erase("protest"), "story_axes.protest"],
		[func(f: Dictionary) -> void: f["authority"]["granted"].append("secret_power"), "bilinmeyen yetki 'secret_power'"],
		[func(f: Dictionary) -> void: f["events"]["milestones"] = ["M3"], "events.milestones"],
		[func(f: Dictionary) -> void: f["events"]["system_actor"] = "sys.events", "actor.<tür>.<n>"],
	]
	for entry: Array in cases:
		var cfg := pol_mutated(entry[0])
		assert_bool(cfg.is_valid()).override_failure_message("bozuk veri kabul edildi: %s" % entry[1]).is_false()
		assert_str(cfg.error + " | ".join(cfg.errors)).contains(entry[1])
		assert_array(cfg.templates).override_failure_message("kısmi şablon sızdı").is_empty()


func test_broken_event_templates_are_rejected_with_the_template_path() -> void:
	var cases: Array = [
		[func(t: Dictionary) -> void: t["options"].remove_at(3), "'defer' fiilli"],
		[func(t: Dictionary) -> void: t["options"][0]["effects"][0]["target"] = "budget.line", "desteklenmeyen hedef"],
		[func(t: Dictionary) -> void: t["options"][0]["effects"][0]["target"] = "world.cue", "desteklenmeyen hedef"],
		[func(t: Dictionary) -> void: t["options"][0]["effects"][1]["curve"] = "linear", "yalnız 'step'"],
		[func(t: Dictionary) -> void: t["options"][1]["requires"]["authority"] = "emperor", "bilinmeyen yetki 'emperor'"],
		[func(t: Dictionary) -> void: t["drivers"][0]["src"] = "mood.of.city", "bilinmeyen kaynak"],
		[func(t: Dictionary) -> void: t["drivers"][0]["hi"] = 400, "hi (400) lo'dan"],
		[func(t: Dictionary) -> void: t["hard"][0]["op"] = "~", "op"],
		[func(t: Dictionary) -> void: t["hard"][0]["value"] = "riot", "basamak adı"],
		[func(t: Dictionary) -> void: t["delivery"] = "modal", "delivery"],
		[func(t: Dictionary) -> void: t["cause"] = "magic", "cause"],
		[func(t: Dictionary) -> void: t["stages"][0]["after_days"] = 0, "after_days"],
		[func(t: Dictionary) -> void: t["options"][0]["effects"][0]["duration_days"] = 0, "duration_days"],
		[func(t: Dictionary) -> void: t["unknown_field"] = 1, "bilinmeyen alan 'unknown_field'"],
	]
	for entry: Array in cases:
		var cfg := pol_mutated(func(f: Dictionary) -> void: entry[0].call(f["templates"]["pe-01"]))
		assert_bool(cfg.is_valid()).override_failure_message("bozuk şablon kabul edildi: %s" % entry[1]).is_false()
		assert_str(" | ".join(cfg.errors)).contains(entry[1])
		assert_str(" | ".join(cfg.errors)).contains("pe-01")


func test_missing_or_non_object_files_and_invalid_actor_config_fail_cleanly() -> void:
	var cfg := pol_mutated(func(f: Dictionary) -> void: f.erase("council"))
	assert_bool(cfg.is_valid()).is_false()
	assert_str(cfg.error).contains("council")
	var no_actors := PoliticsConfig.from_files(raw_politics(), null)
	assert_bool(no_actors.is_valid()).is_false()
	assert_str(no_actors.error).contains("aktör yapılandırması")
	var float_value := pol_mutated(func(f: Dictionary) -> void: f["cadence"]["scan_days"] = 7.5)
	assert_bool(float_value.is_valid()).override_failure_message("kesirli sayı kabul edildi").is_false()
	assert_str(float_value.error).contains("kesirli")


func test_data_contains_no_names_parties_rivals_or_closed_tone_templates() -> void:
	var text := raw_politics_text().to_lower()
	var banned: Array[String] = ["ilgın", "ilgin", "partisi", "party.", "rakip", "rival", "protagonist", "başkan adayı",
		"secim", "seçim"]
	for forbidden in banned:
		assert_bool(text.contains(forbidden)).override_failure_message("veride yasak/kanon-dışı terim: %s" % forbidden) \
			.is_false()
	var cfg := politics_config()
	for template in cfg.templates:
		assert_array(template["tone_tags"]).override_failure_message("%s etiketli" % template["id"]).is_empty()
	assert_array(cfg.events["blocked_tags"]).contains(["corruption"])


func test_default_authority_table_is_placeholder_with_known_keys() -> void:
	var cfg := politics_config()
	for key in cfg.granted_authority:
		assert_array(cfg.known_authority).contains([key])
	assert_bool(cfg.is_granted("rent_protection")).is_false()
