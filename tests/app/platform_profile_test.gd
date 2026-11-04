extends GdUnitTestSuite
## T-007 ölçüt 4 · PlatformProfile: etiketlerden profil, kullanıcı ayarıyla geçersiz kılma, bozuk değerin reddi.
## Saf mantık (OS'a dokunmayan `from_tags`); `detect()` ayrıca bu makinede tutarlılık için denenir.

const TMP_DIR := "user://platform_profile_test"


func _tags(list: Array[String]) -> PackedStringArray:
	return PackedStringArray(list)


func after() -> void:
	PlatformProfile.reset_current()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR + "/settings.cfg"))


# --- platform -> varsayılan profil ---

func test_macos_and_windows_are_desktop_profiles() -> void:
	for platform: String in ["macos", "windows"]:
		var p := PlatformProfile.from_tags(_tags([platform, "pc"]))
		assert_str(String(p.platform)).is_equal(platform)
		assert_str(String(p.input_profile)).is_equal("desktop")
		assert_str(String(p.ui_profile)).is_equal("desktop")
		assert_bool(p.hover_available).is_true()
		assert_float(p.ui_scale).is_equal(1.0)
		assert_int(p.max_game_speed).is_greater_equal(1)
		assert_int(p.tick_slicing).is_greater_equal(1)


func test_ios_is_the_touch_profile_with_44pt_targets_and_no_hover() -> void:
	var p := PlatformProfile.from_tags(_tags(["ios", "mobile"]))
	assert_str(String(p.platform)).is_equal("ios")
	assert_str(String(p.input_profile)).is_equal("touch")
	assert_bool(p.hover_available).is_false()
	assert_float(p.min_touch_target_pt).is_greater_equal(44.0)  # ADR-0004 §3
	assert_float(p.ui_scale).is_greater_equal(1.0)


func test_unknown_system_falls_back_to_desktop_dev_profile() -> void:
	var p := PlatformProfile.from_tags(_tags(["linux"]))
	assert_str(String(p.platform)).is_equal("other")
	assert_str(String(p.input_profile)).is_equal("desktop")
	assert_bool(PlatformProfile.from_tags(_tags([])).platform == PlatformProfile.PLATFORM_OTHER).is_true()


func test_desktop_is_never_throttled_below_touch_on_game_speed_or_slicing_by_default() -> void:
	# ADR-0004: masaüstü asla kısılmaz; iPad farkı ölçümle gelir, sessizce varsayılana yazılmaz.
	var desktop := PlatformProfile.from_tags(_tags(["macos"]))
	var touch := PlatformProfile.from_tags(_tags(["ios"]))
	assert_int(desktop.max_game_speed).is_greater_equal(touch.max_game_speed)


# --- geçersiz kılma ---

func test_user_override_changes_input_profile_and_reloads_that_profiles_defaults() -> void:
	var p := PlatformProfile.from_tags(_tags(["macos"]), {"input_profile": &"touch"})
	assert_str(String(p.input_profile)).is_equal("touch")
	assert_str(String(p.ui_profile)).is_equal("touch")
	assert_bool(p.hover_available).is_false()
	assert_float(p.min_touch_target_pt).is_greater_equal(44.0)
	assert_bool(p.applied_overrides.has("input_profile")).is_true()
	assert_str(String(p.platform)).is_equal("macos")  # platform kimliği değişmez


func test_overrides_apply_after_profile_defaults_regardless_of_dictionary_order() -> void:
	var a := PlatformProfile.from_tags(_tags(["macos"]), {"ui_scale": 1.5, "input_profile": &"touch"})
	var b := PlatformProfile.from_tags(_tags(["macos"]), {"input_profile": &"touch", "ui_scale": 1.5})
	assert_float(a.ui_scale).is_equal(1.5)
	assert_dict(_without_override_lists(a.to_dict())).is_equal(_without_override_lists(b.to_dict()))


func test_each_override_key_takes_effect() -> void:
	var p := PlatformProfile.from_tags(_tags(["windows"]), {
		"ui_scale": 2, "graphics_profile": "low", "max_game_speed": 2, "tick_slicing": 3,
	})
	assert_float(p.ui_scale).is_equal(2.0)
	assert_str(String(p.graphics_profile)).is_equal("low")
	assert_int(p.max_game_speed).is_equal(2)
	assert_int(p.tick_slicing).is_equal(3)
	assert_bool(p.graphics_settings()["shadows"]).is_false()
	assert_int(p.clamp_game_speed(99)).is_equal(2)
	assert_int(p.clamp_game_speed(-5)).is_equal(1)


func test_invalid_overrides_are_rejected_not_clamped_and_defaults_survive() -> void:
	var base := PlatformProfile.from_tags(_tags(["macos"]))
	var p := PlatformProfile.from_tags(_tags(["macos"]), {
		"input_profile": &"gamepad", "ui_scale": 99.0, "graphics_profile": &"ultra", "max_game_speed": 0,
		"tick_slicing": "2", "unknown_key": 1, "max_game_speed_x": 3,
	})
	assert_int(p.rejected_overrides.size()).is_equal(7)
	assert_int(p.applied_overrides.size()).is_equal(0)
	assert_dict(_without_override_lists(p.to_dict())).is_equal(_without_override_lists(base.to_dict()))


func test_type_confusion_in_overrides_does_not_crash() -> void:
	var p := PlatformProfile.from_tags(_tags(["ios"]), {
		"ui_scale": "big", "max_game_speed": 2.5, "input_profile": 5, "graphics_profile": null, "tick_slicing": [],
	})
	assert_int(p.rejected_overrides.size()).is_equal(5)
	assert_str(String(p.input_profile)).is_equal("touch")


# --- komut satırı ve kayıtlı ayar ---

func test_command_line_args_map_to_overrides() -> void:
	var o := PlatformProfile.overrides_from_args(PackedStringArray([
		"--imaro-input-profile=touch", "--imaro-ui-scale=1.5", "--imaro-graphics=low",
		"--imaro-max-speed=3", "--imaro-tick-slicing=2", "--unrelated=1", "--imaro-ui-scale",
	]))
	var p := PlatformProfile.from_tags(_tags(["macos"]), o)
	assert_str(String(p.input_profile)).is_equal("touch")
	assert_float(p.ui_scale).is_equal(1.5)
	assert_str(String(p.graphics_profile)).is_equal("low")
	assert_int(p.max_game_speed).is_equal(3)
	assert_int(p.tick_slicing).is_equal(2)
	assert_int(p.rejected_overrides.size()).is_equal(0)


func test_garbage_command_line_values_are_rejected() -> void:
	var o := PlatformProfile.overrides_from_args(PackedStringArray([
		"--imaro-ui-scale=abc", "--imaro-max-speed=1.5", "--imaro-input-profile=vr",
	]))
	var p := PlatformProfile.from_tags(_tags(["macos"]), o)
	assert_int(p.rejected_overrides.size()).is_equal(3)


func test_saved_settings_round_trip_and_missing_or_corrupt_file_is_empty() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var path := TMP_DIR + "/settings.cfg"
	assert_dict(PlatformProfile.load_overrides(path)).is_empty()  # dosya yok
	var err := PlatformProfile.save_overrides({"input_profile": &"touch", "ui_scale": 1.5, "junk": 1}, path)
	assert_int(err).is_equal(OK)
	var loaded := PlatformProfile.load_overrides(path)
	assert_bool(loaded.has("junk")).is_false()  # geçersiz anahtar yazılmaz
	var p := PlatformProfile.from_tags(_tags(["windows"]), loaded)
	assert_str(String(p.input_profile)).is_equal("touch")
	assert_float(p.ui_scale).is_equal(1.5)
	# Bozuk dosya: çökmeden boş.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[[[ bu ini degil")
	f.close()
	assert_dict(PlatformProfile.load_overrides(path)).is_empty()
	# Elle bozulmuş ama ayrıştırılabilir değer: reddedilir.
	var cfg := ConfigFile.new()
	cfg.set_value(PlatformProfile.SETTINGS_SECTION, "ui_scale", 50.0)
	cfg.save(path)
	var bad := PlatformProfile.from_tags(_tags(["windows"]), PlatformProfile.load_overrides(path))
	assert_array(bad.rejected_overrides).contains(["ui_scale"])
	assert_float(bad.ui_scale).is_equal(1.0)


# --- gerçek makine ---

func test_detect_matches_this_machine_and_current_is_cached() -> void:
	var p := PlatformProfile.detect({"input_profile": &"desktop"})  # kayıtlı ayardan bağımsız sabitle
	if OS.has_feature("macos"):
		assert_str(String(p.platform)).is_equal("macos")
	elif OS.has_feature("windows"):
		assert_str(String(p.platform)).is_equal("windows")
	assert_str(String(p.input_profile)).is_equal("desktop")
	PlatformProfile.reset_current()
	var a := PlatformProfile.current()
	assert_object(PlatformProfile.current()).is_same(a)
	PlatformProfile.reset_current()
	assert_object(PlatformProfile.current()).is_not_same(a)


func test_profile_creates_the_matching_input_profile() -> void:
	var desktop := PlatformProfile.from_tags(_tags(["macos"])).create_input_profile()
	var touch := PlatformProfile.from_tags(_tags(["ios"])).create_input_profile()
	assert_object(desktop).is_instanceof(DesktopInputProfile)
	assert_object(touch).is_instanceof(TouchInputProfile)
	assert_bool(desktop.supports_hover).is_true()
	assert_bool(touch.supports_hover).is_false()


func _without_override_lists(d: Dictionary) -> Dictionary:
	var c := d.duplicate()
	c.erase("applied_overrides")
	c.erase("rejected_overrides")
	return c
