extends GdUnitTestSuite
## Test koşucusunun (GdUnit4 + tools/verify.sh) çalıştığını kanıtlar; oyun koduna bağımlı değildir.


func test_arithmetic_and_strings() -> void:
	assert_int(2 + 2).is_equal(4)
	assert_str("Imaro").is_equal("Imaro")
	assert_bool("Ilgın".length() == 5).is_true()


func test_engine_version_is_4_7() -> void:
	var info := Engine.get_version_info()
	assert_int(info.major).is_equal(4)
	assert_int(info.minor).is_equal(7)


func test_deterministic_rng_with_same_seed() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 1467
	b.seed = 1467
	for i in range(10):
		assert_int(a.randi_range(0, 1000)).is_equal(b.randi_range(0, 1000))
