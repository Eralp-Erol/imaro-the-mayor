class_name CitySimulation
extends RefCounted

signal changed
signal parcel_changed(id: int)

var seed_value: int = 1467
var day: int = 0
var parcels: Array[CityModel.Parcel] = []
var owners: Array[CityModel.Owner] = []
var investors: Array[CityModel.Investor] = []
var developments: Array[CityModel.Development] = []
var municipality := CityModel.Municipality.new()
var groups: Array[CityModel.CitizenGroup] = []
var proposals: Array[Dictionary] = []
var events: Array[Dictionary] = []

func _init(initial_seed: int = 1467) -> void:
	seed_value = initial_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for spec in DistrictLayout.parcels():
		var p := CityModel.Parcel.new(spec)
		p.access = 0.78 + rng.randf() * 0.16
		p.land_value = 65000 + rng.randi_range(0, 20) * 1000
		var public_owner: bool = p.use in ["park", "service"]
		owners.append(CityModel.Owner.new(p.id, "Ilgın Belediyesi" if public_owner else ["Yalçın Ailesi", "Deniz Hanım", "Ege Mülk", "Kıyı Mirasçıları"][p.id % 4], public_owner))
		if p.use == "apartment":
			p.zone = "mixed" if spec.shop != "" else "housing"
			p.homes = spec.floors * 4
			p.occupied = int(p.homes * 0.88)
			p.shops = 1 if spec.shop != "" else 0
		elif public_owner:
			p.zone = "green"
		if p.id == 19:
			p.access = 0.28
			p.land_value = 350000
			p.cleanup = 90000
			p.last_evaluation = "Eski atölye: düşük erişim ve zemin temizliği maliyeti."
		parcels.append(p)
	investors.append(CityModel.Investor.new(0, "Kıyı Konut", "housing", 0.16))
	investors.append(CityModel.Investor.new(1, "Çarşı Girişim", "commerce", 0.23))
	groups.append(CityModel.CitizenGroup.new("Mahalle sakinleri", 61, "Yeni konuta ihtiyaç var; sokakların yükü de gözetilmeli."))
	groups.append(CityModel.CitizenGroup.new("Yerel esnaf", 58, "Mahalleye yeni müşteriler gelmesini bekliyoruz."))
	groups.append(CityModel.CitizenGroup.new("Yatırımcılar", 52, "Boş arsaların imar hakkı yatırım için yetersiz."))
	log_event("Göreve başladınız", "24 numaralı özel parsel için bir imar teklifi hazırlayın.", 23)

func log_event(title: String, detail: String, parcel_id: int = -1) -> void:
	events.append({"day": day, "title": title, "detail": detail, "parcel": parcel_id})
	if events.size() > 100: events.pop_front()

func totals() -> Dictionary:
	var homes := 0
	var shops := 0
	var occupied := 0
	for p in parcels:
		homes += p.homes
		shops += p.shops
		occupied += p.occupied
	return {"homes": homes, "shops": shops, "occupied": occupied, "population": occupied * 2}

func housing_demand() -> float:
	return clampf(0.98 - (totals().homes - 436) * 0.004, 0.3, 1.0)

func commercial_demand() -> float:
	return clampf(0.98 - (totals().shops - 3) * 0.045, 0.3, 1.0)

func effective_access(p: CityModel.Parcel) -> float:
	return minf(1.0, p.access + (0.12 if municipality.mobility else 0.0))

func forecast_budget() -> Dictionary:
	var total := totals()
	return {"income": 1400 + total.occupied * 6 + total.shops * 90,
		"expense": 2100 + total.population + (450 if municipality.mobility else 0) + (250 if municipality.care else 0)}

func pending_for(id: int) -> bool:
	for proposal in proposals:
		if proposal.parcel == id: return true
	return false

func council_vote(id: int, zone: String) -> Dictionary:
	var resident_votes := 0
	var business_votes := 0
	var public_votes := 0
	var resident_reason := "Ticaret yoğunluğu sokakları zorlayacak."
	if zone == "housing":
		resident_votes = 3
		business_votes = 1
		resident_reason = "Yeni konut arzını destekliyoruz."
	elif zone == "mixed":
		resident_votes = 2
		business_votes = 2
		resident_reason = "Konut ve esnaf birlikte gelişsin; yoğunluk itirazımız sürüyor."
	elif zone == "commerce":
		business_votes = 2
		resident_votes = 2 if municipality.mobility else 0
		if municipality.mobility: resident_reason = "Ulaşım desteği yeni işyerlerinin yükünü hafifletiyor."
	elif zone == "green":
		resident_votes = 3
		public_votes = 2
		resident_reason = "Açık alanı koruyalım; özel arsa kamulaştırılmadan park olmaz."
	if municipality.care and zone in ["mixed", "housing"]: public_votes = 1
	return {"yes": resident_votes + business_votes + public_votes, "total": 7,
		"rows": ["Sakinler: %d/3 · %s" % [resident_votes, resident_reason],
		"Esnaf: %d/2 · %s" % [business_votes, "Yeni müşteri ve işyeri beklentisi." if business_votes > 0 else "İşyeri alanı oluşmuyor."],
		"Kamusal alan: %d/2 · %s" % [public_votes, "Bakım bütçesi ve açık alan korunuyor." if public_votes > 0 else "Yoğunluğun hizmet yüküne itiraz ediyoruz."]],
		"parcel": id}

func propose(id: int, zone: String) -> String:
	if id < 0 or id >= parcels.size() or not CityModel.ZONES.has(zone): return "Geçersiz imar teklifi."
	var p := parcels[id]
	if p.owner_id < 100 and owners[p.owner_id].public_owner: return "Bu kamusal parselin mevcut hizmeti korunuyor."
	if p.use != "empty": return "İlk uygulamada yalnızca boş özel parsellerde imar değişir."
	if zone == "restricted" or zone == p.zone: return "Farklı bir imar türü seçin."
	if pending_for(id): return "Bu parselin teklifi zaten meclis gündeminde."
	if municipality.cash < 1000: return "Teklif hazırlığı için 1.000 ₺ gerekiyor."
	municipality.transact(day, -1000, "İmar teklifi hazırlığı · Parsel %02d" % (id + 1))
	proposals.append({"parcel": id, "zone": zone, "due": day + 2})
	log_event("Teklif meclise sunuldu", "%s · karar 2 gün sonra. Hazırlık: 1.000 ₺." % CityModel.ZONES[zone], id)
	changed.emit()
	return "Teklif gündemde. Zamanı ilerleterek meclis kararını izleyin."

func toggle_policy(policy: String) -> String:
	if policy not in ["mobility", "care"]: return "Bilinmeyen politika."
	var current: bool = municipality.get(policy)
	var cost := 30000 if policy == "mobility" else 18000
	if not current and municipality.cash < cost: return "Bu program için bütçe yetersiz."
	municipality.set(policy, not current)
	if not current: municipality.transact(day, -cost, "Ulaşım desteği kurulumu" if policy == "mobility" else "Mahalle bakım programı")
	groups[0].react(4 if not current else -4, "Ulaşım/bakım programı açıldı." if not current else "Belediye hizmet programı durduruldu.")
	log_event("Belediye politikası değişti", ("Ulaşım desteği" if policy == "mobility" else "Mahalle bakımı") + (" başladı." if not current else " durdu."))
	changed.emit()
	return "Politika güncellendi; etkisi ve günlük gideri bütçeye yansıdı."

func evaluate(p: CityModel.Parcel, investor: CityModel.Investor, zone_override: String = "") -> Dictionary:
	var zone := p.zone if zone_override == "" else zone_override
	var result := {"investor": investor.title, "allowed": false, "reason": "İmar hakkı bu profile uygun değil.",
		"cost": 0, "land": p.land_value, "build": 0, "cleanup": p.cleanup, "revenue": 0, "roi": 0.0, "homes": 0, "shops": 0}
	if p.use != "empty" or owners[p.owner_id].public_owner: return result
	if investor.profile == "housing" and zone not in ["housing", "mixed"]: return result
	if investor.profile == "commerce" and zone not in ["commerce", "mixed"]: return result
	var floors: int = p.geometry.floors
	var homes := floors * 4 if zone == "housing" else (floors * 3 if zone == "mixed" else 0)
	var shops := 2 if zone == "mixed" else (floors * 2 if zone == "commerce" else 0)
	var build := floors * 36000 + shops * 8000
	var cost := build + p.land_value + p.cleanup
	var demand := housing_demand() if investor.profile == "housing" else commercial_demand()
	var revenue := int((homes * 20500 + shops * 54000) * demand * (0.5 + effective_access(p) * 0.5))
	# Commercial developers discount housing returns; they are not identical profiles.
	if investor.profile == "commerce" and zone == "mixed": revenue = int(revenue * 0.88)
	var roi := float(revenue - cost) / cost
	result.merge({"cost": cost, "build": build, "revenue": revenue, "roi": roi, "homes": homes, "shops": shops}, true)
	if cost > investor.capital: result.reason = "Sermaye yetersiz."
	elif roi < investor.threshold: result.reason = "Beklenen getiri %%%d; eşik %%%d. Arazi, yapım ve erişim karşılamıyor." % [roundi(roi * 100), roundi(investor.threshold * 100)]
	else:
		result.allowed = true
		result.reason = "Beklenen getiri %%%d, eşik %%%d üstünde; finansman uygun." % [roundi(roi * 100), roundi(investor.threshold * 100)]
	return result

func tick() -> void:
	day += 1
	for proposal in proposals.duplicate():
		if proposal.due > day: continue
		var vote := council_vote(proposal.parcel, proposal.zone)
		if vote.yes >= 4:
			parcels[proposal.parcel].zone = proposal.zone
			groups[0].react(-2 if proposal.zone == "mixed" else 2, "İmar kararı yeni kapasite getiriyor; yoğunluk yakından izleniyor.")
			groups[1].react(4 if proposal.zone in ["mixed", "commerce"] else 1, "İmar kararı yerel müşteri ve işyeri beklentisini değiştirdi.")
			groups[2].react(5 if proposal.zone != "green" else -4, "Yeni imar hakkına göre fizibilite yeniden hesaplanacak.")
			log_event("Meclis kabul etti · %d/7" % vote.yes, "%s yürürlükte. Bina kararı yatırımcıya ait." % CityModel.ZONES[proposal.zone], proposal.parcel)
		else:
			log_event("Meclis reddetti · %d/7" % vote.yes, "Yoğunluk ve hizmet yükü nedeniyle imar değişmedi.", proposal.parcel)
		proposals.erase(proposal)
	# An accepted decision does not directly create a building: market checks run separately.
	if day % 3 == 0:
		market_step()
	for development in developments:
		if development.completed: continue
		var p := parcels[development.parcel_id]
		if day - development.started_day >= development.duration:
			development.completed = true
			p.use = "apartment"
			p.homes = development.homes
			p.shops = development.shops
			p.occupied = int(p.homes * 0.9)
			investors[development.investor_id].capital += development.revenue
			municipality.transact(day, 6000, "İskân harcı · Parsel %02d" % (p.id + 1))
			groups[0].react(3, "%d konut tamamlandı; şantiye gürültüsü sona erdi." % p.homes)
			groups[1].react(-2 if p.shops > 0 else 3, "Yeni işyerleri müşteri getirirken mevcut esnafa rekabet de getiriyor." if p.shops > 0 else "Yeni komşular mahalle esnafının müşterisi olacak.")
			groups[2].react(4, "Tamamlanan proje gelir üretti; sermaye yeni fırsatlara dönebilir.")
			log_event("Yapı kullanıma açıldı", "%d konut, %d işyeri. Doluluk ve günlük vergi hesabı güncellendi." % [p.homes, p.shops], p.id)
		parcel_changed.emit(p.id)
	var flow := forecast_budget()
	municipality.income_today = flow.income
	municipality.expense_today = flow.expense
	municipality.transact(day, flow.income, "Günlük pay ve emlak/işyeri geliri")
	municipality.transact(day, -flow.expense, "Günlük belediye hizmet gideri")
	changed.emit()

func market_step() -> void:
	for investor in investors:
		var best: CityModel.Parcel = null
		var best_result: Dictionary = {}
		for p in parcels:
			if p.use != "empty" or pending_for(p.id): continue
			var result := evaluate(p, investor)
			if p.zone in ["restricted", "green"]: continue
			if result.cost > 0:
				p.last_evaluation = investor.title + ": " + result.reason
			if result.allowed and (best == null or result.roi > best_result.roi):
				best = p
				best_result = result
		if best != null:
			var development := CityModel.Development.new()
			development.parcel_id = best.id
			development.investor_id = investor.id
			development.started_day = day
			development.cost = best_result.cost
			development.revenue = best_result.revenue
			development.homes = best_result.homes
			development.shops = best_result.shops
			investor.capital -= development.cost
			developments.append(development)
			best.use = "construction"
			best.owner_id = 100 + investor.id
			groups[0].react(-4, "Şantiye başladı: kısa vadede gürültü ve sokak yükü arttı.")
			municipality.transact(day, 4000, "Yapı ruhsatı harcı · Parsel %02d" % (best.id + 1))
			log_event("Özel yatırım başladı", "%s kendi sermayesiyle %d ₺ ayırdı. Süre: %d gün." % [investor.title, development.cost, development.duration], best.id)
			parcel_changed.emit(best.id)

func owner_title(p: CityModel.Parcel) -> String:
	return investors[p.owner_id - 100].title if p.owner_id >= 100 else owners[p.owner_id].title

func visual_data(p: CityModel.Parcel) -> Dictionary:
	var spec := p.geometry.duplicate(true)
	spec.use = p.use
	if p.shops > 0 and spec.shop == "": spec.shop = "DÜKKÂN"
	for development in developments:
		if development.parcel_id == p.id:
			spec.progress = clampf(float(day - development.started_day) / development.duration, 0, 1)
	return spec

func snapshot() -> Dictionary:
	return {"version": 1, "seed": seed_value, "day": day,
		"parcels": parcels.map(func(p: CityModel.Parcel) -> Dictionary: return p.to_data()),
		"investors": investors.map(func(i: CityModel.Investor) -> Dictionary: return i.to_data()),
		"developments": developments.map(func(d: CityModel.Development) -> Dictionary: return d.to_data()),
		"groups": groups.map(func(g: CityModel.CitizenGroup) -> Dictionary: return g.to_data()),
		"municipality": {"cash": municipality.cash, "mobility": municipality.mobility, "care": municipality.care,
			"income_today": municipality.income_today, "expense_today": municipality.expense_today, "ledger": municipality.ledger.duplicate(true)},
		"proposals": proposals.duplicate(true), "events": events.duplicate(true)}

static func from_snapshot(data: Dictionary) -> CitySimulation:
	if data.get("version") != 1 or not data.get("seed") is int or not data.get("day") is int: return null
	var restored := CitySimulation.new(data.seed)
	# Saved Variants preserve integer types; object deserialization is never enabled.
	for key in ["parcels", "investors", "developments", "groups", "proposals", "events"]:
		if not data.get(key) is Array: return null
	if data.parcels.size() != 32 or data.investors.size() != 2 or data.groups.size() != 3: return null
	if not data.get("municipality") is Dictionary or data.day < 0: return null
	for i in range(32):
		var p: Variant = data.parcels[i]
		if not p is Dictionary or p.get("id") != i: return null
		for key in restored.parcels[i].to_data():
			if not p.has(key) or typeof(p[key]) != typeof(restored.parcels[i].to_data()[key]): return null
		if not CityModel.ZONES.has(p.zone) or p.use not in ["empty", "apartment", "park", "service", "construction"]: return null
		if not (p.owner in range(32) or p.owner in [100, 101]): return null
	for d: Variant in data.developments:
		if not d is Dictionary: return null
		for key in CityModel.Development.new().to_data():
			if not d.has(key) or typeof(d[key]) != typeof(CityModel.Development.new().to_data()[key]): return null
		if d.parcel_id not in range(32) or d.investor_id not in [0, 1] or d.duration <= 0: return null
	for p: Variant in data.proposals:
		if not p is Dictionary or p.get("parcel", -1) not in range(32) or not CityModel.ZONES.has(p.get("zone", "")) or not p.get("due") is int: return null
	for event: Variant in data.events:
		if not event is Dictionary or not event.get("day") is int or not event.get("title") is String or not event.get("detail") is String or not event.get("parcel") is int: return null
	for i in range(2):
		if not data.investors[i] is Dictionary or data.investors[i].get("id") != i or not data.investors[i].get("capital") is int: return null
	for i in range(3):
		if not data.groups[i] is Dictionary or not data.groups[i].get("support") is int or not data.groups[i].get("reason") is String: return null
	var fresh_municipality: Dictionary = restored.snapshot().municipality
	for key in fresh_municipality:
		if not data.municipality.has(key) or typeof(data.municipality[key]) != typeof(fresh_municipality[key]): return null
	for entry: Variant in data.municipality.ledger:
		if not entry is Dictionary or not entry.get("day") is int or not entry.get("amount") is int or not entry.get("reason") is String: return null
	restored.day = data.day
	for i in range(32):
		var p := restored.parcels[i]
		var source: Dictionary = data.parcels[i]
		p.owner_id = source.owner
		p.zone = source.zone
		p.use = source.use
		p.land_value = source.land
		p.cleanup = source.cleanup
		p.access = source.access
		p.homes = source.homes
		p.shops = source.shops
		p.occupied = source.occupied
		p.last_evaluation = source.evaluation
	for i in range(2): restored.investors[i].capital = data.investors[i].capital
	for i in range(3):
		restored.groups[i].support = data.groups[i].support
		restored.groups[i].reason = data.groups[i].reason
	for source: Dictionary in data.developments:
		var development := CityModel.Development.new()
		for key in development.to_data(): development.set(key, source[key])
		restored.developments.append(development)
	for key in fresh_municipality: restored.municipality.set(key, data.municipality[key])
	restored.proposals.assign(data.proposals)
	restored.events.assign(data.events)
	return restored
