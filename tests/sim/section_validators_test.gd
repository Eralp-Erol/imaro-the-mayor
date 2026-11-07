extends SimTestBase
## T-078 · Bölüm doğrulayıcı kaydı (`SectionValidators`): `GameState.validate_dict` bölümleri elle değil kayıttan
## doğrular. Davranış eskisiyle aynı (aynı sıra, aynı iletiler); yeni bölüm tek satır ekler. Olumsuz: bilinçli bozulmuş
## bölüm kaydı REDDEDİLİR (TEK-03, kayıt güvenliği).

const EXPECTED_KEYS: Array[String] = ["events", "actors", "politics", "public_works", "policy"]


func _valid_dict() -> Dictionary:
	var state := new_state()
	new_sim_full().advance(state, 3)
	return state.to_dict()


func test_registry_lists_known_sections_in_validation_order() -> void:
	assert_array(Array(SectionValidators.keys())).is_equal(EXPECTED_KEYS)


func test_absent_sections_are_valid() -> void:
	assert_str(SectionValidators.validate_systems({})).is_empty()


func test_every_registered_validator_rejects_a_non_dictionary_section() -> void:
	for key in SectionValidators.keys():
		var message := SectionValidators.validate_systems({key: 42})
		assert_str(message).override_failure_message("'%s' bölümü bozuk ama kabul edildi" % key).is_not_empty()
		assert_str(message).contains("systems.%s" % key)


func test_corrupt_section_is_rejected_by_game_state_validation() -> void:
	for key in SectionValidators.keys():
		var data := _valid_dict()
		(data["systems"] as Dictionary)[key] = "bozuk bölüm"
		var message := GameState.validate_dict(data)
		assert_str(message).override_failure_message("'%s' bozuk bölümü yüklenebildi" % key).is_not_empty()
		assert_object(GameState.from_dict(data)).is_null()


func test_corrupt_section_is_rejected_by_save_decode() -> void:
	# Kayıt hash'i bozuk durumdan da hesaplanır; yükleme reddi doğrulayıcı kaydından gelmeli ("corrupt", hash değil).
	var state := new_state()
	state.systems["policy"] = {"version": 999}
	var result := SimSave.decode(SimSave.encode(state))
	assert_bool(result.ok).is_false()
	assert_str(str(result.error_code)).is_equal("corrupt")
	assert_object(result.state).is_null()


func test_valid_state_passes_and_unknown_sections_are_ignored() -> void:
	var data := _valid_dict()
	assert_str(GameState.validate_dict(data)).is_empty()
	(data["systems"] as Dictionary)["economy"] = "ekonomi doğrulayıcısı kayıtta değil (facade yüklemesinde denetlenir)"
	assert_str(GameState.validate_dict(data)).is_empty()


func test_first_error_follows_registry_order() -> void:
	var systems := {"policy": 1, "events": 1}
	assert_str(SectionValidators.validate_systems(systems)).contains("systems.events")
