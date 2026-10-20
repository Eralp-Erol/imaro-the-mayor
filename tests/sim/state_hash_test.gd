# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-900 · StateHash: kanonik SHA-256 durum hash'i (TEK-01, TEK-02).
## Altın değerler `src/sim/core/state_hash.gd` dışında, belgelenmiş bayt biçimini izleyen
## bağımsız bir Python referansıyla üretildi (bkz. T-900 raporu); uygulama kodundan kopyalanmadı.

const HEX_LEN := 64


func _is_hex64(s: String) -> bool:
	return s.length() == HEX_LEN and s.to_lower() == s and s.hex_decode().size() == HEX_LEN / 2


# --- Ölçüt 1: desteklenen türler ve olumsuz durum ---

func test_every_supported_type_yields_sha256_hex() -> void:
	var values: Array = [
		null, true, false, 0, -7, 1.5, "metin", &"kimlik", [], {},
		[1, [2, [3]]], {"a": {"b": [1, 2]}},
		PackedByteArray([1, 2]), PackedInt32Array([1, 2]), PackedInt64Array([1, 2]),
		PackedFloat32Array([1.5]), PackedFloat64Array([1.5]), PackedStringArray(["a"]),
		PackedVector2Array([Vector2(1, 2)]), PackedVector3Array([Vector3(1, 2, 3)]),
		PackedVector4Array([Vector4(1, 2, 3, 4)]), PackedColorArray([Color(0.5, 0.25, 1.0, 1.0)]),
	]
	for v: Variant in values:
		assert_bool(_is_hex64(StateHash.of(v))).override_failure_message("not sha256 hex for %s" % [v]).is_true()


func test_known_vectors_match_independent_reference() -> void:
	assert_str(StateHash.of(null)).is_equal("6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d")
	assert_str(StateHash.of(1)).is_equal("f83f60940c1ec44c0f1e90f694c6cae7c99b4b6d1507d60ad5a3282a7750d0ee")
	assert_str(StateHash.of(1.0)).is_equal("d64acd14161a70c4099bd0451fa44e0895d01bc9abec708d273f7ef9c40dede7")
	assert_str(StateHash.of("1")).is_equal("f788b8de25f8292f2a121749ea9e5f1786fa2144ec81425ae2232ec982f36982")
	assert_str(StateHash.of([])).is_equal("49e8e3297545c15ab6a79471a7a34d43e24a8f1cb25ea3d8417c61f699267a3f")
	assert_str(StateHash.of({})).is_equal("b45482224b439a3d548c65378929b7dcc16a42288530b7b20d5c8103cc879d10")
	var nested := {"tick": 42, "parcels": [1, 2.5, "a", null, true], "owner": {"id": 7, "name": "Ilgın"}}
	assert_str(StateHash.of(nested)).is_equal("30c262599de9e37d370526ec628e374e80ee9b5e4480de192f3001de6c0c66b5")


func test_same_value_hashes_identically_on_repeat() -> void:
	var v := {"a": [1, 2.5, "x"], "b": PackedInt32Array([3, 4])}
	assert_str(StateHash.of(v)).is_equal(StateHash.of(v))
	assert_str(StateHash.of(v)).is_equal(StateHash.of(v.duplicate(true)))


func test_unsupported_object_is_rejected_with_explicit_error() -> void:
	await assert_error(func() -> void: StateHash.of(RefCounted.new())) \
		.is_push_error("StateHash: unsupported type Object at root")
	assert_str(StateHash.of(RefCounted.new())).is_empty()


func test_unsupported_node_is_rejected() -> void:
	var node := Node.new()
	assert_str(StateHash.of(node)).is_empty()
	node.free()


func test_unsupported_nested_value_reports_path() -> void:
	var data := {"parcels": [1, Vector2(1, 2)]}
	await assert_error(func() -> void: StateHash.of(data)) \
		.is_push_error('StateHash: unsupported type Vector2 at root["parcels"][1]')
	assert_str(StateHash.of(data)).is_empty()


func test_unsupported_callable_and_rid_are_rejected() -> void:
	assert_str(StateHash.of(Callable())).is_empty()
	assert_str(StateHash.of(RID())).is_empty()
	assert_str(StateHash.of([1, Callable()])).is_empty()


func test_cyclic_array_is_rejected_not_infinite_recursion() -> void:
	var a: Array = []
	a.append(a)
	assert_str(StateHash.of(a)).is_empty()


# --- Ölçüt 2: sözlük sırası ---

func test_dictionary_insertion_order_does_not_matter() -> void:
	var a := {}
	a["x"] = 1
	a["y"] = 2
	a[3] = [true]
	var b := {}
	b[3] = [true]
	b["y"] = 2
	b["x"] = 1
	assert_array(a.keys()).is_not_equal(b.keys())
	assert_str(StateHash.of(a)).is_equal(StateHash.of(b))


func test_nested_dictionary_insertion_order_does_not_matter() -> void:
	var a := {"o": {"p": 1, "q": 2}, "r": 3}
	var b := {"r": 3, "o": {"q": 2, "p": 1}}
	assert_str(StateHash.of(a)).is_equal(StateHash.of(b))


func test_array_order_matters() -> void:
	assert_str(StateHash.of([1, 2])).is_not_equal(StateHash.of([2, 1]))


func test_stringname_and_string_are_the_same_value() -> void:
	assert_str(StateHash.of(&"abc")).is_equal(StateHash.of("abc"))
	assert_str(StateHash.of({&"k": 1})).is_equal(StateHash.of({"k": 1}))


# --- Ölçüt 3: tek değer değişimi ---

func test_single_changed_value_changes_hash() -> void:
	var base := {"tick": 10, "parcels": [{"id": 1, "zone": 2}, {"id": 2, "zone": 3}]}
	var changed := base.duplicate(true)
	changed["parcels"][1]["zone"] = 4
	assert_str(StateHash.of(base)).is_not_equal(StateHash.of(changed))
	var changed_top := base.duplicate(true)
	changed_top["tick"] = 11
	assert_str(StateHash.of(base)).is_not_equal(StateHash.of(changed_top))


func test_element_in_nested_array_changes_hash() -> void:
	assert_str(StateHash.of([[1, [2, 3]]])).is_not_equal(StateHash.of([[1, [2, 4]]]))


func test_added_removed_and_renamed_keys_change_hash() -> void:
	assert_str(StateHash.of({"a": 1})).is_not_equal(StateHash.of({"a": 1, "b": null}))
	assert_str(StateHash.of({"a": 1})).is_not_equal(StateHash.of({"b": 1}))


func test_container_boundaries_are_unambiguous() -> void:
	assert_str(StateHash.of([[1], 2])).is_not_equal(StateHash.of([1, [2]]))
	assert_str(StateHash.of(["ab", "c"])).is_not_equal(StateHash.of(["a", "bc"]))
	assert_str(StateHash.of([])).is_not_equal(StateHash.of({}))
	assert_str(StateHash.of([[]])).is_not_equal(StateHash.of([]))


# --- Ölçüt 4: tür bilgisi ---

func test_int_float_and_string_one_are_distinct() -> void:
	var hashes := {}
	for v: Variant in [1, 1.0, "1"]:
		hashes[StateHash.of(v)] = true
	assert_int(hashes.size()).is_equal(3)


func test_other_scalar_types_are_distinct() -> void:
	var hashes := {}
	for v: Variant in [null, false, true, 0, 0.0, "", "0", "null", "false"]:
		hashes[StateHash.of(v)] = true
	assert_int(hashes.size()).is_equal(9)


func test_int_vs_float_inside_containers_are_distinct() -> void:
	assert_str(StateHash.of([1])).is_not_equal(StateHash.of([1.0]))
	assert_str(StateHash.of({"a": 1})).is_not_equal(StateHash.of({"a": 1.0}))
	assert_str(StateHash.of({1: "a"})).is_not_equal(StateHash.of({"1": "a"}))


func test_packed_integer_arrays_hash_like_equivalent_array() -> void:
	var expected := StateHash.of([1, 2, 3])
	assert_str(StateHash.of(PackedByteArray([1, 2, 3]))).is_equal(expected)
	assert_str(StateHash.of(PackedInt32Array([1, 2, 3]))).is_equal(expected)
	assert_str(StateHash.of(PackedInt64Array([1, 2, 3]))).is_equal(expected)
	assert_str(StateHash.of(PackedInt32Array([1, 2, 4]))).is_not_equal(expected)


func test_packed_float_and_string_arrays_hash_like_equivalent_array() -> void:
	var expected := StateHash.of([0.5, 2.0])
	assert_str(StateHash.of(PackedFloat32Array([0.5, 2.0]))).is_equal(expected)
	assert_str(StateHash.of(PackedFloat64Array([0.5, 2.0]))).is_equal(expected)
	assert_str(StateHash.of(PackedStringArray(["a", "b"]))).is_equal(StateHash.of(["a", "b"]))
	assert_str(StateHash.of(PackedFloat64Array([1.0]))).is_not_equal(StateHash.of(PackedInt64Array([1])))


func test_packed_array_inside_dictionary_is_covered() -> void:
	var a := {"col": PackedInt32Array([1, 2, 3])}
	var b := {"col": PackedInt32Array([1, 2, 4])}
	assert_str(StateHash.of(a)).is_not_equal(StateHash.of(b))
	assert_str(StateHash.of(a)).is_equal(StateHash.of({"col": [1, 2, 3]}))


func test_packed_vector_and_color_arrays_are_distinct_and_value_sensitive() -> void:
	var base := StateHash.of(PackedVector2Array([Vector2(1, 2)]))
	assert_str(base).is_not_equal(StateHash.of([1.0, 2.0]))
	assert_str(base).is_not_equal(StateHash.of(PackedVector2Array([Vector2(1, 3)])))
	assert_str(base).is_not_equal(StateHash.of(PackedVector3Array([Vector3(1, 2, 0)])))


func test_packed_vector_and_color_components_keep_fractional_precision() -> void:
	assert_str(StateHash.of(PackedVector2Array([Vector2(1.25, 2)]))) \
		.is_not_equal(StateHash.of(PackedVector2Array([Vector2(1.0, 2)])))
	assert_str(StateHash.of(PackedColorArray([Color(0.25, 0.5, 0.75, 1.0)]))) \
		.is_not_equal(StateHash.of(PackedColorArray([Color(0.25, 0.5, 0.5, 1.0)])))


func test_large_packed_array_hashes_deterministically_and_detects_last_element_change() -> void:
	var big := PackedInt32Array()
	big.resize(100000)
	for i in big.size():
		big[i] = i * 7
	var first := StateHash.of(big)
	assert_bool(_is_hex64(first)).is_true()
	assert_str(StateHash.of(big.duplicate())).is_equal(first)
	big[99999] += 1
	assert_str(StateHash.of(big)).is_not_equal(first)


# --- Ölçüt 5: float temsili ve NaN ---

func test_float_uses_exact_binary64_not_text() -> void:
	# 0.1 + 0.2 ile 0.3 metin olarak yuvarlanınca aynı görünebilir; ikili gösterimde farklıdır.
	var sum := 0.1 + 0.2
	assert_bool(sum == 0.3).is_false()
	assert_str(StateHash.of(sum)).is_not_equal(StateHash.of(0.3))
	# En küçük ulp farkı bile hash'i değiştirir.
	assert_str(StateHash.of(1.0)).is_not_equal(StateHash.of(1.0 + 2.220446049250313e-16))


func test_float32_values_widen_exactly_and_match_float64_of_same_value() -> void:
	var f32 := PackedFloat32Array([0.1])
	var widened: float = f32[0]
	assert_str(StateHash.of(f32)).is_equal(StateHash.of([widened]))
	assert_str(StateHash.of(f32)).is_not_equal(StateHash.of([0.1]))


## IEEE-754 binary64'ü üst 16 + alt 48 bitten kurar (GDScript int sabitleri 2^63'ü aşamaz).
func _double_from_bits(high16: int, low48: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, (high16 << 48) | low48)
	return bytes.decode_double(0)


func test_nan_with_different_bit_payloads_hashes_identically() -> void:
	var quiet := _double_from_bits(0x7FF8, 0)
	var negative_payload := _double_from_bits(0xFFF8, 1)
	var signaling := _double_from_bits(0x7FF0, 1)
	assert_bool(is_nan(quiet) and is_nan(negative_payload) and is_nan(signaling)).is_true()
	assert_str(StateHash.of(negative_payload)).is_equal(StateHash.of(quiet))
	assert_str(StateHash.of(signaling)).is_equal(StateHash.of(quiet))
	assert_str(StateHash.of(quiet)).is_equal(StateHash.of(NAN))


func test_nan_has_one_canonical_encoding() -> void:
	var nan_a := NAN
	var nan_b := -NAN
	var nan_c := sqrt(-1.0)
	assert_bool(is_nan(nan_a) and is_nan(nan_b) and is_nan(nan_c)).is_true()
	assert_str(StateHash.of(nan_a)).is_equal("e121b4595d1f0ff5978fd70183066f491d9e133f09112297cd88e235b5eafcfb")
	assert_str(StateHash.of(nan_b)).is_equal(StateHash.of(nan_a))
	assert_str(StateHash.of(nan_c)).is_equal(StateHash.of(nan_a))
	assert_str(StateHash.of([NAN, 1])).is_equal(StateHash.of([nan_c, 1]))
	assert_str(StateHash.of(PackedFloat64Array([NAN]))).is_equal(StateHash.of([NAN]))


func test_nan_is_distinct_from_other_floats_and_values() -> void:
	assert_str(StateHash.of(NAN)).is_not_equal(StateHash.of(0.0))
	assert_str(StateHash.of(NAN)).is_not_equal(StateHash.of(INF))
	assert_str(StateHash.of(NAN)).is_not_equal(StateHash.of(null))
	assert_str(StateHash.of(NAN)).is_not_equal(StateHash.of("nan"))


func test_infinities_are_distinct_and_stable() -> void:
	assert_str(StateHash.of(INF)).is_not_equal(StateHash.of(-INF))
	assert_str(StateHash.of(INF)).is_equal(StateHash.of(INF))


func test_negative_zero_is_normalized_to_positive_zero() -> void:
	var negative_zero := _double_from_bits(0x8000, 0)
	# Önkoşul: değer gerçekten işaret bitli sıfır (en anlamlı bayt 0x80), yoksa test hiçbir şey kanıtlamaz.
	var raw := PackedByteArray()
	raw.resize(8)
	raw.encode_double(0, negative_zero)
	assert_int(raw[7]).is_equal(0x80)
	assert_bool(negative_zero == 0.0).is_true()
	assert_str(StateHash.of(negative_zero)).is_equal(StateHash.of(0.0))
	assert_str(StateHash.of([negative_zero])).is_equal(StateHash.of([0.0]))
	assert_str(StateHash.of(PackedFloat32Array([negative_zero]))).is_equal(StateHash.of(PackedFloat32Array([0.0])))


# --- Ölçüt 6: saflık ---

func test_source_has_no_forbidden_apis() -> void:
	var text := FileAccess.get_file_as_string("res://src/sim/core/state_hash.gd")
	assert_str(text).is_not_empty()
	var pattern := "\\b(randf|randi|randomize|Time\\.|OS\\.|get_tree|extends Node|Engine\\.get_frames)"
	var forbidden := RegEx.create_from_string(pattern)
	assert_object(forbidden.search(text)).is_null()
