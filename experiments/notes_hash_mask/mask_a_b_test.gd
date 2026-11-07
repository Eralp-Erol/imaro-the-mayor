extends ActorTestBase
## Maske kanıtı: GOLDEN_A / GOLDEN_B (tests/sim/m2_query_test.gd). Bkz. README.md.

const M := preload("res://tests/sim/m2_support.gd")
const OLD_GOLDEN_A := "ffbaf113645896e9d60c5c8eeba0ef6b8df5f54df8326b31b7bcbfd7678ae2e6"
const OLD_GOLDEN_B := "42abd619af18f2a9fb64298aa89bbe0d62a14db9d5af3f9c91cb715ffb27df9a"


## ESKİ yöntem: ham dosyalar (`_notes` dahil) -> to_ints -> StateHash.
static func old_digest() -> String:
	var data := {}
	var raw := raw_files()
	for file_name in FILE_NAMES:
		data[file_name] = ActorSchema.to_ints(raw[file_name])
	return StateHash.of(data)


static func masked_hash(f: SimFacadeImpl) -> Dictionary:
	var actors: Dictionary = f.game_state().systems[ActorStore.SYSTEM_KEY]
	var new_digest: String = actors["config_digest"]
	var unmasked := f.state_hash()
	actors["config_digest"] = old_digest()
	var masked := f.state_hash()
	actors["config_digest"] = new_digest
	return {"new_digest": new_digest, "old_digest": old_digest(), "unmasked": unmasked, "masked": masked}


func test_mask_golden_a() -> void:
	var r := masked_hash(M.stress_run())
	print("MASK GOLDEN_A new=%s masked=%s" % [r["unmasked"], r["masked"]])
	assert_str(r["old_digest"]).is_not_equal(r["new_digest"])
	assert_str(r["masked"]).is_equal(OLD_GOLDEN_A)


func test_mask_golden_b() -> void:
	var r := masked_hash(M.two_conditions_run()["facade"])
	print("MASK GOLDEN_B new=%s masked=%s" % [r["unmasked"], r["masked"]])
	assert_str(r["old_digest"]).is_not_equal(r["new_digest"])
	assert_str(r["masked"]).is_equal(OLD_GOLDEN_B)
