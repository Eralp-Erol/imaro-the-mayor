extends GdUnitTestSuite
## T-042 adım 2 · Kayıt/yükleme (ADR-0005 Ek E): ağ, kayıttaki yol listesiyle eşitlenir (ortak önek -> fazlası LIFO geri
## al -> eksiği uygula, her adımda graf hash'i); uyuşmazlıkta yükleme reddedilir ve ESKİ durum + ağ korunur. Yolla
## kaydet
## -> yükle -> N tick, kesintisiz koşuyla aynı hash.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const TAIL := 50


func _f(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


func _net(run: Dictionary) -> WorldNetwork:
	return run["net"]


func _with_one_road(world_seed: int = P.SEED) -> Dictionary:
	var run := P.setup(world_seed)
	_f(run).advance(10)
	_f(run).submit_command(P.road(P.spur_a_cm()))
	_f(run).advance(10)
	return run


func test_save_load_with_a_road_continues_to_the_same_hash_as_an_uninterrupted_run() -> void:
	var straight := _with_one_road()
	_f(straight).advance(TAIL)
	var first := _with_one_road()
	var bytes := _f(first).export_save()
	assert_int(bytes.size()).is_greater(0)
	var fresh := P.setup(P.SEED)  # yeni oyun + taze ağ (yol yok), kayıt yolu ağa işler
	var result := _f(fresh).import_save(bytes)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_int(_net(fresh).delta.ops.size()).is_equal(1)
	assert_str(_net(fresh).graph_hash()).is_equal(_net(first).graph_hash())
	_f(fresh).advance(TAIL)
	assert_str(_f(fresh).state_hash()).is_equal(_f(straight).state_hash())
	assert_str(_net(fresh).graph_hash()).is_equal(_net(straight).graph_hash())


func test_loading_a_save_without_roads_removes_the_roads_drawn_since() -> void:
	var run := P.setup()
	_f(run).advance(10)
	var bytes := _f(run).export_save()  # yol yok, bölüm yok
	_f(run).submit_command(P.road(P.spur_a_cm()))
	_f(run).advance(1)
	_f(run).submit_command(P.road(P.spur_b_cm()))
	_f(run).advance(1)
	var base_graph := P.network().graph_hash()
	assert_int(_net(run).delta.ops.size()).is_equal(2)
	var result := _f(run).import_save(bytes)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_int(_net(run).delta.ops.size()).is_equal(0)
	assert_str(_net(run).graph_hash()).is_equal(base_graph)
	assert_int(_f(run).public_works().size()).is_equal(0)


func test_loading_an_older_two_road_save_undoes_only_the_extra_road() -> void:
	var run := _with_one_road()
	var bytes_one := _f(run).export_save()
	_f(run).submit_command(P.road(P.spur_b_cm()))
	_f(run).advance(1)
	assert_int(_net(run).delta.ops.size()).is_equal(2)
	var result := _f(run).import_save(bytes_one)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_int(_net(run).delta.ops.size()).is_equal(1)
	assert_int(_f(run).public_works().size()).is_equal(1)
	assert_str(_net(run).graph_hash()).is_equal(_net(_with_one_road()).graph_hash())


func test_save_after_undoing_every_road_keeps_an_empty_section_and_loads_cleanly() -> void:
	var run := _with_one_road()
	_f(run).submit_command(SimCommand.public_work_undo_last())
	_f(run).advance(1)
	var bytes := _f(run).export_save()
	assert_int((bytes_to_var(bytes)["state"]["systems"]["public_works"]["ops"] as Array).size()).is_equal(0)
	var other := _with_one_road(P.SEED + 5)  # başka oyunda 1 yol var; kayıt 0 yol diyor
	assert_bool(_f(other).import_save(bytes).ok).is_true()
	assert_int(_net(other).delta.ops.size()).is_equal(0)
	assert_str(_net(other).graph_hash()).is_equal(P.network().graph_hash())
	assert_str(_f(other).state_hash()).is_equal(_f(run).state_hash())


func test_load_in_the_middle_of_a_pending_road_command_keeps_the_queue() -> void:
	var run := P.setup()
	_f(run).advance(5)
	_f(run).submit_command(P.road(P.spur_a_cm()))  # kuyrukta, henüz uygulanmadı
	var bytes := _f(run).export_save()
	var other := P.setup()
	assert_bool(_f(other).import_save(bytes).ok).is_true()
	assert_int(_net(other).delta.ops.size()).is_equal(0)
	_f(other).advance(1)
	assert_int(_net(other).delta.ops.size()).is_equal(1)
	_f(run).advance(1)
	assert_str(_f(other).state_hash()).is_equal(_f(run).state_hash())


func test_a_save_whose_graph_hash_does_not_match_is_rejected_and_the_old_state_survives() -> void:
	var source := _with_one_road()
	var bytes := _f(source).export_save()
	# Bozuk kayıt: bölümdeki graf özeti oynanmış, ama zarf hash'i de yeniden hesaplanmış (yalnız ağ eşitleme yakalar).
	var tampered := _tamper(bytes, func(section: Dictionary) -> void:
		section["hashes"][0] = "0".repeat(64))
	var run := _with_one_road(P.SEED + 1)
	var hash_before := _f(run).state_hash()
	var graph_before := _net(run).graph_hash()
	var result := _f(run).import_save(tampered)
	assert_bool(result.ok).is_false()
	assert_str(String(result.error_code)).is_equal("network_mismatch")
	assert_str(_f(run).state_hash()).is_equal(hash_before)
	assert_str(_net(run).graph_hash()).is_equal(graph_before)
	assert_int(_net(run).delta.ops.size()).is_equal(1)


func test_a_save_with_an_op_the_network_cannot_apply_is_rejected_and_the_old_state_survives() -> void:
	var source := _with_one_road()
	# Taban ağdan farklı bir dünyada çizilmiş yol (suyun içinde): uygulanamaz.
	var tampered := _tamper(_f(source).export_save(), func(section: Dictionary) -> void:
		section["ops"][0]["pts_cm"] = [[270000, 25000], [270000, 45000]])
	var run := P.setup()
	_f(run).advance(3)
	var hash_before := _f(run).state_hash()
	var result := _f(run).import_save(tampered)
	assert_bool(result.ok).is_false()
	assert_str(String(result.error_code)).is_equal("network_mismatch")
	assert_str(_f(run).state_hash()).is_equal(hash_before)
	assert_int(_net(run).delta.ops.size()).is_equal(0)


func test_a_save_for_another_base_network_is_rejected() -> void:
	var source := _with_one_road()
	var tampered := _tamper(_f(source).export_save(), func(section: Dictionary) -> void:
		section["base_graph_hash"] = "f".repeat(64))
	var run := P.setup()
	var result := _f(run).import_save(tampered)
	assert_bool(result.ok).is_false()
	assert_str(String(result.error_code)).is_equal("network_mismatch")


func test_malformed_section_is_rejected_as_a_corrupt_save() -> void:
	var source := _with_one_road()
	for mutate: Callable in [
			func(s: Dictionary) -> void: s["hashes"] = [],
			func(s: Dictionary) -> void: s["works"] = [],
			func(s: Dictionary) -> void: s["infra_bonus"] = {"X": 999},
			func(s: Dictionary) -> void: s["ops"][0]["op"] = "remove_edge"]:
		var run := P.setup()
		var result := _f(run).import_save(_tamper(_f(source).export_save(), mutate))
		assert_bool(result.ok).is_false()
		assert_str(String(result.error_code)).is_equal("corrupt")
		assert_int(_net(run).delta.ops.size()).is_equal(0)


func test_a_save_with_roads_cannot_load_into_a_facade_without_a_network() -> void:
	var source := _with_one_road()
	var plain := EconomyBootstrap.create(P.SEED, P.source(), EconomyTestSupport.config(P.economy_patch()))
	var result := plain.facade.import_save(_f(source).export_save())
	assert_bool(result.ok).is_false()
	assert_str(String(result.error_code)).is_equal("network_mismatch")


func test_state_without_roads_still_round_trips_without_a_network() -> void:
	var plain := EconomyBootstrap.create(P.SEED, P.source(), EconomyTestSupport.config(P.economy_patch()))
	plain.facade.advance(5)
	var other := EconomyBootstrap.create(P.SEED, P.source(), EconomyTestSupport.config(P.economy_patch()))
	assert_bool(other.facade.import_save(plain.facade.export_save()).ok).is_true()
	assert_str(other.facade.state_hash()).is_equal(plain.facade.state_hash())


## Kaydı açar, `public_works` bölümünü değiştirir, geçerli zarf hash'iyle yeniden kodlar (bütünlük hash'i değil, ağ
## eşitleme ve bölüm doğrulaması yakalamalı).
func _tamper(bytes: PackedByteArray, mutate: Callable) -> PackedByteArray:
	var envelope: Dictionary = bytes_to_var(bytes)
	var body: Dictionary = envelope["state"]
	mutate.call(body["systems"]["public_works"])
	envelope["state_hash"] = StateHash.of(body)
	return var_to_bytes(envelope)
