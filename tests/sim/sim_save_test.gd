# gdlint:disable=max-public-methods
extends SimTestBase
## T-002 ölçüt 6 ve 7 · Kayıt/yükleme: kaydet -> yükle -> N tick = kesintisiz koşu hash'i; sürüm alanı; bozuk/eski sürüm
## anlaşılır hatayla reddedilir; biçim int/float ayrımını korur (var_to_bytes/var_to_str, JSON değil; T-900 QA bulgusu).

const K_TICKS := 40
const M_TICKS := 55


func _busy_state(sim: Simulation) -> GameState:
	var state := new_state()
	sim.advance(state, 12)
	Commands.submit(state, &"set_value", {"key": "tax", "value": 5})
	Commands.submit(state, &"set_value", {"key": "tax", "value": -1})
	Commands.submit(state, &"withdraw", {"amount": 3})
	sim.advance(state, K_TICKS - 12)
	Commands.submit(state, &"set_value", {"key": "late", "value": 1})  # kayıt anında kuyrukta bekleyen komut
	return state


func _load_ok(bytes: PackedByteArray) -> GameState:
	var result := SimSave.decode(bytes)
	assert_bool(result.ok).override_failure_message("yükleme başarısız: %s" % result.message).is_true()
	return result.state


func _envelope(overrides: Dictionary, drop: Array = []) -> PackedByteArray:
	var base: Dictionary = bytes_to_var(SimSave.encode(new_state()))
	base.merge(overrides, true)
	for key: String in drop:
		base.erase(key)
	return var_to_bytes(base)


func _assert_rejected(bytes: PackedByteArray, code: StringName) -> void:
	var result := SimSave.decode(bytes)
	assert_bool(result.ok).is_false()
	assert_str(str(result.error_code)).is_equal(str(code))
	assert_str(result.message).is_not_empty()
	assert_object(result.state).is_null()


# --- Ölçüt 6: kaydet -> yükle -> koş = kesintisiz koşu ---

func test_save_load_then_run_equals_uninterrupted_run() -> void:
	var sim_straight := new_sim_full()
	var straight := _busy_state(sim_straight)
	sim_straight.advance(straight, M_TICKS)

	var sim_first := new_sim_full()
	var first := _busy_state(sim_first)
	var bytes := SimSave.encode(first)
	assert_int(bytes.size()).is_greater(0)
	var restored := _load_ok(bytes)
	var sim_second := new_sim_full()
	sim_second.advance(restored, M_TICKS)

	assert_str(state_hash_of(restored)).is_equal(state_hash_of(straight))
	assert_int(restored.tick).is_equal(K_TICKS + M_TICKS)


func test_state_hash_equals_hash_of_serialized_dict() -> void:
	# Kayıt bütünlüğü hash'i to_dict() üzerinden, test/sürücü hash'i state_hash() üzerinden hesaplanır: aynı olmalı.
	var state := _busy_state(new_sim_full())
	assert_str(assert_hash(StateHash.of(state.to_dict()))).is_equal(state_hash_of(state))


func test_loaded_state_hash_equals_saved_state_hash_immediately() -> void:
	var state := _busy_state(new_sim_full())
	assert_str(state_hash_of(_load_ok(SimSave.encode(state)))).is_equal(state_hash_of(state))


func test_resumed_run_diverges_if_state_differs() -> void:
	# Olumsuz: yüklenen durumdan farklı bir komutla devam edilirse hash eşit OLMAMALI (test körü körüne eşit demiyor).
	var sim := new_sim_full()
	var straight := _busy_state(sim)
	sim.advance(straight, M_TICKS)
	var restored := _load_ok(SimSave.encode(_busy_state(new_sim_full())))
	Commands.submit(restored, &"set_value", {"key": "extra", "value": 1})
	new_sim_full().advance(restored, M_TICKS)
	assert_str(state_hash_of(restored)).is_not_equal(state_hash_of(straight))


func test_rng_streams_resume_exact_sequence_after_load() -> void:
	var state := new_state()
	var sim := new_sim_full()
	sim.advance(state, 30)
	var restored := _load_ok(SimSave.encode(state))
	for stream: StringName in [&"stream_a", &"stream_b", &"decider"]:
		assert_int(restored.rng.stream(stream).randi()).is_equal(state.rng.stream(stream).randi())


func test_pending_commands_survive_save_and_apply_after_load() -> void:
	var state := _busy_state(new_sim_full())
	var restored := _load_ok(SimSave.encode(state))
	assert_int(Commands.pending_count(restored)).is_equal(1)
	new_sim_full().step(restored)
	assert_int(restored.system_data(&"cmd")["late"]).is_equal(1)


func test_save_has_version_and_format_fields() -> void:
	var envelope: Dictionary = bytes_to_var(SimSave.encode(new_state()))
	assert_str(str(envelope["format"])).is_equal(SimSave.FORMAT)
	assert_int(typeof(envelope["version"])).is_equal(TYPE_INT)
	assert_int(envelope["version"]).is_equal(SimSave.VERSION)
	assert_bool(envelope["state"] is Dictionary).is_true()


func test_text_save_roundtrips_to_same_hash_and_is_var_to_str() -> void:
	var state := _busy_state(new_sim_full())
	var text := SimSave.encode_text(state)
	assert_str(text).contains("version")
	var result := SimSave.decode_text(text)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_str(state_hash_of(result.state)).is_equal(state_hash_of(state))


# --- Ölçüt 7: int/float ayrımı, JSON değil ---

func test_int_float_and_packed_types_survive_roundtrip() -> void:
	var state := new_state()
	var data := state.system_data(&"types")
	data["i"] = 1
	data["f"] = 1.0
	data["packed_i"] = PackedInt32Array([1, 2, 3])
	data["packed_f"] = PackedFloat64Array([0.1, 0.25])
	data["nested"] = {"k": [1, 2.0, "3"], 7: true}
	var restored := _load_ok(SimSave.encode(state))
	var back := restored.system_data(&"types")
	assert_int(typeof(back["i"])).is_equal(TYPE_INT)
	assert_int(typeof(back["f"])).is_equal(TYPE_FLOAT)
	assert_int(typeof(back["packed_i"])).is_equal(TYPE_PACKED_INT32_ARRAY)
	assert_int(typeof(back["nested"]["k"][1])).is_equal(TYPE_FLOAT)
	assert_str(state_hash_of(restored)).is_equal(state_hash_of(state))


func test_json_would_have_lost_int_float_distinction_which_is_why_it_is_not_used() -> void:
	# Belgeleyici olumsuz kontrol: aynı veri JSON'dan geçerse hash DEĞİŞİR (int -> float); kayıt biçimimiz bunu yapmaz.
	var state := new_state()
	state.system_data(&"types")["i"] = 1
	var via_json: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	assert_str(StateHash.of(via_json)).is_not_equal(StateHash.of(state.to_dict()))
	assert_str(state_hash_of(_load_ok(SimSave.encode(state)))).is_equal(state_hash_of(state))


func test_state_with_unhashable_content_is_refused_instead_of_written() -> void:
	var state := new_state()
	state.system_data(&"bad")["obj"] = RefCounted.new()
	var holder: Array = [PackedByteArray([1])]
	await assert_error(func() -> void: holder[0] = SimSave.encode(state)) \
		.is_push_error("StateHash: unsupported type Object at root[\"systems\"][\"bad\"][\"obj\"]")
	assert_int((holder[0] as PackedByteArray).size()).is_equal(0)
	assert_str(state.state_hash()).is_empty()


# --- Ölçüt 6: bozuk / eski / yeni sürüm ---

func test_empty_input_is_rejected() -> void:
	_assert_rejected(PackedByteArray(), &"empty")


func test_garbage_bytes_are_rejected_as_corrupt() -> void:
	var junk := PackedByteArray()
	for i in 64:
		junk.append((i * 37 + 11) % 256)
	_assert_rejected(junk, &"corrupt")


func test_truncated_save_is_rejected() -> void:
	var good := SimSave.encode(_busy_state(new_sim_full()))
	var cut := good.slice(0, good.size() / 2)
	var result := SimSave.decode(cut)
	assert_bool(result.ok).is_false()
	assert_str(result.message).is_not_empty()


func test_wrong_format_marker_is_rejected() -> void:
	_assert_rejected(_envelope({"format": "something-else"}), &"bad_format")
	_assert_rejected(var_to_bytes([1, 2, 3]), &"corrupt")


func test_older_unsupported_version_is_rejected_with_clear_message() -> void:
	_assert_rejected(_envelope({"version": SimSave.MIN_SUPPORTED_VERSION - 1}), &"version_too_old")
	var result := SimSave.decode(_envelope({"version": 0}))
	assert_str(result.message).contains("0")


func test_newer_version_is_rejected_with_clear_message() -> void:
	_assert_rejected(_envelope({"version": SimSave.VERSION + 1}), &"version_too_new")
	var result := SimSave.decode(_envelope({"version": SimSave.VERSION + 1}))
	assert_str(result.message).contains(str(SimSave.VERSION + 1))


func test_missing_or_non_int_version_is_rejected() -> void:
	_assert_rejected(_envelope({}, ["version"]), &"corrupt")
	_assert_rejected(_envelope({"version": "1"}), &"corrupt")
	_assert_rejected(_envelope({"version": 1.0}), &"corrupt")


func test_state_section_missing_or_malformed_is_rejected() -> void:
	_assert_rejected(_envelope({}, ["state"]), &"corrupt")
	var bad_state: Dictionary = (bytes_to_var(SimSave.encode(new_state())) as Dictionary)["state"]
	bad_state.erase("rng")
	_assert_rejected(_envelope({"state": bad_state}), &"corrupt")


func test_tampered_state_fails_integrity_hash() -> void:
	var envelope: Dictionary = bytes_to_var(SimSave.encode(_busy_state(new_sim_full())))
	envelope["state"]["tick"] = int(envelope["state"]["tick"]) + 1
	_assert_rejected(var_to_bytes(envelope), &"hash_mismatch")


func test_failed_load_does_not_throw_and_valid_load_still_works_after() -> void:
	SimSave.decode(PackedByteArray([0, 1, 2]))
	var state := new_state()
	assert_bool(SimSave.decode(SimSave.encode(state)).ok).is_true()
