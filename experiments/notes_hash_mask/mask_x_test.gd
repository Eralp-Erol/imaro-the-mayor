extends "res://tests/sim/public_works/golden_expropriation_undo_test.gd"
## Maske kanıtı: GOLDEN_X (golden_expropriation_undo_test.gd senaryosu). Bkz. README.md.

const OLD_GOLDEN_X := "cd738f30bb347a65e89004744f5628edf126fd5587a58d805bfc1a1b1c49dbf8"


func test_mask_golden_x() -> void:
	var r: Dictionary = preload("res://experiments/notes_hash_mask/mask_a_b_test.gd").masked_hash(_scenario())
	print("MASK GOLDEN_X new=%s masked=%s" % [r["unmasked"], r["masked"]])
	assert_str(r["old_digest"]).is_not_equal(r["new_digest"])
	assert_str(r["masked"]).is_equal(OLD_GOLDEN_X)
