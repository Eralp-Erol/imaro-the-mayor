class_name ReactionAgenda
extends RefCounted
## T-042b · Yerinden edilmenin gündem ve medya yolu (D-008/D-011, political-events PE-01/PE-04). Kamulaştırma bir kesimi
## yerinden ettiyse PE-01 tipi bir gündem öğesi açılır; tepki basamağı (`bloc.react`) şartı aranmaz: yerinden edilme
## doğrudan nedendir ve oyuncunun görmesi gerekir. Öğenin ateşleme gerekçesi `ReactionCause` kaydına bağlıdır (komut,
## parseller, hane sayısı). Aynı nedenle medya organına haber adayı verilir (PE-04 yolu): yayın kararını medya motoru
## KENDİ kuralıyla verir, burada yayımlanmayı zorlayan bir şey yoktur.
##
## İKİ OKUMA (ikisi de `reactions.json`, veri):
##  1. Bölge ölçeği (`agenda`): kesimin bölge sinyali (yerinden edilen hane / BÖLGE hanesi) eşiğe ulaşınca. Büyük
##     bölgede (gerçek D2: 8686 hane) tek yolun yerinden ettiği hane bu orana ulaşamaz ve kesim payı kapısı
##     (`min_share_pm`) kesimi zaten dışarıda bırakır: sessiz kalır.
##  2. Mahalle ölçeği (`local`, 2026-10-31): yolun (komutun) KENDİ yerinden ettiği hane, bir mahallenin hane sayısına
##     (veri) oranlanır; yerinden edilen varsa komut başına BİR öğe açılır. Yakındaki (yerinden edilmeyen) haneler
##     yalnız baskıyı artırır, tek başına öğe açmaz; yerinden edilen 0 ise sessiz kalır (sahte tepki yok). Açılmış
##     (komut, bölge) `politics.reaction_local.opened` içinde tutulur: aynı yol için öğe yeniden açılmaz (gündem
##     yağmuru yok).
##  D-014 §3 (2026-11-01): evi yıkılan + yol dibindekiler YÜKSEK (öğe baskısı tabanı `floor_pressure_pm`); ilçe geneli
##  çok az ama sıfır değil (`_district_grievance`); "yeniden yerleşti mi" kararı tek noktada (`ReactionRehousing`,
##  şimdilik hep hayır); geri alma kancası `retract_command`.
##
## YALNIZ tepki defteri varken çalışır (kamulaştırmasız koşuda durum ve hash değişmez; `reaction_local` ilk öğe açılınca
## yaratılır). Silahlanma/bekleme/karşılıklı dışlama kapıları olay motorunundur (aynı kapılar). Özel bina yaratmaz
## (CAN-03): yalnız gündem + haber + gerekçe. Sayılar `PoliticsConfig.reactions` (veri). Tarama başına en çok bir öğe.

const SCALE := 1000
const SOURCE := "displacement"
const LOCAL_KEY := "reaction_local"


## Haftalık (PoliticsSystem; kesim taraması SONRASI, olay taramasından sonra). Açılan öğe sayısını döner.
static func scan(state: GameState, ctx: PoliticsContext) -> int:
	if not PublicWorksState.has_reactions(state):
		return 0
	var cfg: Dictionary = ctx.politics.reactions["local"]
	var readings: Array[Dictionary] = []
	if bool(cfg["enabled"]):  # D-014 §3: yeniden iskân kararı TEK noktadan (ReactionRehousing)
		readings = local_readings(state, int(ctx.politics.blocs["reaction_window"]), cfg)
	var opened := _scan_region(state, ctx)
	if opened == 0:
		opened = _scan_local(state, ctx, readings)
	elif bool(cfg.get("independent_items", false)):
		_cover_local(state, readings)  # bölge öğesi bu yolları zaten açıklar: ikinci (yerel) öğe açılmaz
	if bool(cfg["enabled"]) and (int(cfg["district_floor"]) > 0 or int(cfg["district_gain"]) > 0):
		_district_grievance(state, ctx, readings, cfg)
	return opened


## Bölge ölçeği (eski yol): kesimin bölge sinyali eşikte.
@warning_ignore("integer_division")
static func _scan_region(state: GameState, ctx: PoliticsContext) -> int:
	var cfg: Dictionary = ctx.politics.reactions["agenda"]
	var pol := PoliticsState.data(state)
	var best := ""
	var best_level := 0
	for key in PoliticsState.bloc_keys(state):  # eşitlikte anahtar sırası (ilk gelen kalır)
		var level := int(pol["blocs"][key]["signals"].get("displacement", 0))
		if level >= int(cfg["min_displacement_pm"]) and level > best_level:
			best = key
			best_level = level
	if best.is_empty():
		return 0
	var pressure := clampi(best_level * SCALE / int(cfg["full_displacement_pm"]), 0, SCALE)
	if not EventEngine.can_open_direct(state, ctx, str(cfg["template"]), pressure):
		return 0  # kapılar kapalıyken neden kaydı yazılmaz (kayıt hacmi)
	var bloc: Dictionary = pol["blocs"][best]
	var rows := EconomyQuery.region_stats(state, ctx.economy)
	var cause := ReactionCause.record(state, ctx, best, bloc, BlocEngine.reaction_signals(state, ctx, rows))
	if cause.is_empty():
		return 0
	PoliticsState.count(state, "reason_records")
	var opened := EventEngine.open_direct(state, ctx, str(cfg["template"]), best, pressure, SOURCE,
		PackedInt64Array([cause["id"]]))
	if opened:
		_queue_story(state, best, bloc, pressure, cause)
	return 1 if opened else 0


## Medya haber adayı: konu = kesimin baskın şikâyet konusu; neden = yerinden edilme kaydı.
@warning_ignore("integer_division")
static func _queue_story(state: GameState, key: String, bloc: Dictionary, pressure: int, cause: Dictionary,
		topic_override: String = "", story_key: String = "") -> void:
	var actor := ActorStore.actor_ref(state, key)
	var topic := topic_override if not topic_override.is_empty() \
		else BlocEngine.dominant_topic(actor["salience"], actor["state"].get("grievances", {}))
	var total := 0
	for other in PoliticsState.bloc_keys(state):
		total += int(PoliticsState.data(state)["blocs"][other]["size"])
	MediaEngine.queue_story(state, {
		"kind": "protest", "topic": topic, "subject": key, "conflict": pressure,
		"scale": int(bloc["size"]) * SCALE / maxi(total, 1), "fact": -pressure,
		"parent_ids": [int(cause["id"])], "key": story_key if not story_key.is_empty() else "displacement|%s" % key,
	})


# --- Mahalle ölçeği (2026-10-31) ---

## Saf okuma: yerinden edilen (`displaced_milli`: hane x 1000, pencerede sönmüş) ve yakındaki (`nearby_milli`: hane x
## mesafe ağırlığı pm, sönmüş) haneler, `local.neighborhood_households` mahalle büyüklüğüne oranlanır. Dönüş:
## {displacement_pm, proximity_pm, level_pm, pressure (0..1000), opens}. `opens`: yerinden edilme tek başına eşikte.
@warning_ignore("integer_division")
static func local_reading(cfg: Dictionary, displaced_milli: int, nearby_milli: int) -> Dictionary:
	var size := maxi(int(cfg["neighborhood_households"]), 1)
	var displacement := (displaced_milli + size - 1) / size  # yukarı yuvarla: yerinden edilen varsa en az 1 (B-007)
	var proximity := nearby_milli / size
	var level := displacement + proximity * int(cfg["proximity_share_pm"]) / SCALE
	var pressure := clampi(level * SCALE / maxi(int(cfg["full_displacement_pm"]), 1), 0, SCALE)
	var opens: bool = bool(cfg["enabled"]) and displaced_milli > 0 and displacement >= int(cfg["min_displacement_pm"])
	var floor_pm := int(cfg.get("floor_pressure_pm", 0))
	if opens and floor_pm > 0:  # D-014 §3: evi yıkılanın tepkisi yüksek (taban), kalabalıkla tavana çıkar
		pressure = floor_pm + pressure * (SCALE - floor_pm) / SCALE
	return {
		"displacement_pm": displacement, "proximity_pm": proximity, "level_pm": level, "pressure": pressure,
		"opens": opens,
	}


## Tepki defterinden (komut, bölge) başına mahalle okumaları (kod, komut artan): `local_reading` alanları +
## {key, code, command_id, households (gerçek, sönmemiş ve HÂLÂ barınamayan hane; karar
## `ReactionRehousing.still_unhoused`), displaced_total (komutun yerinden ettiği)}. Pencere dışı satırlar sayılmaz.
@warning_ignore("integer_division")
static func local_readings(state: GameState, window: int, cfg: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rehoused := ReactionRehousing.index(state)  # TEK noktadan rahatlama (T-065); kayıt yoksa boş
	var book: Dictionary = PublicWorksState.data(state).get("displaced", {})
	var codes: Array = book.keys()
	codes.sort()
	for code: String in codes:
		var by_command := {}
		for row: Array in PublicWorksState.reaction_rows(state, "displaced", code):
			var age := state.tick - int(row[0])
			if age < 0 or age >= window:
				continue
			var entry: Dictionary = by_command.get(int(row[2]), {"displaced": 0, "nearby": 0, "households": 0})
			entry["displaced"] = int(entry["displaced"]) + int(row[1]) * SCALE * (window - age) / window
			entry["households"] = int(entry["households"]) + int(row[1])
			by_command[int(row[2])] = entry
		for row: Array in PublicWorksState.reaction_rows(state, "nearby", code):
			var age := state.tick - int(row[0])
			if age >= 0 and age < window and by_command.has(int(row[2])):
				by_command[int(row[2])]["nearby"] = int(by_command[int(row[2])]["nearby"]) \
					+ int(row[1]) * (window - age) / window
		var commands: Array = by_command.keys()
		commands.sort()
		for command_id: int in commands:
			var entry: Dictionary = by_command[command_id]
			var total := int(entry["households"])
			var kept := ReactionRehousing.still_unhoused(code, command_id, total, rehoused)  # TEK karar noktası
			if kept < total:
				entry["displaced"] = int(entry["displaced"]) * kept / total
				entry["households"] = kept
			var reading := local_reading(cfg, int(entry["displaced"]), int(entry["nearby"]))
			reading["displaced_total"] = total
			reading["key"] = "%d|%s" % [command_id, code]
			reading["code"] = code
			reading["command_id"] = command_id
			reading["households"] = int(entry["households"])
			var detail := ReactionRehousing.detail(code, command_id, rehoused)
			if not detail.is_empty():  # yalnız tahsis kaydı olan okumada (politika açıkken): neden kaydı için gerçek sayılar
				reading["rehoused"] = int(detail["rehoused"])
				reading["unplaced"] = int(detail["unplaced"])
			out.append(reading)
	return out


## Haftalık mahalle taraması: henüz öğe açılmamış, eşikteki okumaların en güçlüsü (eşitlikte kod/komut sırası) için bir
## PE-01 öğesi. Kapılar (kilometre taşı, silahlanma, karşılıklı dışlama) kapalıysa kayıt yazılmaz; okuma sönene dek
## sonraki taramalarda yeniden denenir.
static func _scan_local(state: GameState, ctx: PoliticsContext, readings: Array[Dictionary]) -> int:
	var cfg: Dictionary = ctx.politics.reactions["local"]
	if not bool(cfg["enabled"]):
		return 0
	var key := _bloc_of_cohort(state, str(cfg["cohort"]))
	if key.is_empty():
		return 0
	var pol := PoliticsState.data(state)
	var done: Dictionary = pol.get(LOCAL_KEY, {}).get("opened", {})
	var best := {}
	for reading in readings:
		if bool(reading["opens"]) and not done.has(reading["key"]) \
				and (best.is_empty() or int(reading["level_pm"]) > int(best["level_pm"])):
			best = reading
	if best.is_empty():
		return 0
	var template := str(ctx.politics.reactions["agenda"]["template"])
	var solo := bool(cfg.get("independent_items", false))
	if not EventEngine.can_open_direct(state, ctx, template, int(best["pressure"]), solo):
		return 0  # kapılar kapalıyken neden kaydı yazılmaz (kayıt hacmi)
	var cause := ReactionCause.record_local(state, ctx, key, best)
	if cause.is_empty():
		return 0
	PoliticsState.count(state, "reason_records")
	var events: Dictionary = pol["events"]
	var item_id := int(events["next_item"])
	if not EventEngine.open_direct(state, ctx, template, key, int(best["pressure"]), SOURCE,
			PackedInt64Array([cause["id"]]), solo):
		return 0
	var topic := _displacement_topic(ctx, str(cfg["cohort"]))
	var item := EventEngine.item_by_id(state, item_id)
	if not item.is_empty() and not topic.is_empty():
		item["topic"] = topic  # yanıt etkileri (şikâyet defteri, güven) bu öğenin NEDEN konusuna yazar
	if not pol.has(LOCAL_KEY):
		pol[LOCAL_KEY] = {"opened": {}}
	pol[LOCAL_KEY]["opened"][best["key"]] = state.tick
	if not pol[LOCAL_KEY].has("items"):
		pol[LOCAL_KEY]["items"] = {}
	pol[LOCAL_KEY]["items"][best["key"]] = item_id  # komut -> gündem öğesi (geri alma kancası / ileri kullanım)
	_queue_story(state, key, pol["blocs"][key], int(best["pressure"]), cause, topic,
		"displacement|%s|%s" % [key, best["key"]])  # her yol ayrı haber (tekrar sönümü yalnız aynı yolda)
	return 1


## Bölge ölçekli öğe açıldıysa, eşikteki yerel okumalar "açıldı" sayılır (aynı yol için iki öğe olmaz).
static func _cover_local(state: GameState, readings: Array[Dictionary]) -> void:
	var pol := PoliticsState.data(state)
	for reading in readings:
		if not bool(reading["opens"]) or pol.get(LOCAL_KEY, {}).get("opened", {}).has(reading["key"]):
			continue
		if not pol.has(LOCAL_KEY):
			pol[LOCAL_KEY] = {"opened": {}}
		pol[LOCAL_KEY]["opened"][reading["key"]] = state.tick


## Kohortu `cohort_id` olan kesimin anahtarı ("" = yok).
static func _bloc_of_cohort(state: GameState, cohort_id: String) -> String:
	var blocs: Dictionary = PoliticsState.data(state)["blocs"]
	for key in PoliticsState.bloc_keys(state):
		if str(blocs[key]["cohort"]) == cohort_id:
			return key
	return ""


## Kohortun `displacement` şikâyet kuralının konusu (veri); yoksa "".
static func _displacement_topic(ctx: PoliticsContext, cohort_id: String) -> String:
	for rule: Dictionary in ctx.politics.cohort(cohort_id).get("grievance_rules", []):
		if str(rule["signal"]) == SOURCE:
			return str(rule["topic"])
	return ""


# --- İlçe geneli tepki ve tepkiyi kaldırma (D-014 §3) ---

## Haftalık ilçe geneli (D-014 §3): yerinden edilme sürerken, bölge payı olan her kesimin yerinden edilme konulu şikâyet
## defterine küçük bir puan eklenir (sıfır değil, çok az); defter kendiliğinden söner (`decay_pm.grievance`).
@warning_ignore("integer_division")
static func _district_grievance(state: GameState, ctx: PoliticsContext, readings: Array[Dictionary],
		cfg: Dictionary) -> void:
	var seekers := {}  # bölge -> hâlâ barınamayan hane (tüm yollar)
	for reading in readings:
		seekers[reading["code"]] = int(seekers.get(reading["code"], 0)) + int(reading["households"])
	var latent := {}
	for row in EconomyQuery.region_stats(state, ctx.economy):
		latent[String(row["code"])] = int(row["latent_hh"])
	var codes: Array = seekers.keys()
	codes.sort()
	var blocs: Dictionary = PoliticsState.data(state)["blocs"]
	for code: String in codes:
		if int(seekers[code]) <= 0:
			continue
		var add := maxi(int(cfg["district_floor"]), int(seekers[code]) * int(cfg["district_gain"])
			/ maxi(int(latent.get(code, 1)), 1))
		for key in PoliticsState.bloc_keys(state):
			var topic := _displacement_topic(ctx, str(blocs[key]["cohort"]))
			if topic.is_empty() or not (blocs[key]["exposure"] as Dictionary).has(code):
				continue
			var astate: Dictionary = ActorStore.actor_ref(state, key)["state"]
			if not astate.has("grievances"):
				astate["grievances"] = {}
			astate["grievances"][topic] = clampi(int(astate["grievances"].get(topic, 0)) + add, 0, SCALE)


## GERİ ALMA KANCASI: bir yol/olay (komut) kimliğine bağlı tepki kayıtlarını (yerinden edilme + yakınlık satırları, tüm
## bölgeler) kaldırır; dönüş: silinen satır sayısı (bilinmeyen komut = 0, durum DEĞİŞMEZ). Sonraki taramalar bu yolu
## görmez (yeni öğe açılmaz, ilçe şikâyeti eklenmez); ZATEN açılmış gündem öğesi ve `opened` işareti DOKUNULMADAN kalır
## (öğeyi kapatmak EventEngine'in işi; geri alma işleyicisi gerekirse ayrıca yapar). Yol komutlarına DOKUNMAZ.
static func retract_command(state: GameState, command_id: int) -> int:
	var d := PublicWorksState.data(state)
	var removed := 0
	for book in PublicWorksState.REACTION_BOOKS:
		if not d.has(book):
			continue
		var table: Dictionary = d[book]
		var codes: Array = table.keys()
		codes.sort()
		for code: String in codes:
			var kept: Array = (table[code] as Array).filter(func(row: Array) -> bool: return int(row[2]) != command_id)
			if kept.size() != (table[code] as Array).size():
				removed += (table[code] as Array).size() - kept.size()
				table[code] = kept
	return removed
