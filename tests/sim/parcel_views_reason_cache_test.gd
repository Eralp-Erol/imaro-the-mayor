extends SimTestBase
## `SimFacadeImpl.parcel_views` gerekçe dizini önbelleği (2026-11-01, ADR önerisi §2.3): her çağrıda tüm günlüğü taramak
## yerine facade-yerel önbellek (anahtar: durum + günlük örneği + first_id/last_id/boyut + limit). Çıktı bit-bit aynı,
## durum/hash'e girmez; günlük değişince YENİLENİR (bayatlama yok).

const M := preload("res://tests/sim/m2_support.gd")


## Günlük okumalarını sayan günlük (önbelleğin gerçekten devreye girdiğini ölçmek için): `scans` = tam tarama
## (`subject_index`, eski yol), `peeks` = kayıt başına kopyasız okuma (yeni yol: yalnız YENİ kayıtlar için).
class CountingLog:
	extends ReasonLog
	var scans: int = 0
	var peeks: int = 0

	func subject_index(wanted: Dictionary, limit: int) -> Dictionary:
		scans += 1
		return super.subject_index(wanted, limit)

	func peek(id: int) -> Dictionary:
		peeks += 1
		return super.peek(id)


func _wanted(ids: PackedInt64Array) -> Dictionary:
	var wanted := {}
	for id in ids:
		wanted[String(SimContract.parcel_ref(id))] = true
	return wanted


## Önbelleksiz referans: günlüğün kendi `subject_index`i (eski yol).
func _expected(f: SimFacadeImpl, ids: PackedInt64Array) -> Array:
	var index := f.game_state().reasons.subject_index(_wanted(ids), FacadeConfig.load_default().parcel_reason_limit)
	var out: Array = []
	for id in ids:
		out.append(Array(index.get(String(SimContract.parcel_ref(id)), PackedInt64Array())))
	return out


func _got(f: SimFacadeImpl, ids: PackedInt64Array) -> Array:
	var out: Array = []
	for view in f.parcel_views(ids):
		out.append(Array(view.reason_ids))
	return out


func _facade() -> SimFacadeImpl:
	return M.politics_handle(M.E.regions(M.STRESS), 14).facade


func _subset(all: PackedInt64Array, rng: RandomNumberGenerator, n: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for _k in n:
		out.append(all[rng.randi_range(0, all.size() - 1)])
	return out


func test_cached_reason_ids_equal_the_uncached_subject_index_on_every_day_for_several_seeds() -> void:
	for world_seed in [20261020, 7, 99001]:
		var h := M.politics_handle(M.E.regions(M.STRESS), 14, world_seed)
		var f := h.facade
		f.submit_command(SimCommand.zoning_propose(f.parcel_ids(), &"zone.mixed"))
		var all := f.parcel_ids()
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed
		var seen_reasons := 0
		for _day in 40:
			f.advance(1)
			for _call in 3:  # aynı günde tekrar tekrar (önbellek isabeti) ve farklı alt kümeler
				var ids := _subset(all, rng, rng.randi_range(1, 12))
				var want := _expected(f, ids)
				assert_array(_got(f, ids)).override_failure_message("tohum %d gün %d" % [world_seed, f.current_tick()]) \
					.is_equal(want)
				for row: Array in want:
					seen_reasons += row.size()
			assert_array(_got(f, all)).is_equal(_expected(f, all))
		assert_int(seen_reasons).override_failure_message("hiç gerekçe görülmedi: test boş").is_greater(0)


func test_a_log_that_only_grows_costs_one_read_per_new_record_not_a_full_scan_per_call() -> void:
	var f := _facade()
	var state := f.game_state()
	var counting := CountingLog.new(1000)
	state.reasons = counting
	var ids := f.parcel_ids().slice(0, 8)
	var ref := String(SimContract.parcel_ref(ids[0]))
	state.reasons.record(0, &"actor.investor.1", &"decision.investor.develop", [], 0, &"c", PackedStringArray([ref]))
	f.parcel_views(ids)
	assert_int(counting.peeks).override_failure_message("ilk kurulum kayıt sayısı kadar okur").is_equal(1)
	for _i in 5:
		f.parcel_views(ids)
	f.parcel_views(f.parcel_ids().slice(0, 12))  # başka parseller: günlük değişmedi => yine okuma yok
	assert_int(counting.peeks).override_failure_message("değişmeyen günlük yeniden okundu").is_equal(1)
	var added := state.reasons.record(0, &"actor.investor.1", &"decision.investor.develop", [], 0, &"c2",
		PackedStringArray([ref]))
	var views := f.parcel_views(ids)
	assert_int(counting.peeks).override_failure_message("yalnız yeni kayıt okunmalı").is_equal(2)
	assert_int(views[0].reason_ids[views[0].reason_ids.size() - 1]).override_failure_message("yeni kayıt görünmüyor") \
		.is_equal(added)
	assert_int(counting.scans).override_failure_message("eski tam tarama yolu kullanıldı").is_equal(0)


func test_new_reason_appears_immediately_and_pruned_ones_disappear() -> void:
	var f := _facade()
	var state := f.game_state()
	var counting := CountingLog.new(4)  # küçük kapasite: budama
	state.reasons = counting
	var ids := f.parcel_ids().slice(0, 3)
	var ref := String(SimContract.parcel_ref(ids[0]))
	var first := state.reasons.record(1, &"actor.investor.1", &"d", [], 0, &"a", PackedStringArray([ref]))
	assert_array(_got(f, ids)[0]).is_equal([first])
	var second := state.reasons.record(2, &"actor.investor.1", &"d", [], 0, &"b", PackedStringArray([ref]))
	assert_array(_got(f, ids)[0]).override_failure_message("yeni gerekçe bayat önbellekte kaldı").is_equal([first, second])
	for k in 5:  # başka parsele 5 kayıt: kapasite 4 => ilk ikisi budanır
		state.reasons.record(3 + k, &"actor.investor.1", &"d", [], 0, &"x", PackedStringArray(["parcel.%d" % ids[1]]))
	var got := _got(f, ids)
	assert_array(got[0]).override_failure_message("budanmış gerekçe hâlâ görünüyor").is_empty()
	assert_array(got).is_equal(_expected(f, ids))
	assert_bool(state.reasons.peek(first).is_empty()).is_true()


func test_cache_follows_save_load() -> void:
	var f := _facade()
	f.submit_command(SimCommand.zoning_propose(f.parcel_ids(), &"zone.mixed"))
	f.advance(20)
	var ids := f.parcel_ids()
	var bytes := f.export_save()
	var before_load := _got(f, ids)  # önbelleği ısıt
	f.advance(25)
	assert_array(_got(f, ids)).is_equal(_expected(f, ids))
	var res := f.import_save(bytes)
	assert_bool(res.ok).override_failure_message("yükleme başarısız: %s" % res.message).is_true()
	assert_array(_got(f, ids)).override_failure_message("yükleme sonrası bayat önbellek").is_equal(before_load)
	assert_array(_got(f, ids)).is_equal(_expected(f, ids))


func test_cache_is_not_part_of_state_and_reads_leave_the_hash_untouched() -> void:
	var f := _facade()
	f.submit_command(SimCommand.zoning_propose(f.parcel_ids(), &"zone.mixed"))
	f.advance(15)
	var before := f.state_hash()
	for _i in 4:
		f.parcel_views(f.parcel_ids())
	assert_str(f.state_hash()).is_equal(before)
	# Okuma yapılan ve hiç yapılmayan iki aynı koşu aynı yere varır (önbellek durumu etkilemez).
	var g := _facade()
	g.submit_command(SimCommand.zoning_propose(g.parcel_ids(), &"zone.mixed"))
	g.advance(15)
	assert_str(g.state_hash()).is_equal(before)


## Önbellek birimi: rastgele ekleme/budama/sorgu dizileri (yinelenen konu, konusuz kayıt, küçük kapasite, farklı limit)
## her adımda `subject_index` ile BİT-BİT aynı olmalı.
func test_cache_unit_matches_subject_index_over_random_append_prune_query_sequences() -> void:
	var pool: Array[String] = []
	for k in 9:
		pool.append("parcel.%d" % (k + 1))
	for world_seed in [1, 2, 3]:
		for capacity in [3, 7, 40]:
			for limit in [1, 2, 5]:
				var rng := RandomNumberGenerator.new()
				rng.seed = world_seed * 1000 + capacity * 10 + limit
				var state := new_state()
				state.reasons = ReasonLog.new(capacity)
				var cache := ReasonSubjectCache.new()
				for step in 60:
					for _r in rng.randi_range(0, 3):  # 0 yeni kayıt da olur (değişmeyen günlük)
						var subjects := PackedStringArray()
						for _s in rng.randi_range(0, 3):  # yinelenen konu mümkün
							subjects.append(pool[rng.randi_range(0, pool.size() - 1)])
						state.reasons.record(step, &"actor.investor.1", &"d", [], 0, &"c", subjects)
					var wanted := {}
					for _w in rng.randi_range(1, 6):
						wanted[pool[rng.randi_range(0, pool.size() - 1)]] = true
					var want := state.reasons.subject_index(wanted, limit)
					var got := cache.lookup(state, wanted, limit)
					for ref in wanted:
						assert_array(Array(got[ref])).override_failure_message(
							"tohum %d kapasite %d limit %d adım %d %s" % [world_seed, capacity, limit, step, ref]) \
							.is_equal(Array(want.get(ref, PackedInt64Array())))


func test_cache_unit_drops_everything_when_the_log_instance_the_state_or_the_limit_changes() -> void:
	var state := new_state()
	state.reasons.record(1, &"actor.investor.1", &"d", [], 0, &"c", PackedStringArray(["parcel.1"]))
	var cache := ReasonSubjectCache.new()
	var wanted := {"parcel.1": true}
	assert_int(cache.lookup(state, wanted, 5)["parcel.1"].size()).is_equal(1)
	# aynı numaralı ama FARKLI içerikli yeni günlük (kayıt yükleme benzeri): eski sonuç sızmamalı
	var other := ReasonLog.new(1000)
	other.record(1, &"actor.investor.1", &"d", [], 0, &"c", PackedStringArray(["parcel.2"]))
	state.reasons = other
	assert_array(Array(cache.lookup(state, wanted, 5)["parcel.1"])).is_empty()
	var other_state := new_state()
	other_state.reasons.record(1, &"actor.investor.1", &"d", [], 0, &"c", PackedStringArray(["parcel.1"]))
	other_state.reasons.record(2, &"actor.investor.1", &"d", [], 0, &"c", PackedStringArray(["parcel.1"]))
	assert_int(cache.lookup(other_state, wanted, 5)["parcel.1"].size()).is_equal(2)
	assert_int(cache.lookup(other_state, wanted, 1)["parcel.1"].size()).override_failure_message("limit").is_equal(1)


## Packed diziler REFERANSLA geçer (Godot 4): çağıranın döndürülen diziyi değiştirmesi önbelleğe sızmamalı
## (`sim_facade_impl_test.test_returned_dtos_are_copies_ui_cannot_mutate_sim` bunu facade üzerinden de sınar).
func test_mutating_a_returned_array_does_not_leak_into_the_cache() -> void:
	var state := new_state()
	state.reasons.record(1, &"actor.investor.1", &"d", [], 0, &"c", PackedStringArray(["parcel.1"]))
	var cache := ReasonSubjectCache.new()
	var wanted := {"parcel.1": true}
	var first: PackedInt64Array = cache.lookup(state, wanted, 5)["parcel.1"]
	first.append(555)
	first[0] = 777
	assert_array(Array(cache.lookup(state, wanted, 5)["parcel.1"])).is_equal([1])
	state.reasons.record(2, &"actor.investor.1", &"d", [], 0, &"c", PackedStringArray(["parcel.1"]))
	assert_array(Array(cache.lookup(state, wanted, 5)["parcel.1"])).is_equal([1, 2])
	assert_array(Array(first)).override_failure_message("eski sonuç sonradan değişti").is_equal([777, 555])
