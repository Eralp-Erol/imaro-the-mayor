extends GdUnitTestSuite
## T-042b · İmleç önizlemesi seyreltmesi: kamulaştırma teklifi hesabı pahalıdır (~8-10 ms); imleç önizleme aralığı son
## `hover_at` süresinin katı kadar uzar (görev döngüsü sınırlı), ucuz denetimde taban aralıkta kalır. İmleç hareketleri
## aralık içinde birleştirilir (sim'e her kare sorulmaz; son konum `process`te uygulanır).


func test_cheap_previews_keep_the_base_interval() -> void:
	var ctrl := RoadDrawController.new()
	assert_int(ctrl.hover_interval_msec()).is_equal(RoadDrawController.HOVER_INTERVAL_MSEC)
	ctrl._hover_cost_msec = 1.0
	assert_int(ctrl.hover_interval_msec()).is_equal(RoadDrawController.HOVER_INTERVAL_MSEC)


func test_expensive_previews_stretch_the_interval_so_the_duty_cycle_stays_bounded() -> void:
	var ctrl := RoadDrawController.new()
	for cost in [10.0, 20.0, 40.0]:
		ctrl._hover_cost_msec = cost
		var interval := ctrl.hover_interval_msec()
		assert_int(interval).is_greater_equal(RoadDrawController.HOVER_INTERVAL_MSEC)
		assert_float(cost / float(interval)).is_less_equal(0.15)
	ctrl._hover_cost_msec = 10.0
	assert_int(ctrl.hover_interval_msec()).is_equal(70)
