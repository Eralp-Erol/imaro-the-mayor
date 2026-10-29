extends GdUnitTestSuite
## Sahip geri bildirimi (2026-10-29) · eğim tabanı sokak ve komşuluk ölçeğinde neredeyse yatay (ADR-0007 Ek b):
## taban 3 derece, 600 m'ye kadar düz, K1 girişine (1500 m) log-doğrusal yükselir, komşu uzaklıklarda sıçramaz.


func test_the_pitch_floor_is_nearly_horizontal_through_the_street_and_lower_neighborhood_then_rises_smoothly() -> void:
	var env := CameraEnvelope.load_default()
	# Sahip geri bildirimi (2026-10-29): sokak ve komşuluk ölçeğinde neredeyse yatay bakılabilmeli.
	for d in [50.0, 120.0, 300.0, 600.0]:
		assert_float(env.pitch_min_deg(d)).override_failure_message("d=%s" % d).is_less_equal(3.5)
	assert_float(env.pitch_min_deg(env.d_min_m)).is_greater(0.0)  # ufuk görünür ama tam yatay (0) değil
	# Uzaklaştıkça yükselir ve K1 girişinde FOV/2 + epsilon'u karşılar (sıçrama yok).
	assert_float(env.pitch_min_deg(1000.0)).is_greater(env.pitch_min_deg(600.0))
	assert_float(env.pitch_min_deg(env.k1_min_distance_m)).is_greater_equal(
			CameraEnvelope.DEFAULT_FOV_DEG * 0.5 + env.k1_epsilon_deg)


func test_the_pitch_floor_has_no_jump_between_neighboring_distances_anywhere_including_the_k1_entry() -> void:
	var env := CameraEnvelope.load_default()
	var max_step := 0.0
	var d := env.d_min_m
	while d * 1.01 <= env.d_max_m:
		max_step = maxf(max_step, absf(env.pitch_min_deg(d * 1.01) - env.pitch_min_deg(d)))
		d *= 1.01
	# En dik parça (~24 derece / ln birim) 1% uzaklık adımında ~0,25 derece verir; sıçrama bunun çok üstüdür.
	assert_float(max_step).override_failure_message("komşu uzaklıklarda eğim tabanı sıçrıyor").is_less(0.3)
	var k1 := env.k1_min_distance_m
	assert_float(absf(env.pitch_min_deg(k1 * 1.001) - env.pitch_min_deg(k1 * 0.999))).is_less(0.05)
	# Duyarlılık: sıçramalı bir eğri (aynı ölçüt) yakalanır.
	var jump: Array[Vector2] = [Vector2(50.0, 3.0), Vector2(1499.0, 3.0), Vector2(1500.0, 25.0), Vector2(18000.0, 40.0)]
	var jumpy := CameraEnvelope.new()
	jumpy.pitch_curve = jump
	assert_float(absf(jumpy.pitch_min_deg(1500.0 * 1.001) - jumpy.pitch_min_deg(1500.0 * 0.999))).is_greater(0.5)
