class_name LibraryGate
extends RefCounted
## Çalışma zamanı onay kapısı (T-062 A1, ADR-0006 §2.1b). Oyun, kütüphane kimliğini YALNIZ buradan alır: kapı
## `data/library/game_*.json` oyun tablolarındaki (derleme kapısından geçmiş: approved + hash eşleşen) kimlikleri tanır;
## başka her kimlik (rejected, proposed, bilinmeyen) REDDEDİLİR: kayıt/yol döndürülmez, `unapproved_ids` güncellenir,
## `denial_log` ve (açıksa) `push_error` ile iz bırakılır. Sessiz geçiş yok.
##
## Saf veri katmanı: RefCounted, node/autoload/zaman/RNG yok, GLB/PNG YÜKLEMEZ (yalnız yol verir; yüklemek çağıranın işi
## ve yalnız kapıdan dönen yolla olur). Sıra deterministiktir: tablo sırası (buildings, ground), tablo içi dosya sırası.
## Katalog (`catalog.json`) ikinci kilittir: tablodaki kimlik katalogda `approved` değilse kabul edilmez ve ret nedeni
## (`rejected`/`proposed`/`unknown_id`) katalogdan okunur. Yol verilen katalog okunamıyorsa kapı KAPALI kalır
## (fail-closed).
## Asset hash'i çalışma zamanında denetlenmez (dışa aktarımda kaynak yok): `verify full` içindeki doğrulayıcı denetler.

const CATALOG_PATH := "res://data/library/catalog.json"
const GAME_TABLE_PATHS := ["res://data/library/game_buildings.json", "res://data/library/game_ground.json"]
const FORMAT := "imaro-game-set/1"
## Bitki + sokak donatısı oyun tabloları (T-062 B0). Varsayılan kapıya EKLENMEZ (bina/zemin tüketicileri etkilenmez);
## bitki yerleşimi `load_plants()` ile kendi kapısını kurar.
const PLANT_TABLE_PATHS := ["res://data/library/game_plants.json", "res://data/library/game_furniture.json"]
## Tablo adı -> kayıt dizisi anahtarı. Bilinmeyen tablo adı reddedilir.
const TABLE_RECORD_KEYS := {"buildings": "modules", "ground": "layers", "vegetation": "plants",
		"furniture": "items"}
const LOD_ORDER := ["LOD0", "LOD1", "PROXY"]

const REASON_REJECTED := "rejected"
const REASON_PROPOSED := "proposed"
const REASON_UNKNOWN := "unknown_id"
const REASON_NOT_IN_GAME_SET := "not_in_game_set"
const REASON_EMPTY_ID := "empty_id"

## false ise ret/yükleme hatası `push_error` yazmaz (testler; kayıt yine tutulur).
var report_errors: bool = true
## Yükleme hataları (bozuk/eksik JSON, şema, çakışma). Boşsa kapı sağlıklı.
var load_errors: PackedStringArray = PackedStringArray()
## Reddedilen DISTINCT kimlikler, ilk istek sırasıyla (sayaç = `.size()`).
var unapproved_ids: PackedStringArray = PackedStringArray()
## Reddedilen istek sayısı (aynı kimliğin tekrarı dahil) / verilen istek sayısı.
var denied_requests: int = 0
var granted_requests: int = 0
## Her ret için {id, reason, via}.
var denial_log: Array[Dictionary] = []

var _catalog_loaded: bool = false
## Katalog kimliği -> approval ("approved"/"rejected"/"proposed"/...).
var _catalog_status: Dictionary = {}
## Onaylı kimlik -> kayıt (tablo girdisi), ve ekleme sırası.
var _records: Dictionary = {}
var _order: PackedStringArray = PackedStringArray()
var _table_of: Dictionary = {}
var _tables_loaded: PackedStringArray = PackedStringArray()
## Tabloların kendi `unapproved` bölümleri: kimlik -> neden; sayaç tablo başına.
var _table_excluded: Dictionary = {}
var _table_excluded_count: int = 0


## Varsayılan: katalog + iki oyun tablosu. Hata varsa `load_errors` dolu ve ilgili kimlikler kapalı.
static func load_default() -> LibraryGate:
	var gate := LibraryGate.new()
	gate.load_game_tables(PackedStringArray(GAME_TABLE_PATHS), CATALOG_PATH)
	return gate


## Bitki + donatı tabloları ve katalog (T-062 B0): bitki/donatı kimlikleri yalnız bu kapıdan alınır.
static func load_plants() -> LibraryGate:
	var gate := LibraryGate.new()
	gate.load_game_tables(PackedStringArray(PLANT_TABLE_PATHS), CATALOG_PATH)
	return gate


## Katalog (boş yol = çapraz denetim yok) sonra tablolar. Hepsi hatasızsa true.
func load_game_tables(table_paths: PackedStringArray, catalog_path: String = "") -> bool:
	var ok := true
	if not catalog_path.is_empty():
		var catalog_text := _read_text(catalog_path)
		ok = load_catalog_text(catalog_text, catalog_path) and ok
	for path in table_paths:
		ok = add_table_text(_read_text(path), path) and ok
	return ok


func load_catalog_text(text: String, source: String) -> bool:
	var data: Variant = _parse(text, source)
	if not (data is Dictionary):
		return false
	var entries: Variant = (data as Dictionary).get("entries")
	if not (entries is Array):
		return _fail("%s: 'entries' dizisi yok" % source)
	var status: Dictionary = {}
	for entry in entries as Array:
		if not (entry is Dictionary) or not ((entry as Dictionary).get("id") is String):
			return _fail("%s: geçersiz katalog girdisi" % source)
		var d := entry as Dictionary
		status[str(d["id"])] = str(d.get("approval", ""))
	_catalog_status = status
	_catalog_loaded = true
	return true


## Bir oyun tablosunu kabul eder. Herhangi bir şema/çakışma hatasında tablonun HİÇBİR kimliği kabul edilmez.
func add_table_text(text: String, source: String) -> bool:
	var data: Variant = _parse(text, source)
	if not (data is Dictionary):
		return false
	var staged := _stage_table(data as Dictionary, source)
	if staged.has("error"):
		return _fail(str(staged["error"]))
	var table_name := str(staged["name"])
	var records: Dictionary = staged["records"]
	for id in staged["order"] as PackedStringArray:
		_records[id] = records[id]
		_table_of[id] = table_name
		_order.append(id)
	_tables_loaded.append(table_name)
	var ex_ids: Dictionary = (staged["excluded"] as Dictionary)["ids"]
	for ex_id in ex_ids:
		_table_excluded[ex_id] = ex_ids[ex_id]
	_table_excluded_count += ex_ids.size()
	return true


## Saf sorgu: sayaç/iz YOK.
func is_approved(id: String) -> bool:
	return _records.has(id)


## Kimlik kapıdan geçerse tablo kaydının kopyasını, geçmezse BOŞ sözlük döndürür (ret sayılır ve izlenir).
func request(id: String) -> Dictionary:
	if _records.has(id):
		granted_requests += 1
		return (_records[id] as Dictionary).duplicate(true)
	_deny(id, "request")
	return {}


## Kapıdan geçen kimliğin asset yolları (bina: LOD0, LOD1, PROXY, sonra diğer LOD'lar sıralı; zemin: png).
## Onaysız -> boş.
## Yalnız yol verir, hiçbir şey yüklemez.
func request_paths(id: String) -> PackedStringArray:
	var paths := PackedStringArray()
	if not _records.has(id):
		_deny(id, "request_paths")
		return paths
	granted_requests += 1
	var rec := _records[id] as Dictionary
	if rec.get("lods") is Dictionary:
		var lods := rec["lods"] as Dictionary
		var names: Array = LOD_ORDER.duplicate()
		var extra: Array = []
		for key in lods:
			if not names.has(key):
				extra.append(key)
		extra.sort()
		names.append_array(extra)
		for lod_name in names:
			if lods.has(lod_name) and (lods[lod_name] is Dictionary):
				var glb := str((lods[lod_name] as Dictionary).get("glb", ""))
				if not glb.is_empty():
					paths.append(glb)
	elif rec.has("png"):
		paths.append(str(rec["png"]))
	return paths


func approved_ids() -> PackedStringArray:
	return _order.duplicate()


func approved_ids_of(table_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in _order:
		if _table_of[id] == table_name:
			out.append(id)
	return out


## Tablo adı ("buildings"/"ground") ya da "" (bilinmiyor).
func table_of(id: String) -> String:
	return str(_table_of.get(id, ""))


## Oyun tablolarının KENDİ `unapproved` bölümlerinin toplamı (A0 derleme kapısının dışladıkları).
func table_excluded_count() -> int:
	return _table_excluded_count


## Dışlanan kimlikler (tablo `unapproved.entries`), sıralı.
func table_excluded_ids() -> PackedStringArray:
	var ids: Array = _table_excluded.keys()
	ids.sort()
	return PackedStringArray(ids)


## Toplam dışlanan DISTINCT kimlik: tablo dışlananları + çalışma zamanında reddedilenler (kesişim bir kez sayılır).
func excluded_total() -> int:
	var seen: Dictionary = _table_excluded.duplicate()
	for id in unapproved_ids:
		seen[id] = true
	return seen.size()


func stats() -> Dictionary:
	return {
		"approved": _order.size(),
		"table_excluded": _table_excluded_count,
		"excluded_total": excluded_total(),
		"unapproved_ids": unapproved_ids.size(),
		"denied_requests": denied_requests,
		"granted_requests": granted_requests,
		"load_errors": load_errors.size(),
		"tables": _tables_loaded.duplicate(),
		"catalog_cross_check": _catalog_loaded,
	}


## Katalogdan ret nedeni: rejected / proposed / unknown_id, katalog yüklenmediyse ya da kimlik onaylıysa
## (tabloda yok) not_in_game_set.
func deny_reason(id: String) -> String:
	if id.is_empty():
		return REASON_EMPTY_ID
	if _catalog_loaded:
		return _catalog_reason(id)
	return REASON_NOT_IN_GAME_SET


func _catalog_reason(id: String) -> String:
	if not _catalog_status.has(id):
		return REASON_UNKNOWN
	match str(_catalog_status[id]):
		"rejected":
			return REASON_REJECTED
		"proposed":
			return REASON_PROPOSED
		"approved":
			return REASON_NOT_IN_GAME_SET
		_:
			return REASON_UNKNOWN


func _deny(id: String, via: String) -> void:
	denied_requests += 1
	var reason := deny_reason(id)
	denial_log.append({"id": id, "reason": reason, "via": via})
	if not unapproved_ids.has(id):
		unapproved_ids.append(id)
	if report_errors:
		push_error("LibraryGate: onaysız kimlik '%s' reddedildi (%s, %s)" % [id, reason, via])


func _fail(message: String) -> bool:
	load_errors.append(message)
	if report_errors:
		push_error("LibraryGate: %s" % message)
	return false


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _parse(text: String, source: String) -> Variant:
	if text.strip_edges().is_empty():
		_fail("%s: dosya yok ya da boş" % source)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		_fail("%s: JSON bozuk (satır %d: %s)" % [source, json.get_error_line(), json.get_error_message()])
		return null
	if not (json.data is Dictionary):
		_fail("%s: kök bir sözlük değil" % source)
		return null
	return json.data


## Doğrular ve hazırlar (durumu DEĞİŞTİRMEZ): {name, records, order, excluded} ya da {error}.
func _stage_table(table: Dictionary, source: String) -> Dictionary:
	var table_name := str(table.get("table", ""))
	var problem := ""
	if str(table.get("format", "")) != FORMAT:
		problem = "%s: format '%s' != '%s'" % [source, str(table.get("format", "")), FORMAT]
	elif not TABLE_RECORD_KEYS.has(table_name):
		problem = "%s: bilinmeyen tablo '%s'" % [source, table_name]
	elif _tables_loaded.has(table_name):
		problem = "%s: '%s' tablosu zaten yüklü" % [source, table_name]
	elif not (table.get(str(TABLE_RECORD_KEYS[table_name])) is Array):
		problem = "%s: '%s' dizisi yok" % [source, str(TABLE_RECORD_KEYS[table_name])]
	if not problem.is_empty():
		return {"error": problem}
	var excluded := _read_excluded(table, source)
	if excluded.has("error"):
		return excluded
	var records: Dictionary = {}
	var order := PackedStringArray()
	for rec in table[str(TABLE_RECORD_KEYS[table_name])] as Array:
		problem = _check_record(rec, records, source, excluded)
		if not problem.is_empty():
			return {"error": problem}
		var id := str((rec as Dictionary)["id"])
		records[id] = (rec as Dictionary).duplicate(true)
		order.append(id)
	# Katalog ikinci kilit: tabloda olup katalogda approved olmayan kimlik tabloyu tümden reddettirir.
	if _catalog_loaded:
		for id in order:
			if str(_catalog_status.get(id, "")) != "approved":
				return {"error": "%s: '%s' katalogda approved değil (%s)" % [source, id, _catalog_reason(id)]}
	return {"name": table_name, "records": records, "order": order, "excluded": excluded}


## Tablonun `unapproved` bölümü: {ids: {id: reason}, count} ya da {error}. Bölüm yoksa boş sayılır.
func _read_excluded(table: Dictionary, source: String) -> Dictionary:
	var ids: Dictionary = {}
	if not table.has("unapproved"):
		return {"ids": ids, "count": 0}
	var section: Variant = table["unapproved"]
	if not (section is Dictionary) or not ((section as Dictionary).get("entries") is Array):
		return {"error": "%s: 'unapproved.entries' geçersiz" % source}
	for entry in (section as Dictionary)["entries"] as Array:
		if not (entry is Dictionary) or str((entry as Dictionary).get("id", "")).is_empty():
			return {"error": "%s: 'unapproved' girdisinde kimlik yok" % source}
		ids[str((entry as Dictionary)["id"])] = str((entry as Dictionary).get("reason", ""))
	var count: Variant = (section as Dictionary).get("count")
	if not (count is float or count is int) or int(count) != ids.size():
		return {"error": "%s: 'unapproved.count' girdi sayısıyla uyuşmuyor" % source}
	return {"ids": ids, "count": ids.size()}


## "" = geçerli; aksi halde hata iletisi.
func _check_record(rec: Variant, staged: Dictionary, source: String, excluded: Dictionary) -> String:
	if not (rec is Dictionary) or not ((rec as Dictionary).get("id") is String):
		return "%s: kayıtta metin 'id' yok" % source
	var id := str((rec as Dictionary)["id"])
	if id.is_empty():
		return "%s: boş kimlik" % source
	if staged.has(id) or _records.has(id):
		return "%s: yinelenen kimlik '%s'" % [source, id]
	var ex_ids: Dictionary = excluded["ids"]
	if ex_ids.has(id):
		return "%s: '%s' hem kabul hem 'unapproved' listesinde" % [source, id]
	return ""
