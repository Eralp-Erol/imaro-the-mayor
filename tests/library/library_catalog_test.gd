extends GdUnitTestSuite
## T-052 · Katalog doğrulayıcı + Python birim testleri GdUnit4 hattından da koşsun (lane/verify uyumu).
## Python 3 yoksa test atlanır (assert yok) ve neden açıkça yazılır.


func _python() -> String:
	var out: Array = []
	if OS.execute("python3", ["--version"], out) == 0:
		return "python3"
	return ""


func test_catalog_validates() -> void:
	var py := _python()
	if py.is_empty():
		push_warning("python3 yok: katalog doğrulaması atlandı")
		return
	var out: Array = []
	var root := ProjectSettings.globalize_path("res://")
	var code := OS.execute(py, ["-I", root + "tools/library/validate_catalog.py", "--root", root, "-q"], out, true)
	assert_int(code).override_failure_message("katalog doğrulayıcı: %s" % str(out)).is_equal(0)


func test_catalog_python_unit_tests_pass() -> void:
	var py := _python()
	if py.is_empty():
		push_warning("python3 yok: katalog birim testleri atlandı")
		return
	var out: Array = []
	var root := ProjectSettings.globalize_path("res://")
	var code := OS.execute(py, ["-I", root + "tests/library/test_catalog.py"], out, true)
	assert_int(code).override_failure_message("python testleri: %s" % str(out)).is_equal(0)
