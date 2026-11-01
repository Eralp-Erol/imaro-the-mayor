extends GdUnitTestSuite
## Sözleşme 1.6 (ADR-0005 Ek H, ADR-0009 Değişiklik 3; T-042c, D-014 §1) · Yolu yık yüzeyi: `public_work.demolish`
## komutu, `public_work.demolished` olayı, `undo_available()`/`demolish_cost()` sorguları ve varsayılanları.
## Yeniden iskân (1.7) bu testin kapsamında DEĞİL. Gerçek sim davranışı tests/sim/public_works/demolish_*.

const S := preload("res://tests/contracts/contract_test_support.gd")


func test_version_is_1_6_and_the_surface_arrived_in_that_minor() -> void:
	assert_str(SimContract.VERSION).is_equal("1.6")
	assert_int(SimContract.VERSION_MAJOR).is_equal(1)
	assert_int(SimContract.VERSION_MINOR).is_equal(6)
	assert_bool(SimContract.is_compatible("1.5")).is_true()
	assert_bool(SimContract.is_compatible("1.6")).is_true()
	assert_bool(SimContract.is_compatible("2.0")).is_false()


func test_demolish_is_a_catalogued_mayor_verb_with_one_required_int() -> void:
	assert_str(String(SimCommand.KIND_PUBLIC_WORK_DEMOLISH)).is_equal("public_work.demolish")
	assert_bool(SimCommand.CATALOG.has(&"public_work.demolish")).is_true()
	assert_bool(SimCommand.is_forbidden_kind(SimCommand.KIND_PUBLIC_WORK_DEMOLISH)).is_false()
	var c := SimCommand.public_work_demolish(7)
	assert_bool(c.validate_shape().is_empty()).is_true()
	assert_int(int(c.params["command_id"])).is_equal(7)
	var wrong := SimCommand.make(&"public_work.demolish", {"command_id": "7"})
	assert_str(String(wrong.validate_shape()["reason_key"])).is_equal("command.reject.bad_param_type")
	var missing := SimCommand.make(&"public_work.demolish", {})
	assert_bool(missing.validate_shape().is_empty()).is_false()


func test_demolished_event_kind_is_defined_and_distinct_from_removed() -> void:
	assert_str(String(SimEvent.KIND_PUBLIC_WORK_DEMOLISHED)).is_equal("public_work.demolished")
	assert_bool(SimEvent.KIND_PUBLIC_WORK_DEMOLISHED != SimEvent.KIND_PUBLIC_WORK_REMOVED).is_true()


func test_default_cost_query_reports_unknown_for_a_facade_that_does_not_override_it() -> void:
	# Mock `demolish_cost`u geçersiz kılmaz: soyut sınıfın varsayılanı -1 (bilinmiyor), uydurma maliyet yok.
	var f := S.facade(S.SCENARIO_POSITIVE)
	assert_int(f.demolish_cost(1)).is_equal(-1)
	assert_int(f.demolish_cost(0)).is_equal(-1)


func test_mock_undo_is_closed_before_any_road_exists() -> void:
	assert_bool(S.facade(S.SCENARIO_POSITIVE).undo_available()).is_false()


func test_mock_rejects_demolish_honestly_instead_of_accepting_a_dead_command() -> void:
	# Mock yol geometrisi tutmaz, yıkımı uygulayamaz: "queued" demek ölü düğme olurdu. Ön doğrulama ve gönderim reddeder.
	var f := S.facade(S.SCENARIO_POSITIVE)
	var cmd := SimCommand.public_work_demolish(1)
	var probe := f.validate_command(cmd)
	assert_bool(probe.is_rejected()).is_true()
	assert_str(String(probe.reason_key)).is_equal("public_work.reject.demolition_mock")
	var sent := f.submit_command(cmd)
	assert_bool(sent.is_rejected()).is_true()
	assert_str(String(sent.reason_key)).is_equal("public_work.reject.demolition_mock")
	# Neden oyuncuya Türkçe ve MOCK olarak söylenir (ham anahtar yok); yol paneli bunu "yıkılamaz" satırında kullanır.
	UiText.reset()
	UiText.report_missing = false
	var text := UiText.reject_reason(probe.reason_key, probe.args)
	assert_str(text).contains("MOCK")
	assert_array(Array(UiText.missing_keys())).is_empty()
