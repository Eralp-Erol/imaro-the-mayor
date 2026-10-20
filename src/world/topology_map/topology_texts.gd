class_name TopologyTexts
extends RefCounted
## Topoloji haritasının METİNLERİ (T-028): damga, kanon durum tablosu (KANONİK/OY/ÇM/ÇIKARIM/AÇIK/TEKNİK) ve kullanıcıya
## sunulan karar soruları. Hepsi tek yerde; sayılar modelden (veriden) gelir. Soruların CEVABI yok: yalnız seçenekler
## ve "şu an veri ne diyor" sunulur (karar kullanıcıdadır; kayıt koordinatörde, production/QUESTIONS.md Q-015).
## Yer adı yoktur (CAN-01): yalnız D-kodları, D2 "Orven" (veriden), ada kimlikleri.

const STATUS_CANON := "KANONİK"
const STATUS_OY := "OY"
const STATUS_CM := "ÇM"
const STATUS_INFERRED := "ÇIKARIM"
const STATUS_OPEN := "AÇIK"
const STATUS_TECH := "TEKNİK"
## Geçerli durum sözcükleri ("ÇM/ÇIKARIM" gibi bileşikler "/" ile ayrılır).
const STATUSES: Array[String] = [STATUS_CANON, STATUS_OY, STATUS_CM, STATUS_INFERRED, STATUS_OPEN, STATUS_TECH]
const TITLE := "Ismeral — etiketli topoloji haritası (T-028)"
const TRACE_NOTE := "Ayrı harita kaynağı değil: WorldData + WorldNetwork + T0Settlement görünümü (WLD-01, TEK-03)."
const NORTH_NOTE := "kuzey = −z (teknik eksen sözleşmesi, kanon değil)"
const BOUNDARY_NOTE := "Bölge sınırları yaklaşık/AÇIK (çapa + eliptik kapsam; resmî ilçe değil)"


## Türkçe ondalık virgüllü sayı.
static func num(value: float, digits: int = 1) -> String:
	return String.num(snappedf(value, pow(10.0, -digits)), digits).replace(".", ",")


## Yüzde (0..1 -> "37").
static func pct(share: float) -> String:
	return str(int(round(share * 100.0)))


## Kanon durum tablosu: [{"status", "item", "detail", "req"}] — sayılar modelden.
static func provenance(m: TopologyModel) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var core_share := core_building_share(m)
	rows.append(_row(STATUS_CANON, "Tek fiziksel dünya; ölçeğe göre ayrı kıyı/harita yok",
			"Bu harita da ayrı kaynak değil: aynı WorldData/WorldNetwork/T0Settlement verisinin görünümü.",
			"WLD-01, TEK-03"))
	rows.append(_row(STATUS_OY, "Batıda körfez/kıyı, doğuda iç ova, güneydoğuda yamaç",
			"Yön bağlayıcı; körfezin biçimi, ağız genişliği ve ova/yamaç oranı ÇM (aşağıdaki sorular).", "WLD-02"))
	rows.append(_row(STATUS_OY, "Altı çalışma bölgesi D1–D6 (haritada %d)" % m.regions.size(),
			"Kodlar resmî ilçe değil. Kapsamlar çapa + eliptik yarıçap; sınırlar, boyutlar, statü AÇIK.", "WLD-02"))
	rows.append(_row(STATUS_CANON, "Yalnız D2 'Orven' adlı; başka yer/ilçe adı yok",
			"Diğer bölgeler D-kodu, adalar I-kimliği; sokak/mahalle adı yok (AÇIK).", "CAN-01"))
	rows.append(_row("%s/%s" % [STATUS_INFERRED, STATUS_CM], "D1 körfezin kuzey burnunda, D6 güney kıyıda",
			"Kaynak görsel D1'i güney kıyı gibi de okutabilir; yön çalışma verisinde kuzey seçildi (coast.json notu).",
			"WLD-02, WLD-05"))
	rows.append(_row(STATUS_OY, "D1 ve D6 karşı kıyıda, su ile ayrık; feribot/ulaşım bağı",
			"Haritada en kısa su aralığı ≈ %s km; sayı ÇM. Körfezi yok eden doldurma sabit karar değil." % _gap_km(m),
			"WLD-05"))
	rows.append(_row(STATUS_CANON, "T0 limanı + ilk sanayi ana karada, D4'ün batısında",
			"Haritada limana kıyıdan ≈ %s m; kesin konum ve kıyıya uzaklık ÇM, kanon değil." % _port_shore(m),
			"WLD-03"))
	rows.append(_row(STATUS_CANON, "T0 adalarında büyük liman/ana sanayi yok",
			"Haritada ada kaynaklı liman/sanayi etiketi: %d, ana kara dışı saha: %d." % [
			m.islands_with_forbidden_tags.size(), m.sites_off_mainland.size()], "WLD-03"))
	rows.append(_row(STATUS_CM, "Ada sayısı, şekli ve konumu (haritada %d ada)" % m.islands.size(),
			"Kaynak görselde yaklaşık 5–7 ada okunuyor; sayı/poligon kilitli değil (coast.json).", "WLD-03"))
	rows.append(_row("%s/%s" % [STATUS_CM, STATUS_INFERRED], "Kıyı çizgisi (ana kara, körfez, adalar)",
			"F02: ana karanın tam kıyı çizgisi kesinleştirilmemiştir; çizgi kontrol noktalarından türeyen çalışma verisi.",
			"WLD-02, WLD-09"))
	rows.append(_row(STATUS_OY, "T0: D1+D6 kompakt çekirdek, D2–D5 daha küçük gerçek merkezler",
			"Haritada yapıların %%%s'i D1+D6'da (toplam %d yapı); oranlar ÇM." % [pct(core_share), m.building_total]
			if m.building_total > 0 else "T0 yerleşimi yüklenmedi (--no-settlement): yoğunluk gösterilmiyor.",
			"WLD-04, WLD-06"))
	rows.append(_row("%s/%s" % [STATUS_CM, STATUS_TECH], "Yükselti kuşakları (<%d / %d–%d / ≥%d m)" % [
			int(TopologyModel.PLAIN_MAX_M), int(TopologyModel.PLAIN_MAX_M), int(TopologyModel.SLOPE_MAX_M),
			int(TopologyModel.SLOPE_MAX_M)], "Eşikler yalnız gösterim içindir (kanon değil).", "WLD-02"))
	rows.append(_row(STATUS_CM, "Yol / ray / feribot omurgası (haritada %d kenar)" % backbone_edge_count(m),
			"Ağ T-011 üreteç kurallarından; güzergâhlar kanon değil.", "WLD-05"))
	rows.append(_row(STATUS_TECH, "Ölçek ≈ %d × %d km, kuzey = −z" % [int(m.bounds.size.x / 1000.0),
			int(m.bounds.size.y / 1000.0)], "Metro ölçeği ve eksen TEKNİK/ÇM; Anderva–Ismeral ölçek oranı AÇIK.",
			"TEK-03"))
	return rows


## Kullanıcıya sunulan karar soruları (4–6): [{"id", "title", "current", "options": Array[String], "affects"}].
static func questions(m: TopologyModel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mouth_km := float((m.bay.get("mouth_bbox", Rect2()) as Rect2).size.y) / 1000.0
	out.append(_question("K1", "Körfez biçimi",
			"Batıya açılan geniş ağız, doğuya daralan iç körfez: iç su ≈ %s km², ağız ≈ %s km." % [
			num(float(m.land_stats.get("gulf_km2", 0.0)), 0), num(mouth_km, 1)],
			["A) Bu biçim kalsın", "B) Daha dar ağızlı, daha kapalı iç körfez", "C) Daha açık, geniş ağızlı körfez",
			"D) Başka (kullanıcı tarif eder)"], "kıyı kontrol noktaları, iç körfez derinliği"))
	out.append(_question("K2", "Ada dizisi",
			"%d ada (%s), toplam ≈ %s km²; kaynak görselde 5–7 ada okunuyor." % [m.islands.size(),
			_island_ids(m), num(_island_area(m), 1)],
			["A) Mevcut dizi kalsın", "B) Sayıyı azalt (5–6, ağız çevresinde küme)",
			"C) Ağız boyunca zincir / başka dizilim", "D) Başka (kullanıcı tarif eder)"], "coast.json adaları"))
	out.append(_question("K3", "D1 / D6 karşı kıyı",
			"D1 körfezin kuzey burnunda, D6 güney kıyıda (ÇIKARIM); su aralığı ≈ %s km, feribot ≈ %s km." % [
			_gap_km(m), num(float(m.gap.get("ferry_length_m", 0.0)) / 1000.0, 1)],
			["A) D1 kuzey, D6 güney (şimdiki)", "B) D1 güney, D6 kuzey (takas)",
			"C) Aralık daha dar / daha geniş olsun", "D) Başka (kullanıcı tarif eder)"],
			"regions.json çapaları, feribot hattı, D1/D6 kıyı biçimi"))
	var yard_txt := ""
	if int(m.yard.get("count", 0)) > 0:
		yard_txt = ", saha yapıları kıyıya en az %s m" % num(float(m.yard.get("min_shore_m", 0.0)), 0)
	out.append(_question("K4", "Liman konumu",
			"Liman ana karada, D4'ün batısında (kanon); kıyıdan ≈ %s m içeride%s." % [_port_shore(m), yard_txt],
			["A) Şimdiki konum kalsın", "B) Doğrudan kıyı şeridine bitişik (T-001b)",
			"C) Liman yarımadası / koy içi başka kıyı parçası", "D) Başka (kullanıcı tarif eder)"],
			"sites.json liman, kıyı biçimi, liman dokusu"))
	out.append(_question("K5", "Ova / yamaç oranı",
			"Ana karada düz ova %%%s, yamaç %%%s, sırt/yüksek %%%s (eşik <%d / %d–%d / ≥%d m)." % [
			pct(float(m.land_stats.get("plain_share", 0.0))), pct(float(m.land_stats.get("slope_share", 0.0))),
			pct(float(m.land_stats.get("ridge_share", 0.0))), int(TopologyModel.PLAIN_MAX_M),
			int(TopologyModel.PLAIN_MAX_M), int(TopologyModel.SLOPE_MAX_M), int(TopologyModel.SLOPE_MAX_M)],
			["A) Dağılım kalsın", "B) Daha geniş ova (tarım ve büyüme alanı)", "C) Daha çok yamaç / kıyı tepesi",
			"D) Başka (kullanıcı tarif eder)"], "terrain.json massif/ova parametreleri"))
	out.append(_question("K6", "Bölge kapsamı ve T0 yoğunluğu",
			("D1+D6 yapıların %%%s'ini taşıyor; D2–D5 daha küçük merkezler. " % pct(core_building_share(m))
			if m.building_total > 0 else "T0 yerleşimi yüklenmedi. ") + "Kapsamlar yaklaşık elips.",
			["A) Mevcut oran kalsın", "B) Çekirdek (D1+D6) daha kompakt/yoğun", "C) D2–D5 merkezleri daha büyük",
			"D) Bölge kapsamlarını kullanıcı çizer / tarif eder"], "regions.json kapsamları, ağ doku yarıçapları"))
	return out


## D1+D6 yapılarının toplama oranı (0..1); yerleşim yoksa 0.
static func core_building_share(m: TopologyModel) -> float:
	if m.building_total <= 0:
		return 0.0
	var n := 0
	for code in [&"D1", &"D6"]:
		var mark := m.region_mark(code)
		if mark != null:
			n += mark.buildings
	return float(n) / float(m.building_total)


static func backbone_edge_count(m: TopologyModel) -> int:
	var n := 0
	for cls in TopologyModel.BACKBONE_CLASSES:
		n += int(m.network_edge_counts.get(cls, 0))
	return n


static func _gap_km(m: TopologyModel) -> String:
	return num(float(m.gap.get("water_gap_m", 0.0)) / 1000.0, 1) if bool(m.gap.get("valid", false)) else "?"


static func _port_shore(m: TopologyModel) -> String:
	var port := m.site_mark(&"port")
	return num(port.shore_m, 0) if port != null else "?"


static func _island_ids(m: TopologyModel) -> String:
	if m.islands.is_empty():
		return "yok"
	return "%s–%s" % [m.islands[0].id, m.islands[m.islands.size() - 1].id]


static func _island_area(m: TopologyModel) -> float:
	var a := 0.0
	for isl in m.islands:
		a += isl.area_km2
	return a


static func _row(status: String, item: String, detail: String, req: String) -> Dictionary:
	return {"status": status, "item": item, "detail": detail, "req": req}


static func _question(id: String, title: String, current: String, options: Array[String],
		affects: String) -> Dictionary:
	return {"id": id, "title": title, "current": current, "options": options, "affects": affects}
