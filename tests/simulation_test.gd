extends SceneTree

var failures: Array[String] = []
var checks: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func days(sim: CitySimulation, count: int) -> void:
	for i in range(count): sim.tick()

func run() -> void:
	var untouched := CitySimulation.new()
	days(untouched, 30)
	check(untouched.developments.is_empty(), "Kısıtlı imar kendiliğinden özel bina üretmez")
	check(untouched.parcels.size() == 32, "32 kararlı parsel kimliği")
	var sim := CitySimulation.new()
	var initial := sim.totals()
	var cash_before := sim.municipality.cash
	sim.propose(23, "mixed")
	check(sim.parcels[23].use == "empty" and sim.developments.is_empty(), "Teklif özel bina spawn etmez")
	check(sim.municipality.cash == cash_before - 1000, "Teklif gideri gerçek belediye kasasından düşer")
	days(sim, 2)
	check(sim.parcels[23].zone == "mixed" and sim.parcels[23].use == "empty", "Meclis onayı ile yatırım kararı ayrı günlerde")
	sim.tick()
	check(sim.parcels[23].use == "construction", "Uygun getiri gerçek yatırım başlatır")
	check(sim.developments.size() == 1, "Aynı parsele ikinci yatırımcı proje başlatamaz")
	check(sim.investors[0].capital < 1800000, "Yapım gideri özel yatırımcının sermayesinden çıkar")
	check(sim.totals().homes == initial.homes, "Şantiye tamamlanmadan konut kapasitesi artmaz")
	days(sim, 17)
	check(sim.parcels[23].use == "construction", "18 günlük inşaat erken tamamlanmaz")
	sim.tick()
	check(sim.parcels[23].use == "apartment" and sim.totals().homes > initial.homes, "Tamamlanan proje kapasiteyi artırır")
	check(sim.totals().shops > initial.shops and sim.parcels[23].occupied > 0, "Karma kullanım işyeri ve gerçek doluluk getirir")
	check(sim.forecast_budget().income > untouched.forecast_budget().income, "Yeni kullanım vergi gelirini artırır")
	check(sim.groups[0].reason.contains("gürültüsü sona erdi") and sim.groups[1].reason.contains("rekabet"), "Sakin ve esnafın nedensel tepkileri farklıdır")
	var balance := 320000
	for entry in sim.municipality.ledger: balance += entry.amount
	check(sim.municipality.cash == balance, "Bütçe işlemlerinin toplamı kasa ile tutarlı")
	check(sim.propose(23, "housing").contains("yalnızca"), "Tamamlanmış özel yapı belediye tarafından değiştirilemez")
	var negative := CitySimulation.new()
	negative.propose(19, "housing")
	days(negative, 30)
	check(negative.parcels[19].zone == "housing" and negative.parcels[19].use == "empty", "İmar onaylı pahalı parsel yatırım almayabilir")
	check(negative.parcels[19].last_evaluation.contains("eşik"), "Yatırım reddinin ekonomik gerekçesi görünür")
	var rejected := CitySimulation.new()
	rejected.propose(23, "commerce")
	days(rejected, 3)
	check(rejected.parcels[23].zone == "restricted" and rejected.events.back().title.contains("reddetti"), "Meclis reddi imarı gerçekten engeller")
	var merchant := CitySimulation.new()
	merchant.toggle_policy("mobility")
	merchant.propose(23, "commerce")
	days(merchant, 3)
	check(merchant.developments.size() == 1 and merchant.developments[0].investor_id == 1, "Ulaşım politikası meclisi ve ticari profili etkiler")
	check(merchant.developments[0].homes == 0, "Ticari geliştiricinin çıktısı konut geliştiricisinden farklı")
	var green := CitySimulation.new()
	green.propose(23, "green")
	days(green, 30)
	check(green.parcels[23].use == "empty" and green.parcels[23].owner_id == 23, "Yeşil imar özel arsayı bedelsiz kamu parkına çevirmez")
	var a := CitySimulation.new(88)
	var b := CitySimulation.new(88)
	a.propose(23, "mixed")
	b.propose(23, "mixed")
	var clock_a := GameClock.new()
	var clock_b := GameClock.new()
	clock_a.speed = 1
	clock_b.speed = 1
	for i in range(1800): clock_a.advance(1.0 / 30.0, a)
	for i in range(60):
		for delta in [0.017, 0.083, 0.4, 0.5]: clock_b.advance(delta, b)
	check(a.day == 30 and a.snapshot() == b.snapshot(), "30 FPS ve düzensiz kare süreleri aynı simülasyonu üretir")
	clock_a.speed = 0
	clock_a.advance(100, a)
	check(a.day == 30, "Duraklatma simülasyon zamanını dondurur")
	var saved := CitySimulation.new()
	saved.propose(23, "mixed")
	days(saved, 7)
	check(CitySave.save_game(saved, "user://test-ilgin.save") == OK, "Kayıt yazılır")
	var restored := CitySave.load_game("user://test-ilgin.save")
	check(restored != null and restored.snapshot() == saved.snapshot(), "Şantiye sırasında kayıt yükleme birebir durumu korur")
	if restored != null:
		days(saved, 25)
		days(restored, 25)
		check(saved.snapshot() == restored.snapshot(), "Yüklenen oyunun gelecekteki kararları da deterministik")
	check(CitySimulation.from_snapshot({"version": 99}) == null, "Geçersiz kayıt sürümü reddedilir")
	DirAccess.remove_absolute("user://test-ilgin.save")
	DirAccess.make_dir_recursive_absolute("res://artifacts/tests")
	var file := FileAccess.open("res://artifacts/tests/simulation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "engine": Engine.get_version_info().string}, "\t"))
	file.close()
	print("SIMULATION: %d/%d passed" % [checks.size() - failures.size(), checks.size()])
	quit(0 if failures.is_empty() else 1)
