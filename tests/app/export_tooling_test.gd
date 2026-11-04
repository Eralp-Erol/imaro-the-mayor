extends GdUnitTestSuite
## T-007 ölçüt 2/3 · export_presets.cfg yapısı + gizli bilgi yokluğu; tools/export.sh çıkış kodları (Godot koşmadan).
## Gerçek export/duman testi şablon gerektirir: bkz. `tools/export.sh` (burada KOŞULMAZ).

const PRESETS := "res://export_presets.cfg"
const SECRET_KEYS: PackedStringArray = [
	"codesign/certificate_password", "codesign/certificate_file", "codesign/identity", "codesign/apple_team_id",
	"codesign/provisioning_profile", "codesign/password", "application/app_store_team_id",
	"application/code_sign_identity_debug", "application/code_sign_identity_release",
	"application/provisioning_profile_uuid_debug", "application/provisioning_profile_uuid_release",
	"application/provisioning_profile_specifier_debug", "application/provisioning_profile_specifier_release",
	"notarization/apple_id_name", "notarization/apple_id_password", "notarization/api_uuid",
	"notarization/api_key", "notarization/api_key_id", "codesign/installer_identity",
]


func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	assert_int(cfg.load(PRESETS)).is_equal(OK)
	return cfg


func _preset(cfg: ConfigFile, platform: String) -> String:
	for i in 8:
		var section := "preset.%d" % i
		if cfg.has_section(section) and cfg.get_value(section, "platform", "") == platform:
			return section
	return ""


func _sh(args: PackedStringArray, env_prefix := "") -> Dictionary:
	var root := ProjectSettings.globalize_path("res://")
	var out: Array = []
	var cmd := "cd '%s' && %s tools/export.sh %s" % [root, env_prefix, " ".join(args)]
	var code := OS.execute("/bin/bash", ["-c", cmd + " 2>&1"], out)
	return {"code": code, "out": "".join(out)}


func test_presets_define_macos_windows_and_ios_ipad() -> void:
	var cfg := _cfg()
	var mac := _preset(cfg, "macOS")
	var win := _preset(cfg, "Windows Desktop")
	var ios := _preset(cfg, "iOS")
	assert_str(mac).is_not_empty()
	assert_str(win).is_not_empty()
	assert_str(ios).is_not_empty()
	assert_str(cfg.get_value(win + ".options", "binary_format/architecture")).is_equal("x86_64")
	assert_int(cfg.get_value(ios + ".options", "application/targeted_device_family")).is_equal(1)  # iPad
	assert_bool(cfg.get_value(ios + ".options", "application/export_project_only")).is_true()  # imza/derleme T-008
	assert_int(cfg.get_value(mac + ".options", "codesign/codesign")).is_equal(0)  # imzasız geliştirme
	assert_bool(cfg.get_value(win + ".options", "codesign/enable")).is_false()
	for section: String in [mac, win, ios]:
		assert_str(cfg.get_value(section, "export_path")).starts_with("build/")  # build/ gitignore'da


func test_presets_contain_no_secrets_or_identities() -> void:
	var cfg := _cfg()
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			if SECRET_KEYS.has(key):
				assert_str(str(cfg.get_value(section, key))).is_empty()
	var raw := FileAccess.get_file_as_string(PRESETS)
	assert_bool(raw.contains("password=\"") and not raw.contains("password=\"\"")).is_false()
	assert_bool(raw.contains(".p12") or raw.contains(".pfx") or raw.contains(".mobileprovision")).is_false()


func test_presets_exclude_tests_and_tooling_from_exports() -> void:
	var cfg := _cfg()
	for section in cfg.get_sections():
		if cfg.has_section_key(section, "exclude_filter"):
			var filter: String = cfg.get_value(section, "exclude_filter")
			for needle in ["tests/*", "artifacts/*", "addons/gdUnit4/*", "build/*"]:
				assert_bool(filter.contains(needle)).is_true()


func test_export_script_is_valid_bash_and_executable() -> void:
	var r := _sh(PackedStringArray(["templates", ">/dev/null"]), "IMARO_EXPORT_TEMPLATES_DIR=/nonexistent_imaro_tpl")
	assert_int(OS.execute("/bin/bash", ["-n", ProjectSettings.globalize_path("res://tools/export.sh")])).is_equal(0)
	assert_int(r["code"]).is_not_equal(1)  # sözdizimi/kullanım çökmesi değil


func test_usage_errors_exit_2_without_running_godot() -> void:
	assert_int(_sh(PackedStringArray([]))["code"]).is_equal(2)
	assert_int(_sh(PackedStringArray(["linux"]))["code"]).is_equal(2)
	assert_int(_sh(PackedStringArray(["macos", "--bogus"]))["code"]).is_equal(2)
	assert_int(_sh(PackedStringArray(["install-templates", "/nonexistent/x.tpz"]))["code"]).is_equal(2)


func test_missing_templates_fail_with_nonzero_exit_and_a_clear_download_instruction() -> void:
	for platform in ["macos", "windows", "ios"]:
		var r := _sh(PackedStringArray([platform]), "IMARO_EXPORT_TEMPLATES_DIR=/nonexistent_imaro_tpl")
		assert_int(r["code"]).is_equal(4)
		var out: String = r["out"]
		assert_bool(out.contains("https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/")).is_true()
		assert_bool(out.contains("Godot_v4.7.2-stable_export_templates.tpz")).is_true()
		assert_bool(out.contains("1281349702")).is_true()
		assert_bool(out.contains("SHA-512")).is_true()
		assert_bool(out.contains("KULLANICI ONAYI")).is_true()
	# --release da aynı kapıdan geçer
	var rel := _sh(PackedStringArray(["windows", "--release"]), "IMARO_EXPORT_TEMPLATES_DIR=/nonexistent_imaro_tpl")
	assert_int(rel["code"]).is_equal(4)


func test_wrong_template_version_is_rejected() -> void:
	var dir := ProjectSettings.globalize_path("user://export_tooling_test/tpl")
	var ver_dir := dir.path_join("4.7.2.stable")
	DirAccess.make_dir_recursive_absolute(ver_dir)
	var f := FileAccess.open(ver_dir.path_join("version.txt"), FileAccess.WRITE)
	f.store_string("4.6.1.stable")
	f.close()
	var g := FileAccess.open(ver_dir.path_join("macos.zip"), FileAccess.WRITE)
	g.store_string("x")
	g.close()
	var r := _sh(PackedStringArray(["macos"]), "IMARO_EXPORT_TEMPLATES_DIR='%s'" % dir)
	assert_int(r["code"]).is_equal(4)
	for p in ["version.txt", "macos.zip"]:
		DirAccess.remove_absolute(ver_dir.path_join(p))
	DirAccess.remove_absolute(ver_dir)
	DirAccess.remove_absolute(dir)


func test_install_templates_rejects_a_tampered_or_wrong_size_archive() -> void:
	var dir := ProjectSettings.globalize_path("user://export_tooling_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("fake.tpz")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("bu bir sablon degil")
	f.close()
	var env := "IMARO_EXPORT_TEMPLATES_DIR='%s'" % dir.path_join("tpl")
	var r := _sh(PackedStringArray(["install-templates", "'%s'" % path]), env)
	assert_int(r["code"]).is_equal(5)
	assert_bool(DirAccess.dir_exists_absolute(dir.path_join("tpl/4.7.2.stable"))).is_false()  # kurulum yapılmadı
	DirAccess.remove_absolute(path)
