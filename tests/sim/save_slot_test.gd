extends SimTestBase
## T-027 ölçüt 6 · Kayıt yuvası G/Ç (src/app/save_slot*): yaz/oku/listele/sil, kampanya kimliği (CAN-09), bozuk dosya
## anlaşılır hata, atomik yazma. Sim saf kalır: dosya G/Ç yalnız bu katmanda; sim yalnız bayt verir/alır.

const CAMPAIGN_A := &"campaign.alpha"
const CAMPAIGN_B := &"campaign.beta"
## Kendi dizinimiz: GdUnit'in paylaşılan `user://tmp` dizinini başka hatların eşzamanlı koşuları silebilir.
const TEST_DIR := "user://sim_lane_test_save_slot"

var _dir: String = ""


func before_test() -> void:
	_remove_dir()
	_dir = TEST_DIR
	DirAccess.make_dir_recursive_absolute(_dir)


func after_test() -> void:
	_remove_dir()


func _remove_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		return
	for file_name in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR.path_join(file_name))
	DirAccess.remove_absolute(TEST_DIR)


func _facade() -> SimFacadeImpl:
	return FacadeTestSupport.facade(3)


func _played(ticks: int = 6) -> SimFacadeImpl:
	var f := _facade()
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"))
	f.advance(ticks)
	return f


func _write_raw(slot_id: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(SaveSlot.path_for(_dir, StringName(slot_id)), FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


# --- Kimlik doğrulama ---

func test_slot_and_campaign_ids_are_validated_against_path_tricks() -> void:
	for ok in ["slot1", "auto", "q-1", "a_b", "0day"]:
		assert_bool(SaveSlot.is_valid_slot_id(StringName(ok))).override_failure_message(ok).is_true()
	for bad in ["", "../x", "a/b", "A", "slot 1", "x.y", "-lead", "a".repeat(33), "..", "c:\\x", "slot\n"]:
		assert_bool(SaveSlot.is_valid_slot_id(StringName(bad))).override_failure_message("kabul: %s" % bad).is_false()
	assert_bool(SaveSlot.is_valid_campaign_id(CAMPAIGN_A)).is_true()
	for bad in ["", "../c", "a b", "Camp", "x/y"]:
		assert_bool(SaveSlot.is_valid_campaign_id(StringName(bad))).override_failure_message("kabul: %s" % bad).is_false()


func test_invalid_ids_are_rejected_before_touching_the_disk() -> void:
	var f := _played()
	var r := SaveSlot.save_facade(_dir, &"../evil", CAMPAIGN_A, f)
	assert_bool(r.ok).is_false()
	assert_str(String(r.error_code)).is_equal("invalid_slot_id")
	r = SaveSlot.save_facade(_dir, &"slot1", &"Bad Campaign", f)
	assert_str(String(r.error_code)).is_equal("invalid_campaign_id")
	assert_array(SaveSlot.list(_dir)).is_empty()
	assert_str(String(SaveSlot.read(_dir, &"../evil").error_code)).is_equal("invalid_slot_id")
	assert_str(String(SaveSlot.remove(_dir, &"a/b").error_code)).is_equal("invalid_slot_id")


# --- Yaz / oku ---

func test_write_then_read_round_trips_campaign_and_sim_state() -> void:
	var f := _played(7)
	var wrote := SaveSlot.save_facade(_dir, &"slot1", CAMPAIGN_A, f)
	assert_bool(wrote.ok).override_failure_message(wrote.message).is_true()
	assert_bool(FileAccess.file_exists(SaveSlot.path_for(_dir, &"slot1"))).is_true()
	var read := SaveSlot.read(_dir, &"slot1")
	assert_bool(read.ok).override_failure_message(read.message).is_true()
	assert_str(String(read.campaign_id)).is_equal("campaign.alpha")
	assert_str(String(read.slot_id)).is_equal("slot1")
	assert_int(read.tick).is_equal(f.current_tick())
	assert_int(read.world_seed).is_equal(FacadeTestSupport.SEED)
	assert_bool(read.sim_bytes == f.export_save()).is_true()


func test_load_into_a_fresh_facade_restores_state_and_campaign() -> void:
	var f := _played(7)
	SaveSlot.save_facade(_dir, &"slot1", CAMPAIGN_A, f)
	var fresh := _facade()
	var r := SaveSlot.load_into(_dir, &"slot1", fresh)
	assert_bool(r.ok).override_failure_message(r.message).is_true()
	assert_str(fresh.state_hash()).is_equal(f.state_hash())
	assert_str(String(fresh.campaign_id)).is_equal("campaign.alpha")
	assert_str(String(fresh.snapshot().scenario_id)).is_equal("campaign.alpha")
	fresh.advance(5)
	f.advance(5)
	assert_str(fresh.state_hash()).override_failure_message("yükle -> devam = kesintisiz").is_equal(f.state_hash())


func test_overwrite_replaces_the_slot_atomically_and_leaves_no_temp_file() -> void:
	var f := _played(3)
	SaveSlot.save_facade(_dir, &"slot1", CAMPAIGN_A, f)
	f.advance(10)
	assert_bool(SaveSlot.save_facade(_dir, &"slot1", CAMPAIGN_A, f).ok).is_true()
	assert_int(SaveSlot.read(_dir, &"slot1").tick).is_equal(13)
	var files := DirAccess.get_files_at(_dir)
	assert_int(files.size()).override_failure_message(str(files)).is_equal(1)
	assert_bool(String(files[0]).ends_with(SaveSlot.EXTENSION)).is_true()


func test_failed_overwrite_keeps_the_previous_good_slot() -> void:
	var f := _played(3)
	SaveSlot.save_facade(_dir, &"slot1", CAMPAIGN_A, f)
	var before := SaveSlot.read(_dir, &"slot1").sim_bytes
	var r := SaveSlot.write(_dir, &"slot1", CAMPAIGN_A, PackedByteArray([1, 2, 3]))
	assert_bool(r.ok).is_false()
	assert_bool(SaveSlot.read(_dir, &"slot1").sim_bytes == before) \
		.override_failure_message("eski kayıt bozulmamalı").is_true()


# --- Kampanya izolasyonu (CAN-09) ---

func test_campaigns_are_kept_apart() -> void:
	var f := _played()
	SaveSlot.save_facade(_dir, &"a1", CAMPAIGN_A, f)
	SaveSlot.save_facade(_dir, &"a2", CAMPAIGN_A, f)
	SaveSlot.save_facade(_dir, &"b1", CAMPAIGN_B, f)
	assert_array(SaveSlot.list(_dir, CAMPAIGN_A).map(func(i: SaveSlot.Info) -> String: return String(i.slot_id))) \
		.is_equal(["a1", "a2"])
	assert_array(SaveSlot.list(_dir, CAMPAIGN_B).map(func(i: SaveSlot.Info) -> String: return String(i.slot_id))) \
		.is_equal(["b1"])
	assert_int(SaveSlot.list(_dir).size()).is_equal(3)
	var wrong := SaveSlot.read(_dir, &"b1", CAMPAIGN_A)
	assert_bool(wrong.ok).is_false()
	assert_str(String(wrong.error_code)).is_equal("campaign_mismatch")
	assert_str(wrong.message).contains("campaign.beta")
	var fresh := _facade()
	assert_str(String(SaveSlot.load_into(_dir, &"b1", fresh, CAMPAIGN_A).error_code)).is_equal("campaign_mismatch")
	assert_int(fresh.current_tick()).override_failure_message("reddedilen yükleme durumu değiştirmemeli").is_equal(0)
	assert_bool(SaveSlot.load_into(_dir, &"b1", fresh, CAMPAIGN_B).ok).is_true()


# --- Listeleme ---

func test_list_is_sorted_and_reports_header_fields() -> void:
	var f := _played(2)
	SaveSlot.save_facade(_dir, &"zeta", CAMPAIGN_A, f)
	f.advance(4)
	SaveSlot.save_facade(_dir, &"alpha", CAMPAIGN_A, f)
	var infos := SaveSlot.list(_dir)
	assert_int(infos.size()).is_equal(2)
	assert_str(String(infos[0].slot_id)).is_equal("alpha")
	assert_str(String(infos[1].slot_id)).is_equal("zeta")
	assert_bool(infos[0].ok).is_true()
	assert_int(infos[0].tick).is_equal(6)
	assert_int(infos[1].tick).is_equal(2)
	assert_str(String(infos[0].campaign_id)).is_equal("campaign.alpha")


func test_list_of_missing_directory_is_empty_and_ignores_foreign_files() -> void:
	assert_array(SaveSlot.list(_dir + "/does_not_exist")).is_empty()
	var stray := FileAccess.open(_dir + "/readme.txt", FileAccess.WRITE)
	stray.store_string("hi")
	stray.close()
	assert_array(SaveSlot.list(_dir)).override_failure_message("yuva olmayan dosya listelenmemeli").is_empty()


# --- Bozuk dosyalar ---

func test_garbage_file_is_reported_as_corrupt_without_crashing() -> void:
	_write_raw("junk", PackedByteArray([9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 255]))
	var r := SaveSlot.read(_dir, &"junk")
	assert_bool(r.ok).is_false()
	assert_str(String(r.error_code)).is_equal("corrupt")
	assert_str(r.message).is_not_empty()
	var infos := SaveSlot.list(_dir)
	assert_int(infos.size()).is_equal(1)
	assert_bool(infos[0].ok).is_false()
	assert_str(String(infos[0].error_code)).is_equal("corrupt")
	assert_bool(SaveSlot.load_into(_dir, &"junk", _facade()).ok).is_false()


func test_empty_and_missing_files_have_their_own_errors() -> void:
	_write_raw("empty", PackedByteArray())
	assert_str(String(SaveSlot.read(_dir, &"empty").error_code)).is_equal("empty")
	assert_str(String(SaveSlot.read(_dir, &"nothere").error_code)).is_equal("not_found")
	assert_str(String(SaveSlot.remove(_dir, &"nothere").error_code)).is_equal("not_found")


func test_truncated_and_tampered_saves_are_rejected_with_sim_codes() -> void:
	var f := _played()
	SaveSlot.save_facade(_dir, &"good", CAMPAIGN_A, f)
	var good := FileAccess.get_file_as_bytes(SaveSlot.path_for(_dir, &"good"))
	_write_raw("cut", good.slice(0, good.size() / 2))
	assert_bool(SaveSlot.read(_dir, &"cut").ok).is_false()
	# Sim baytı içeride değiştirilirse (kayıt hash'i) sim kodu geçer.
	var envelope: Dictionary = bytes_to_var(good)
	var sim_envelope: Dictionary = bytes_to_var(envelope["sim_save"])
	sim_envelope["state"]["tick"] = int(sim_envelope["state"]["tick"]) + 1
	envelope["sim_save"] = var_to_bytes(sim_envelope)
	envelope["slot_id"] = "tampered"
	_write_raw("tampered", var_to_bytes(envelope))
	var r := SaveSlot.read(_dir, &"tampered")
	assert_bool(r.ok).is_false()
	assert_str(String(r.error_code)).is_equal("hash_mismatch")


func test_wrong_container_format_version_and_header_fields_are_rejected() -> void:
	var f := _played()
	SaveSlot.save_facade(_dir, &"good", CAMPAIGN_A, f)
	var good: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(SaveSlot.path_for(_dir, &"good")))
	var cases := {
		"fmt": [{"format": "other"}, "bad_format"],
		"newer": [{"version": SaveSlot.VERSION + 1}, "version_too_new"],
		"older": [{"version": SaveSlot.MIN_SUPPORTED_VERSION - 1}, "version_too_old"],
		"nover": [{"version": "1"}, "corrupt"],
		"badcamp": [{"campaign_id": "../x"}, "corrupt"],
		"slotname": [{"slot_id": "someoneelse"}, "corrupt"],
		"nosim": [{"sim_save": "text"}, "corrupt"],
	}
	for slot: String in cases:
		var mutated := good.duplicate(true)
		mutated.merge(cases[slot][0], true)
		_write_raw(slot, var_to_bytes(mutated))
		var r := SaveSlot.read(_dir, StringName(slot))
		assert_bool(r.ok).override_failure_message("kabul: %s" % slot).is_false()
		assert_str(String(r.error_code)).override_failure_message(slot).is_equal(cases[slot][1])
		assert_str(r.message).is_not_empty()


func test_slot_with_other_world_is_rejected_on_load_and_facade_is_untouched() -> void:
	var other := SimFacadeImpl.create(FacadeTestSupport.SEED, FacadeTestSupport.fixture_source(2))
	other.advance(3)
	var wrote := SaveSlot.save_facade(_dir, &"other", CAMPAIGN_A, other)
	assert_bool(wrote.ok).override_failure_message(wrote.message).is_true()
	var f := _facade()
	var h := f.state_hash()
	var r := SaveSlot.load_into(_dir, &"other", f)
	assert_bool(r.ok).is_false()
	assert_str(String(r.error_code)).is_equal("world_mismatch")
	assert_str(f.state_hash()).is_equal(h)


# --- Silme ---

func test_remove_deletes_only_that_slot() -> void:
	var f := _played()
	SaveSlot.save_facade(_dir, &"keep", CAMPAIGN_A, f)
	SaveSlot.save_facade(_dir, &"drop", CAMPAIGN_A, f)
	assert_bool(SaveSlot.remove(_dir, &"drop").ok).is_true()
	assert_array(SaveSlot.list(_dir).map(func(i: SaveSlot.Info) -> String: return String(i.slot_id))).is_equal(["keep"])
	assert_bool(SaveSlot.read(_dir, &"keep").ok).is_true()
