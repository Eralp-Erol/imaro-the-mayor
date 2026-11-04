class_name PublicWorksState
extends RefCounted
## Oyuncu yolu durum bölümü `state.systems["public_works"]` (T-042 adım 2, ADR-0005 Ek E). Bölüm YALNIZ ilk uygulanan
## yolda yaratılır; okuma/doğrulama (`validate_command`) bölüm yaratmaz. Böylece yolsuz koşuların `state_hash`'i (altın
## değerler `tests/sim/m2_query_test.gd`) bit-bit aynıdır.
##
## Düzen (hepsi düz veri, ondalık yok):
##   version               VERSION
##   base_graph_hash       yolların uygulandığı TABAN ağın graf özeti (`WorldNetwork.base_hash`); yükleme uyuşmazsa
## reddeder
##   ops                   [NetworkDelta op'ları] (add_road: pts_cm [[x, z]...], class, width_dm), uygulama sırasıyla
##   hashes                [graf hash'i, op i uygulandıktan SONRA]; kayıt/yükleme her adımda karşılaştırır
##   works                 [{id, command_id, tick, road_class, length_cm, region_units {kod: birim}}]; ops ile aynı
## uzunluk
##   infra_bonus           TÜRETİLMİŞ {kod: birim}: bölge altyapı kapasitesine EKLENEN (ekonomi okur; sütun yazılmaz)
##   infra_source          TÜRETİLMİŞ {kod: "command.N"}: bölgede kapasiteyi EN SON artıran yol (gerekçe `source_ref`i)
## Türetilmiş iki sözlük `works`ten yeniden hesaplanabilir; `validate_data` uyuşmayı bozuk kayıt sayar. Ekonomi sütunu
## `regions.infra_cap`a DOKUNULMAZ: etkin kapasite = taban + bonus; geri alma bonusu kendiliğinden düşürür.
##
## v2 (T-042b, D-011, ADR-0005 Ek F): bölüm İLK kamulaştırmada v1'den v2'ye yükselir (yolsuz ve kamulaştırmasız
## koşuların
## durumu/hash'i v1 kalır). Eklenenler:
##   works[i].expropriation   YALNIZ kamulaştıran yolda: {parcel_ids [artan], snapshots [alınan satırın anlık
## görüntüsü],
##                            built_parcels, project_parcels, res_units, com_units, households, regions {kod: parsel},
##                            latent_removed {kod: hane}, nearby_households, nearby_parcels, fate}
##   taken                    TÜRETİLMİŞ {parsel_kimliği: komut_kimliği}: şu an alınmış parseller (geri alma düşürür)
##   displaced                {kod: [[tick, hane, komut]...]} yerinden edilme olayları. GERİ ALINMAZ (halk tepkisi
##                            geri gelmez, D-011); eski kayıtlar `reaction_keep_days` sonra budanır
##   nearby                   {kod: [[tick, hane x ağırlık_pm, komut]...]} yakınlık olayları (D-014: o yolun geri
##                            alınması bu satırları SİLER; halk tepkisi hiç olmamış gibi olur)
##
## T-042c (D-014 §1, ek alanlar; sürüm artmaz, yolsuz koşuların durumu aynı kalır):
##   undo                     KLASİK GERİ AL penceresi {command_id, scans}: yalnız en son yapılan yol geri alınabilir ve
##                            ancak başka bir yol/yıkım yapılana, geri alınana ya da halk tepkisi siyaset taramasına
##                            girene kadar (`scans`: yol uygulanırken siyasetin tarama sayacı). {} = pencere kapalı.
##                            Alan YOKSA (eski kayıt) son yol açık sayılır.
##   works[i].kind            "demolish" yalnız yıkım satırlarında (yolun her kenarı için bir satır = bir ağ işlemi,
##                            op `remove_edge`); yol satırlarında yoktur. Yıkım satırı: {kind, command_id (yıkım
##                            komutu), target_command_id, edge, road_class, length_cm 0, region_units {}}
##   works[i].demolished_by   YIKILMIŞ yol satırında yıkım komutunun kimliği. Satır silinmez (alınan parseller
##                            `taken`da kalır, bütçe satırı yerinde durur); kapasite etkisi türetmede düşer.

const KEY := "public_works"
const VERSION := 1
const VERSION_EXPROPRIATION := 2
const VERSION_LAND_REUSE := 3
const OP_ADD_ROAD := "add_road"
const OP_REMOVE_EDGE := "remove_edge"
const OP_RESTORE_PARCELS := "restore_parcels"
const KIND_DEMOLISH := "demolish"
const KIND_LAND_REUSE := "land_reuse"
const COMMAND_PREFIX := "command."
const REACTION_BOOKS: Array[String] = ["displaced", "nearby"]


## Bölüm (DOĞRUDAN durumun parçası); yoksa boş sözlük.
static func data(state: GameState) -> Dictionary:
	var d: Variant = state.systems.get(KEY, null)
	return d if d is Dictionary else {}


static func is_present(state: GameState) -> bool:
	return not data(state).is_empty()


## Kayıtlı yol sayısı (bölüm yoksa 0).
static func work_count(state: GameState) -> int:
	var d := data(state)
	return 0 if d.is_empty() else (d["works"] as Array).size()


## Satır bir yıkım satırı mı (kenar başına bir ağ işlemi)?
static func is_demolition(entry: Dictionary) -> bool:
	return str(entry.get("kind", "")) == KIND_DEMOLISH


static func is_land_reuse(entry: Dictionary) -> bool:
	return str(entry.get("kind", "")) == KIND_LAND_REUSE


static func is_road_work(entry: Dictionary) -> bool:
	return str(entry.get("kind", "")).is_empty()


## Satır, ağda duran bir oyuncu yolu mu (yıkım satırı da yıkılmış yol da değil)?
static func is_standing_road(entry: Dictionary) -> bool:
	return is_road_work(entry) and not entry.has("demolished_by")


## Yolun yeniden iskân tahsis kaydı ({} = yok: politika kapalıydı ya da yerinden edilen yoktu).
static func resettlement_of(work: Dictionary) -> Dictionary:
	return (work.get("expropriation", {}) as Dictionary).get("resettlement", {})


## Yolun yeniden iskân bedeli (kayıt yoksa 0).
static func resettlement_cost(work: Dictionary) -> int:
	return int(resettlement_of(work).get("cost", 0))


## Tahsis kaydı olan yollar {komut kimliği: kayıt}. YIKILMIŞ yol da sayılır (tepki satırları yıkımda silinmez, rahatlama
## sürer); geri alınmış yol `works`ta yoktur. Kayıt yoksa BOŞ sözlük.
static func resettlement_records(state: GameState) -> Dictionary:
	var out := {}
	var d := data(state)
	if d.is_empty():
		return out
	for work: Dictionary in d["works"]:
		var record := resettlement_of(work)
		if is_road_work(work) and not record.is_empty():
			out[int(work["command_id"])] = record
	return out


## Ayakta duran oyuncu yolu satırları (eskiden yeniye; değer kopyası DEĞİL, bölümdeki sözlükler).
static func standing_roads(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := data(state)
	if d.is_empty():
		return out
	for entry: Dictionary in d["works"]:
		if is_standing_road(entry):
			out.append(entry)
	return out


## Komut kimliğiyle ayakta duran yol satırı; yoksa {}.
static func standing_road(state: GameState, command_id: int) -> Dictionary:
	for entry in standing_roads(state):
		if int(entry["command_id"]) == command_id:
			return entry
	return {}


## Tabana eklenen kapasite birimi (bölüm/kod yoksa 0). Ekonomi karar yolunda çağrılır: O(1).
static func infra_bonus(state: GameState, region_code: Variant) -> int:
	var d: Variant = state.systems.get(KEY, null)
	return 0 if not (d is Dictionary) else int((d["infra_bonus"] as Dictionary).get(String(region_code), 0))


## Bölgede kapasiteyi en son artıran yolun komut referansı (`command.N`); yoksa &"".
static func infra_source(state: GameState, region_code: Variant) -> StringName:
	var d: Variant = state.systems.get(KEY, null)
	if not (d is Dictionary):
		return &""
	return StringName(str((d["infra_source"] as Dictionary).get(String(region_code), "")))


## Alınmış parselin alınma komut kimliği (`command.N`nin N'i); alınmamışsa 0. O(1).
static func taken_command(state: GameState, parcel_id: int) -> int:
	var d: Variant = state.systems.get(KEY, null)
	if not (d is Dictionary) or not (d as Dictionary).has("taken"):
		return 0
	return int((d["taken"] as Dictionary).get(parcel_id, 0))


## Şu an alınmış parsel sayısı (bölüm/anahtar yoksa 0).
static func taken_count(state: GameState) -> int:
	var d := data(state)
	return 0 if not d.has("taken") else (d["taken"] as Dictionary).size()


## Bölge için kayıtlı tepki olayları: `book` = "displaced" | "nearby". [[tick, değer, komut]...]; yoksa [].
static func reaction_rows(state: GameState, book: String, region_code: String) -> Array:
	var d: Variant = state.systems.get(KEY, null)
	if not (d is Dictionary) or not (d as Dictionary).has(book):
		return []
	return (d[book] as Dictionary).get(region_code, [])


## Kamulaştırma tepki kaydı var mı (v2)? Siyaset sinyalleri YALNIZ bu durumda yazılır (yolsuz/kamulaştırmasız koşularda
## kesim durumu eskisiyle bit-bit aynıdır).
static func has_reactions(state: GameState) -> bool:
	var d := data(state)
	return d.has("displaced")


## Tepki olaylarını ekler (geri alınmaz). `displaced`/`nearby`: {kod: değer}; `keep_days` > 0: bu günden eski satırlar
## budanır. Bölüm v2 olmalı (`append_work` kamulaştıran işte yükseltir).
static func note_reactions(state: GameState, command_id: int, displaced: Dictionary, nearby: Dictionary,
		keep_days: int) -> void:
	var d := data(state)
	var rows := {"displaced": displaced, "nearby": nearby}
	for book in REACTION_BOOKS:
		var table: Dictionary = d[book]
		for code: String in _sorted_keys(rows[book]):
			if int(rows[book][code]) > 0:
				var list: Array = table.get(code, [])
				list.append([state.tick, int(rows[book][code]), command_id])
				table[code] = list
		if keep_days > 0:
			for code: String in table:
				var kept: Array = []
				for row: Array in table[code]:
					if state.tick - int(row[0]) <= keep_days:
						kept.append(row)
				table[code] = kept


static func _sorted_keys(table: Dictionary) -> Array:
	var keys: Array = table.keys()
	keys.sort()
	return keys


## Yeni yolu ekler (bölüm yoksa yaratır). `work`: {command_id, tick, road_class, length_cm, region_units}; kamulaştıran
## yolda ek olarak `expropriation` (bölümü v2'ye yükseltir).
static func append_work(state: GameState, base_graph_hash: String, op: Dictionary, graph_hash_after: String,
		work: Dictionary) -> void:
	var d := state.system_data(StringName(KEY))
	if d.is_empty():
		d["version"] = VERSION
		d["base_graph_hash"] = base_graph_hash
		d["ops"] = []
		d["hashes"] = []
		d["works"] = []
		d["infra_bonus"] = {}
		d["infra_source"] = {}
	(d["ops"] as Array).append(op.duplicate(true))
	(d["hashes"] as Array).append(graph_hash_after)
	var entry := work.duplicate(true)
	entry["id"] = (d["works"] as Array).size() + 1
	(d["works"] as Array).append(entry)
	if entry.has("expropriation") and int(d["version"]) < VERSION_EXPROPRIATION:  # ilk kamulaştırma: v1 -> v2
		d["version"] = VERSION_EXPROPRIATION
		d["taken"] = {}
		d["displaced"] = {}
		d["nearby"] = {}
	d["undo"] = {"command_id": int(entry["command_id"]), "scans": UndoWindow.scans(state)}  # klasik geri al (D-014)
	rebuild_derived(d)


## Yıkım: `target_command_id` yolunun her kenarı için bir satır + ağ işlemi eklenir (`ops` = remove_edge sırası) ve
## hedef yol satırı `demolished_by` ile işaretlenir (satır silinmez). Geri al penceresi kapanır. `ops[i]`/`hashes[i]`:
## i. kenar silindikten sonraki işlem ve graf özeti. Bölüm olmalı.
static func append_demolition(state: GameState, command_id: int, target_command_id: int, road_class: String,
		ops: Array, hashes: Array) -> void:
	var d := data(state)
	for i in ops.size():
		(d["ops"] as Array).append((ops[i] as Dictionary).duplicate(true))
		(d["hashes"] as Array).append(hashes[i])
		(d["works"] as Array).append({"id": (d["works"] as Array).size() + 1, "kind": KIND_DEMOLISH,
			"command_id": command_id, "tick": state.tick, "target_command_id": target_command_id,
			"edge": int((ops[i] as Dictionary)["edge"]), "road_class": road_class, "length_cm": 0,
			"region_units": {}})
	for entry: Dictionary in d["works"]:
		if is_road_work(entry) and int(entry["command_id"]) == target_command_id:
			entry["demolished_by"] = command_id
	d["undo"] = {}
	rebuild_derived(d)


## D-018: ilk yeni imar yürürlüğünde v3. Dünya restore işlemleri yol/yıkım ile AYNI kronolojik deftere girer.
static func append_land_reuse(state: GameState, command_id: int, source_op: int, ids: PackedInt64Array,
		op: Dictionary, graph_hash_after: String) -> void:
	var d := data(state)
	var source_command: int = d["works"][source_op]["command_id"]
	d["version"] = VERSION_LAND_REUSE
	(d["ops"] as Array).append(op.duplicate(true))
	(d["hashes"] as Array).append(graph_hash_after)
	(d["works"] as Array).append({"id": (d["works"] as Array).size() + 1, "kind": KIND_LAND_REUSE,
		"command_id": command_id, "tick": state.tick, "source_op": source_op,
		"source_command_id": source_command, "parcel_ids": Array(ids), "road_class": "",
		"length_cm": 0, "region_units": {}})
	d["undo"] = {}
	rebuild_derived(d)


## Klasik geri al penceresini kapatır (geri alma sonrası: yığılmaz). Bölüm yoksa bir şey yapmaz.
static func close_undo(state: GameState) -> void:
	var d := data(state)
	if not d.is_empty():
		d["undo"] = {}


## Komuta ait tepki satırı var mı (yerinden edilme/yakınlık defterleri)?
static func has_reaction_rows(state: GameState, command_id: int) -> bool:
	var d := data(state)
	for book in REACTION_BOOKS:
		var table: Dictionary = d.get(book, {})
		for code: Variant in table:
			for row: Array in table[code]:
				if int(row[2]) == command_id:
					return true
	return false


## Tepki defterinde boşalan bölge anahtarlarını siler (geri alma: `ReactionAgenda.retract_command` satırları siler,
## boş liste bırakır; defter hiç tepki olmamış gibi boş kalsın).
static func prune_empty_reactions(state: GameState) -> void:
	var d := data(state)
	for book in REACTION_BOOKS:
		if not d.has(book):
			continue
		var table: Dictionary = d[book]
		for code: String in _sorted_keys(table):
			if (table[code] as Array).is_empty():
				table.erase(code)


## Son yolu çıkarır ve döndürür ({} = yok). Türetilmiş sözlükler yeniden hesaplanır.
static func pop_work(state: GameState) -> Dictionary:
	var d := data(state)
	if d.is_empty() or (d["works"] as Array).is_empty():
		return {}
	(d["ops"] as Array).pop_back()
	(d["hashes"] as Array).pop_back()
	var work: Dictionary = (d["works"] as Array).pop_back()
	d["undo"] = {}  # geri alma yığılmaz: bir sonraki yol, yeni bir yol yapılana kadar geri alınamaz (D-014)
	rebuild_derived(d)
	return work


## Türetilmiş `infra_bonus`/`infra_source`u `works`ten yeniden kurar (bölge kodu sıralı; boş bonus yazılmaz).
static func rebuild_derived(d: Dictionary) -> void:
	var derived := derive(d["works"])
	d["infra_bonus"] = derived["bonus"]
	d["infra_source"] = derived["source"]
	if d.has("taken"):
		d["taken"] = derived["taken"]


static func derive(works: Array) -> Dictionary:
	var bonus := {}
	var source := {}
	var taken := {}
	for work: Dictionary in works:
		if is_demolition(work):
			continue
		if is_land_reuse(work):
			for id: Variant in work["parcel_ids"]:
				if int(taken.get(int(id), 0)) == int(work["source_command_id"]):
					taken.erase(int(id))
			continue
		if work.has("expropriation"):
			for id: Variant in work["expropriation"]["parcel_ids"]:
				taken[int(id)] = int(work["command_id"])
		if work.has("demolished_by"):
			continue  # yıkılmış yolun kapasite etkisi kalmaz; alınan parseller `taken`da kalır
		var units: Dictionary = work["region_units"]
		for code: Variant in units:
			var key := str(code)
			var amount := int(units[code])
			if amount <= 0:
				continue
			bonus[key] = int(bonus.get(key, 0)) + amount
			source[key] = "%s%d" % [COMMAND_PREFIX, int(work["command_id"])]
	return {"bonus": bonus, "source": source, "taken": taken}


## Bölge birimleri toplamı.
static func total_units(units: Dictionary) -> int:
	var sum := 0
	for code: Variant in units:
		sum += int(units[code])
	return sum


## Bölge kodları (String), sıralı: olay/öznitelik üretiminde deterministik sıra.
static func sorted_codes(units: Dictionary) -> Array:
	var codes: Array = units.keys()
	codes.sort()
	return codes


## Bölüm biçim hatası (Türkçe) ya da "". Bölüm yoksa geçerli. Ağa bakmaz (ağ eşitleme ayrıdır).
static func validate_data(value: Variant) -> String:
	if value == null:
		return ""
	var version: Variant = value.get("version", null) if value is Dictionary else null
	if version != VERSION and version != VERSION_EXPROPRIATION and version != VERSION_LAND_REUSE:
		return "durum.systems.public_works sürümü geçersiz"
	if typeof(value.get("base_graph_hash", null)) != TYPE_STRING:
		return "durum.systems.public_works.base_graph_hash dizge değil"
	for field_name in ["ops", "hashes", "works"]:
		if not (value.get(field_name, null) is Array):
			return "durum.systems.public_works.%s dizi değil" % field_name
	for field_name in ["infra_bonus", "infra_source"]:
		if not (value.get(field_name, null) is Dictionary):
			return "durum.systems.public_works.%s sözlük değil" % field_name
	var n: int = (value["ops"] as Array).size()
	if (value["hashes"] as Array).size() != n or (value["works"] as Array).size() != n:
		return "durum.systems.public_works ops/hashes/works uzunlukları farklı"
	for i in n:
		var problem := _op_problem(value["ops"][i]) + _hash_problem(value["hashes"][i]) \
			+ _work_problem(value["works"][i], i)
		if not problem.is_empty():
			return "durum.systems.public_works[%d]: %s" % [i, problem]
		if is_demolition(value["works"][i]) != (str(value["ops"][i].get("op", "")) == OP_REMOVE_EDGE):
			return "durum.systems.public_works[%d]: satır türü işlemle uyuşmuyor" % i
		if is_land_reuse(value["works"][i]) != (str(value["ops"][i].get("op", "")) == OP_RESTORE_PARCELS):
			return "durum.systems.public_works[%d]: arazi satırı işlemle uyuşmuyor" % i
		if is_land_reuse(value["works"][i]) and version != VERSION_LAND_REUSE:
			return "durum.systems.public_works[%d]: arazi kullanımı v3 gerektirir" % i
		if version == VERSION and (value["works"][i] as Dictionary).has("expropriation"):
			return "durum.systems.public_works[%d]: v1 kayıtta kamulaştırma satırı olamaz" % i
	var derived := derive(value["works"])
	if StateHash.of(derived["bonus"]) != StateHash.of(value["infra_bonus"]) \
			or StateHash.of(derived["source"]) != StateHash.of(value["infra_source"]):
		return "durum.systems.public_works türetilmiş kapasite yollarla uyuşmuyor"
	var window := _undo_problem(value) + _demolition_problem(value["works"])
	if not window.is_empty():
		return "durum.systems.public_works: %s" % window
	var land_problem := _land_reuse_problem(value) if version == VERSION_LAND_REUSE else ""
	if not land_problem.is_empty():
		return "durum.systems.public_works: %s" % land_problem
	return _expropriation_section_problem(value, derived) if version >= VERSION_EXPROPRIATION else ""


## v2 bölümü: `taken` türetilmişle aynı, tepki defterleri biçimli.
static func _expropriation_section_problem(value: Dictionary, derived: Dictionary) -> String:
	for field_name in ["taken", "displaced", "nearby"]:
		if not (value.get(field_name, null) is Dictionary):
			return "durum.systems.public_works.%s sözlük değil" % field_name
	if StateHash.of(derived["taken"]) != StateHash.of(value["taken"]):
		return "durum.systems.public_works.taken yollarla uyuşmuyor"
	for book in REACTION_BOOKS:
		for code: Variant in value[book]:
			if typeof(code) != TYPE_STRING or not (value[book][code] is Array):
				return "durum.systems.public_works.%s[%s] dizi değil" % [book, str(code)]
			for row: Variant in value[book][code]:
				if not (row is Array) or (row as Array).size() != 3 or typeof(row[0]) != TYPE_INT \
						or typeof(row[1]) != TYPE_INT or typeof(row[2]) != TYPE_INT:
					return "durum.systems.public_works.%s satırı [tick, değer, komut] tamsayı üçlüsü değil" % book
	return ""


## Klasik geri al penceresi: yoksa geçerli (eski kayıt); varsa {} ya da son satırdaki yolu gösteren {command_id, scans}.
static func _undo_problem(value: Dictionary) -> String:
	if not value.has("undo"):
		return ""
	var window: Variant = value["undo"]
	if not (window is Dictionary):
		return "undo sözlük değil"
	if (window as Dictionary).is_empty():
		return ""
	if typeof(window.get("command_id", null)) != TYPE_INT or typeof(window.get("scans", null)) != TYPE_INT:
		return "undo.command_id/scans tamsayı değil"
	var works: Array = value["works"]
	if works.is_empty():
		return "undo penceresi açık ama yol yok"
	var last: Dictionary = works[works.size() - 1]
	if not is_standing_road(last) or int(last["command_id"]) != int(window["command_id"]):
		return "undo penceresi son yolu göstermiyor"
	return ""


## Yıkım satırları: hedef yol satırı var ve `demolished_by` onu yıkan komutu gösteriyor; işaretli her yolun yıkım
## satırı var.
static func _demolition_problem(works: Array) -> String:
	var by_command := {}
	for entry: Dictionary in works:
		if is_road_work(entry):
			by_command[int(entry["command_id"])] = entry
	var marked := {}
	for entry: Dictionary in works:
		if not is_demolition(entry):
			continue
		if typeof(entry.get("target_command_id", null)) != TYPE_INT or typeof(entry.get("edge", null)) != TYPE_INT:
			return "yıkım satırı hedef/kenar tamsayı değil"
		var target: Variant = by_command.get(int(entry["target_command_id"]), null)
		if target == null or int(target.get("demolished_by", -1)) != int(entry["command_id"]):
			return "yıkım satırı yıkılmış bir yola bağlı değil"
		marked[int(entry["target_command_id"])] = true
	for command_id: int in by_command:
		if (by_command[command_id] as Dictionary).has("demolished_by") and not marked.has(command_id):
			return "yıkılmış yolun yıkım satırı yok"
	return ""


static func _expropriation_problem(x: Variant) -> String:
	if not (x is Dictionary):
		return "kamulaştırma kaydı sözlük değil"
	for field_name in ["parcel_ids", "snapshots"]:
		if not (x.get(field_name, null) is Array):
			return "kamulaştırma.%s dizi değil" % field_name
	for field_name in ["built_parcels", "project_parcels", "res_units", "com_units", "households", "nearby_households",
			"nearby_parcels"]:
		if typeof(x.get(field_name, null)) != TYPE_INT:
			return "kamulaştırma.%s tamsayı değil" % field_name
	for field_name in ["regions", "latent_removed"]:
		if not (x.get(field_name, null) is Dictionary):
			return "kamulaştırma.%s sözlük değil" % field_name
	if (x["snapshots"] as Array).size() != (x["parcel_ids"] as Array).size():
		return "kamulaştırma anlık görüntüleri alınan parsellerle aynı sayıda değil"
	for k in (x["parcel_ids"] as Array).size():
		var snap: Variant = x["snapshots"][k]
		if typeof(x["parcel_ids"][k]) != TYPE_INT or not (snap is Dictionary) \
				or snap.get("id", null) != x["parcel_ids"][k] \
				or typeof(snap.get("stage", null)) != TYPE_INT or typeof(snap.get("units", null)) != TYPE_INT \
				or typeof(snap.get("region", null)) != TYPE_STRING:
			return "kamulaştırma anlık görüntüsü geçersiz"
	return _resettlement_problem(x["resettlement"], int(x["households"])) if x.has("resettlement") else ""


## Yeniden iskân tahsis kaydı (T-065) iç tutarlılığı: `moves` [kaynak, hedef, hane > 0] (kaynak != hedef),
## rehoused = Σ moves + Σ served (T-067 bekleme listesinden sonradan verilenler), unplaced = Σ unplaced_by,
## rehoused + unplaced = yerinden edilen hane, partial <= rehoused, cost >= 0.
static func _resettlement_problem(r: Variant, households: int) -> String:
	if not (r is Dictionary):
		return "yeniden iskân kaydı sözlük değil"
	for field_name in ["rehoused", "unplaced", "partial", "cost", "residual_pm"]:
		if typeof(r.get(field_name, null)) != TYPE_INT or int(r[field_name]) < 0:
			return "yeniden iskân.%s negatif olmayan tamsayı değil" % field_name
	for field_name in ["unplaced_by", "effective"]:
		if not (r.get(field_name, null) is Dictionary):
			return "yeniden iskân.%s sözlük değil" % field_name
	if not (r.get("moves", null) is Array):
		return "yeniden iskân.moves dizi değil"
	var moved := 0
	for move: Variant in r["moves"]:
		if not (move is Array) or (move as Array).size() != 3 or typeof(move[0]) != TYPE_STRING \
				or typeof(move[1]) != TYPE_STRING or typeof(move[2]) != TYPE_INT or int(move[2]) <= 0 \
				or move[0] == move[1]:
			return "yeniden iskân satırı [kaynak, hedef, hane > 0] değil"
		moved += int(move[2])
	var unplaced := 0
	for code: Variant in r["unplaced_by"]:
		if typeof(code) != TYPE_STRING or typeof(r["unplaced_by"][code]) != TYPE_INT or int(r["unplaced_by"][code]) <= 0:
			return "yeniden iskân.unplaced_by satırı geçersiz"
		unplaced += int(r["unplaced_by"][code])
	for code: Variant in r["effective"]:
		if typeof(code) != TYPE_STRING or typeof(r["effective"][code]) != TYPE_INT or int(r["effective"][code]) < 0:
			return "yeniden iskân.effective satırı geçersiz"
	var served := _served_problem(r)
	if served < 0:
		return "yeniden iskân.served ya da weight_by geçersiz"
	moved += served
	if moved != int(r["rehoused"]) or unplaced != int(r["unplaced"]):
		return "yeniden iskân toplamları satırlarla uyuşmuyor"
	if int(r["rehoused"]) + int(r["unplaced"]) != households or int(r["partial"]) > int(r["rehoused"]):
		return "yeniden iskân hane toplamı yerinden edilenle uyuşmuyor"
	return ""


## Bekleme listesinden verilen evler (T-067): `served` [[tick >= 0, kaynak, hedef, hane > 0, sınıf 0/1, 0/1]...]
## ve `weight_by` {kod: negatif olmayan tamsayı}, ikisi de isteğe bağlı. Geçerliyse verilen toplam hane, değilse -1.
static func _served_problem(r: Dictionary) -> int:
	var total := 0
	if r.has("served"):
		if not (r["served"] is Array):
			return -1
		for row: Variant in r["served"]:
			if not (row is Array) or (row as Array).size() != 6 or typeof(row[0]) != TYPE_INT or int(row[0]) < 0 \
					or typeof(row[1]) != TYPE_STRING or typeof(row[2]) != TYPE_STRING or typeof(row[3]) != TYPE_INT \
					or int(row[3]) <= 0 or typeof(row[4]) != TYPE_INT or not [0, 1].has(int(row[4])) \
					or typeof(row[5]) != TYPE_INT or not [0, 1].has(int(row[5])):
				return -1
			total += int(row[3])
	if r.has("weight_by"):
		if not (r["weight_by"] is Dictionary):
			return -1
		for code: Variant in r["weight_by"]:
			if typeof(code) != TYPE_STRING or typeof(r["weight_by"][code]) != TYPE_INT or int(r["weight_by"][code]) < 0:
				return -1
	return total


static func _op_problem(op: Variant) -> String:
	if op is Dictionary and str(op.get("op", "")) == OP_RESTORE_PARCELS:
		if typeof(op.get("source_op", null)) != TYPE_INT or int(op["source_op"]) < 0:
			return "arazi kaynak işlemi geçersiz"
		return _land_ids_problem(op.get("parcel_ids", null))
	if op is Dictionary and str(op.get("op", "")) == OP_REMOVE_EDGE:  # yıkım satırının işlemi
		return "" if typeof(op.get("edge", null)) == TYPE_INT else "op kenar kimliği tamsayı değil"
	if not (op is Dictionary) or str(op.get("op", "")) != OP_ADD_ROAD:
		return "op add_road/remove_edge değil"
	if typeof(op.get("class", null)) != TYPE_STRING or typeof(op.get("width_dm", null)) != TYPE_INT:
		return "op sınıf/genişlik geçersiz"
	var pts: Variant = op.get("pts_cm", null)
	if not (pts is Array) or (pts as Array).size() < 2:
		return "op noktaları geçersiz"
	for pair: Variant in pts:
		if not (pair is Array) or (pair as Array).size() != 2 \
				or typeof(pair[0]) != TYPE_INT or typeof(pair[1]) != TYPE_INT:
			return "op noktası [x, z] tamsayı çifti değil"
	return ""


static func _land_ids_problem(ids: Variant) -> String:
	if not (ids is Array) or (ids as Array).is_empty():
		return "arazi parselleri boş ya da dizi değil"
	var previous := 0
	for id: Variant in ids:
		if typeof(id) != TYPE_INT or int(id) <= previous:
			return "arazi parselleri artan pozitif kimlik değil"
		previous = int(id)
	return ""


## Kaynak arazi, o anda alınmış ve DAHA ÖNCE yıkılmış yolun parselidir. Sonraki kamulaştırma yeni sahipliktir.
static func _land_reuse_problem(value: Dictionary) -> String:
	var works: Array = value["works"]
	var taken_from := {}
	var demolished := {}
	for i in works.size():
		var work: Dictionary = works[i]
		if is_demolition(work):
			demolished[int(work["target_command_id"])] = true
		elif is_land_reuse(work):
			var op: Dictionary = value["ops"][i]
			var source_op: Variant = work.get("source_op", null)
			if typeof(source_op) != TYPE_INT or int(source_op) < 0 or int(source_op) >= i \
					or source_op != op["source_op"]:
				return "arazi kaynak işlemi önceki bir yol değil"
			var source: Dictionary = works[int(source_op)]
			if not is_road_work(source) or not source.has("expropriation") \
					or not demolished.has(int(source["command_id"])) \
					or work.get("source_command_id", null) != source["command_id"]:
				return "arazi kaynağı yıkılmış kamulaştırmalı yol değil"
			var ids_problem := _land_ids_problem(work.get("parcel_ids", null))
			if not ids_problem.is_empty() or StateHash.of(work["parcel_ids"]) != StateHash.of(op["parcel_ids"]):
				return "arazi parselleri işlemle uyuşmuyor"
			for id: int in work["parcel_ids"]:
				if int(taken_from.get(id, -1)) != int(source_op):
					return "arazi parseli bu kaynakta alınmış değil ya da zaten açılmış"
				taken_from.erase(id)
		elif is_road_work(work) and work.has("expropriation"):
			for id: int in work["expropriation"]["parcel_ids"]:
				if taken_from.has(id):
					return "alınmış parsel yeniden alınamaz"
				taken_from[id] = i
	return ""


static func _hash_problem(h: Variant) -> String:
	return "" if typeof(h) == TYPE_STRING and not (h as String).is_empty() else "graf özeti boş"


static func _work_problem(work: Variant, index: int) -> String:
	if not (work is Dictionary):
		return "yol kaydı sözlük değil"
	for field_name in ["id", "command_id", "tick", "length_cm"]:
		if typeof(work.get(field_name, null)) != TYPE_INT:
			return "yol.%s tamsayı değil" % field_name
	if int(work["id"]) != index + 1 or int(work["command_id"]) < 1 or int(work["tick"]) < 0:
		return "yol kimliği/komut/tick geçersiz"
	if typeof(work.get("road_class", null)) != TYPE_STRING or not (work.get("region_units", null) is Dictionary):
		return "yol sınıfı/bölge birimleri geçersiz"
	for code: Variant in work["region_units"]:
		if typeof(code) != TYPE_STRING or typeof(work["region_units"][code]) != TYPE_INT:
			return "yol bölge birimi tamsayı değil"
	return _expropriation_problem(work["expropriation"]) if (work as Dictionary).has("expropriation") else ""
