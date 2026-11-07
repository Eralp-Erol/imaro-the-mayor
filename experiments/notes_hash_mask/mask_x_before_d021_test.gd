extends "res://tests/sim/public_works/golden_x_council_trust_test.gd"
## Maske kanıtı: GOLDEN_X_BEFORE_D021 (kural kapalı referans; golden_x_council_trust_test.gd). Bkz. README.md.

const OLD_GOLDEN_X_BEFORE_D021 := "92d1a99e9ef9b491683d790a7e8b5ca2f39510ba7114f1c2fde7e324e22c1ef6"


func test_mask_golden_x_before_d021() -> void:
	var r: Dictionary = preload("res://experiments/notes_hash_mask/mask_a_b_test.gd").masked_hash(_scenario(false))
	print("MASK GOLDEN_X_BEFORE_D021 new=%s masked=%s" % [r["unmasked"], r["masked"]])
	assert_str(r["old_digest"]).is_not_equal(r["new_digest"])
	assert_str(r["masked"]).is_equal(OLD_GOLDEN_X_BEFORE_D021)
