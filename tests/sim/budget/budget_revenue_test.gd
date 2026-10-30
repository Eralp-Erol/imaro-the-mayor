extends GdUnitTestSuite
## T-043C ölçüt 1-2 · Vergi geliri = Σ(tamamlanmış bina birimi x rent_per_unit_month) x tax_rate_pm / 1000, AY SONUNDA
## toplanır (ekonomi durumundan salt okunur). Bina yokken 0; bina tamamlanınca bir sonraki ay sonunda artar; kalem
## gerekçesi tamamlanan parsele bağlanır (SIM-12).

const B := preload("res://tests/sim/budget/budget_support.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const TAX := &"decision.budget.tax_revenue"
const DAYS := 30


func _build_one(h: EconomyHandle) -> int:
	var parcel := int(h.facade.parcel_ids(S.R1)[0])
	h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([parcel]), &"zone.mixed"))
	return parcel


## Ekonomi sonuç özetinde biten birim olana dek en çok `limit` gün ilerler; tamamlanma tick'i ya da -1.
func _advance_until_built(f: SimFacadeImpl, limit: int) -> int:
	for i in limit:
		f.advance(1)
		for r in f.economy_outcome().regions:
			if r.residential_units + r.commercial_units > 0:
				return f.current_tick()
	return -1


func test_without_buildings_revenue_is_zero_at_every_month_end() -> void:
	var h := B.fixture_handle()
	for month in 3:
		h.facade.advance(DAYS)
		assert_int(h.facade.snapshot().budget.revenue).is_equal(0)
	assert_int(h.facade.snapshot().budget.balance).is_equal(B.config().initial_balance)


func test_revenue_appears_only_at_the_month_end_after_completion_and_follows_the_formula() -> void:
	var cfg := B.config({"tax": {"tax_rate_pm": 250}})
	var h := B.fixture_handle({"tax": {"tax_rate_pm": 250}})
	var f := h.facade
	var parcel := _build_one(h)
	var completed := _advance_until_built(f, 300)
	assert_int(completed).override_failure_message("bina tamamlanmadı").is_greater(0)
	var month_end := ((completed + DAYS - 1) / DAYS) * DAYS
	if completed % DAYS != 0:  # ay içinde tamamlandı: ay sonuna dek gelir hâlâ 0
		assert_int(f.snapshot().budget.revenue).is_equal(0)
		f.advance(month_end - completed - 1)
		assert_int(f.snapshot().budget.revenue).is_equal(0)
		f.advance(1)
	var expected := B.expected_revenue(f, cfg)
	assert_int(expected).is_greater(0)
	var view := f.snapshot().budget
	assert_int(view.revenue).is_equal(expected)
	assert_int(view.balance).is_equal(cfg.initial_balance + expected)
	assert_int(view.period).is_equal(month_end / DAYS)
	# kalem gerekçesi tamamlanan parsele bağlı
	var linked := false
	for id in view.reason_ids:
		var r := f.reason(id)
		if r.decision_key == TAX and r.subjects.has(String(SimContract.parcel_ref(parcel))):
			linked = true
	assert_bool(linked).override_failure_message("vergi gerekçesi parsele bağlı değil").is_true()
	# bir sonraki ay sonunda aynı birimler aynı geliri verir; kasa iki kez tahsil edilmiş olur
	f.advance(DAYS)
	assert_int(f.snapshot().budget.revenue).is_equal(expected)
	assert_int(f.snapshot().budget.balance).is_equal(cfg.initial_balance + 2 * expected)


func test_revenue_is_constant_between_month_ends() -> void:
	var h := B.fixture_handle({"tax": {"tax_rate_pm": 250}})
	_build_one(h)
	assert_int(_advance_until_built(h.facade, 300)).is_greater(0)
	h.facade.advance(DAYS)  # en az bir ay sonu
	var at_end := h.facade.snapshot().budget.revenue
	for i in 10:
		h.facade.advance(1)
		if h.facade.current_tick() % DAYS != 0:
			assert_int(h.facade.snapshot().budget.revenue).is_equal(at_end)


func test_zero_tax_rate_collects_nothing_even_with_buildings() -> void:
	var h := B.fixture_handle({"tax": {"tax_rate_pm": 0}})
	_build_one(h)
	assert_int(_advance_until_built(h.facade, 300)).is_greater(0)
	h.facade.advance(2 * DAYS)
	assert_int(h.facade.snapshot().budget.revenue).is_equal(0)
	assert_int(h.facade.snapshot().budget.balance).is_equal(B.config().initial_balance)


func test_revenue_reads_the_economy_and_never_changes_what_investors_decide() -> void:
	# CAN-03: bütçe salt okur; aynı tohum + komutla bütçeli ve bütçesiz koşunun parsel kararları AYNI.
	var with_budget := B.fixture_handle()
	var without := B.fixture_handle({}, false)
	for h: EconomyHandle in [with_budget, without]:
		_build_one(h)
		h.facade.advance(150)
	assert_array(_decisions(with_budget.facade)).is_equal(_decisions(without.facade))
	assert_int(_decisions(without.facade).size()).is_greater(0)


func _decisions(f: SimFacadeImpl) -> Array:
	var out: Array = []
	for v in f.parcel_views(f.parcel_ids()):
		out.append([v.id, v.development, v.use, v.units, v.decision, v.decision_code])
	return out
