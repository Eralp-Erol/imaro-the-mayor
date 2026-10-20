class_name ReasonLog
extends RefCounted
## Gerekçe kaydı altyapısı (T-002, T-027 ölçüt 1, SIM-12, ADR-0002 Karar 7, ADR-0005 ReasonRecord). Her aktör kararı
## {aktör, karar, faktörler, eşik} kaydı üretir; UI ve testler buradan okur. Kayıt, sözleşme `ReasonRecord`'una
## KAYIPSIZ eşlenir (adaptör: src/sim/facade/reason_adapter.gd): sim tarafında kayan nokta yoktur.
##
## Kayıt alanları:
##   id           1'den başlar, artar; budanınca da tekrar kullanılmaz (0 = "kimlik yok").
##   tick         kararın verildiği tick.
##   actor        aktör referans dizgesi `actor.<tür>.<n>` (n >= 1), StringName.
##   decision     karar anahtarı (örn. `decision.investor.develop`), StringName.
##   factors      [{name, value, weight, is_estimate, source_ref}]: value/weight 1000 ölçekli TAMSAYI
##                (SimContract.FIXED_SCALE; 0.42 -> 420); weight yoksa FIXED_SCALE (= 1.0). Float kabul edilmez.
##   threshold    eşik, aynı ölçekte tamsayı.
##   score        Σ SimContract.contribution(value, weight) (sıfıra doğru kesen doğrusal toplam; log HESAPLAR).
##   outcome      &"positive" <=> score >= threshold (karardaki eylem GERÇEKLEŞTİ), aksi &"negative"
##                (SIM-07: eylem gerçekleşmedi).
##                Log HESAPLAR: çağıran tutarsız puan/sonuç veremez (ReasonRecord değişmezi yapıdan gelir).
##   code         kısa makine-okur gerekçe kodu (boş olabilir; ör. &"yield_below_threshold").
##   subjects     ilgili varlık referansları `<tür>.<n>` (PackedStringArray; `parcel.12`, `command.7`).
##   parent_ids   nedensellik zinciri: bu karardan ÖNCE kaydedilmiş gerekçelerin id'leri (PackedInt64Array).
## Kapasite aşılınca en eski kayıtlar budanır (kapasite `GameState.config.reason_log_capacity`, kayıtla taşınır).

const OUTCOME_POSITIVE := &"positive"
const OUTCOME_NEGATIVE := &"negative"
const _ACTOR_PREFIX := "actor."

var _records: Array = []
var _next_id: int = 1
var _capacity: int = 1


func _init(capacity: int = 1) -> void:
	_capacity = maxi(1, capacity)


func size() -> int:
	return _records.size()


## Kaydı ekler ve id'sini (>= 1) döndürür; geçersiz girdide push_error + -1 (kayıt eklenmez, kimlik tüketilmez).
func record(tick: int, actor: Variant, decision: Variant, factors: Array, threshold: Variant,
		code: StringName = &"", subjects: PackedStringArray = PackedStringArray(),
		parent_ids: PackedInt64Array = PackedInt64Array()) -> int:
	var error := _validate(actor, decision, factors, threshold, subjects, parent_ids, _next_id)
	if not error.is_empty():
		push_error("ReasonLog: %s" % error)
		return -1
	var normalized: Array = []
	var score := 0
	for factor: Dictionary in factors:
		var weight: int = factor.get("weight", SimContract.FIXED_SCALE)
		normalized.append({
			"name": StringName(str(factor["name"])),
			"value": factor["value"],
			"weight": weight,
			"is_estimate": bool(factor.get("is_estimate", false)),
			"source_ref": StringName(str(factor.get("source_ref", ""))),
		})
		score += SimContract.contribution(factor["value"], weight)
	var id := _next_id
	_next_id += 1
	_records.append({
		"id": id, "tick": tick, "actor": StringName(str(actor)), "decision": StringName(str(decision)),
		"factors": normalized, "threshold": threshold, "code": code, "score": score,
		"outcome": OUTCOME_POSITIVE if score >= int(threshold) else OUTCOME_NEGATIVE,
		"subjects": subjects.duplicate(), "parent_ids": parent_ids.duplicate(),
	})
	while _records.size() > _capacity:
		_records.pop_front()
	return id


## Saklanan en eski / en yeni gerekçe id'si; kayıt yoksa 0.
func first_id() -> int:
	return 0 if _records.is_empty() else int((_records[0] as Dictionary)["id"])


func last_id() -> int:
	return 0 if _records.is_empty() else int((_records[_records.size() - 1] as Dictionary)["id"])


## Kayıt kopyası; yoksa (veya budanmışsa) boş sözlük.
func by_id(id: int) -> Dictionary:
	for i in range(_records.size() - 1, -1, -1):
		var rec: Dictionary = _records[i]
		if rec["id"] == id:
			return rec.duplicate(true)
		if rec["id"] < id:
			break
	return {}


## Süzgeç anahtarları (hepsi isteğe bağlı, VE ile birleşir): actor, decision, code, from_tick, to_tick (dahil),
## subject (kaydın `subjects` listesinde geçen ya da aktörü olan referans; sözleşme `ReasonRecord.is_about`).
## Sonuç eskiden yeniye sıralı KOPYALAR dizisidir.
func find(filter: Dictionary) -> Array:
	var out: Array = []
	for rec: Dictionary in _records:
		if _matches(rec, filter):
			out.append(rec.duplicate(true))
	return out


## Tek geçişte konu → gerekçe id'leri: `wanted` anahtarları aranan konu referansları (String); her konu için en yeni
## `limit` gerekçenin id'si, artan sırada (kayıtları kopyalamaz). Facade `ParcelView.reason_ids` için kullanır.
func subject_index(wanted: Dictionary, limit: int) -> Dictionary:
	var out := {}
	for rec: Dictionary in _records:
		for subject in rec["subjects"] as PackedStringArray:
			if not wanted.has(subject):
				continue
			var ids: PackedInt64Array = out.get(subject, PackedInt64Array())
			ids.append(rec["id"])
			if ids.size() > limit:
				ids = ids.slice(ids.size() - limit)
			out[subject] = ids
	return out


## `find` ile eşleşen en yeni kayıt; yoksa boş sözlük.
func latest(filter: Dictionary) -> Dictionary:
	for i in range(_records.size() - 1, -1, -1):
		if _matches(_records[i], filter):
			return (_records[i] as Dictionary).duplicate(true)
	return {}


func to_dict() -> Dictionary:
	return {"capacity": _capacity, "next_id": _next_id, "records": _records.duplicate(true)}


## Hash için kopyasız görünüm (salt okunur kullanın).
func to_dict_view() -> Dictionary:
	return {"capacity": _capacity, "next_id": _next_id, "records": _records}


static func from_dict(data: Dictionary) -> ReasonLog:
	var result := ReasonLog.new(int(data["capacity"]))
	result._next_id = int(data["next_id"])
	result._records = (data["records"] as Array).duplicate(true)
	return result


## Biçim hatası metni; geçerliyse "".
static func validate_dict(data: Variant) -> String:
	if not (data is Dictionary):
		return "reasons bölümü sözlük değil"
	for key in ["capacity", "next_id"]:
		if typeof(data.get(key, null)) != TYPE_INT:
			return "reasons.%s int değil" % key
	if int(data["next_id"]) < 1:
		return "reasons.next_id 1'den küçük"
	if not (data.get("records", null) is Array):
		return "reasons.records dizi değil"
	for rec: Variant in data["records"]:
		var problem := _record_problem(rec, int(data["next_id"]))
		if not problem.is_empty():
			return problem
	return ""


static func _record_problem(rec: Variant, next_id: int) -> String:
	if not (rec is Dictionary):
		return "reasons.records öğesi sözlük değil"
	for key in ["id", "tick", "threshold", "score"]:
		if typeof(rec.get(key, null)) != TYPE_INT:
			return "reasons kaydında %s int değil" % key
	if int(rec["id"]) < 1 or int(rec["id"]) >= next_id:
		return "reasons kaydında id aralık dışı"
	for key in ["actor", "decision", "factors", "code", "outcome", "subjects", "parent_ids"]:
		if not rec.has(key):
			return "reasons kaydında %s yok" % key
	if rec["outcome"] != OUTCOME_POSITIVE and rec["outcome"] != OUTCOME_NEGATIVE:
		return "reasons kaydında outcome geçersiz"
	if typeof(rec["subjects"]) != TYPE_PACKED_STRING_ARRAY or typeof(rec["parent_ids"]) != TYPE_PACKED_INT64_ARRAY:
		return "reasons kaydında subjects/parent_ids türü geçersiz"
	if not (rec["factors"] is Array):
		return "reasons kaydında factors dizi değil"
	for factor: Variant in rec["factors"]:
		if not (factor is Dictionary) or typeof(factor.get("value", null)) != TYPE_INT \
				or typeof(factor.get("weight", null)) != TYPE_INT:
			return "reasons faktöründe value/weight int değil"
	return ""


func _matches(rec: Dictionary, filter: Dictionary) -> bool:
	if filter.has("actor") and not _same(rec["actor"], filter["actor"]):
		return false
	if filter.has("decision") and not _same(rec["decision"], filter["decision"]):
		return false
	if filter.has("code") and not _same(rec["code"], filter["code"]):
		return false
	return _in_tick_range(rec, filter) and _about_subject(rec, filter)


static func _in_tick_range(rec: Dictionary, filter: Dictionary) -> bool:
	if filter.has("from_tick") and rec["tick"] < int(filter["from_tick"]):
		return false
	return not (filter.has("to_tick") and rec["tick"] > int(filter["to_tick"]))


static func _about_subject(rec: Dictionary, filter: Dictionary) -> bool:
	if not filter.has("subject"):
		return true
	var wanted := str(filter["subject"])
	return (rec["subjects"] as PackedStringArray).has(wanted) or str(rec["actor"]) == wanted


## String ile StringName eşit sayılır; int yalnız int ile; türler uyuşmazsa false (Variant != hata vermesin).
static func _same(a: Variant, b: Variant) -> bool:
	var a_text := typeof(a) == TYPE_STRING or typeof(a) == TYPE_STRING_NAME
	var b_text := typeof(b) == TYPE_STRING or typeof(b) == TYPE_STRING_NAME
	if a_text and b_text:
		return str(a) == str(b)
	if typeof(a) == TYPE_INT and typeof(b) == TYPE_INT:
		return a == b
	return false


static func _is_name(value: Variant) -> bool:
	return (typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME) and not str(value).is_empty()


## `<tür>.<n>` biçiminde geçerli referans mı (n >= 1)?
static func _is_ref(value: String) -> bool:
	var parsed := SimContract.parse_ref(StringName(value))
	return not String(parsed["kind"]).is_empty() and int(parsed["id"]) >= 1


static func _validate(actor: Variant, decision: Variant, factors: Array, threshold: Variant,
		subjects: PackedStringArray, parent_ids: PackedInt64Array, next_id: int) -> String:
	if not _is_name(actor) or not str(actor).begins_with(_ACTOR_PREFIX) or not _is_ref(str(actor)):
		return "actor must be an actor ref 'actor.<kind>.<n>' (n >= 1)"
	if not _is_name(decision):
		return "decision must be a non-empty String/StringName"
	if typeof(threshold) != TYPE_INT:
		return "threshold must be an int (fixed-point, scale %d)" % SimContract.FIXED_SCALE
	for i in factors.size():
		var factor: Variant = factors[i]
		if not (factor is Dictionary) or not _is_name(factor.get("name", null)):
			return "factor[%d] needs a non-empty 'name'" % i
		if typeof(factor.get("value", null)) != TYPE_INT:
			return "factor[%d] 'value' must be an int (fixed-point, scale %d)" % [i, SimContract.FIXED_SCALE]
		if factor.has("weight") and typeof(factor["weight"]) != TYPE_INT:
			return "factor[%d] 'weight' must be an int (fixed-point, scale %d)" % [i, SimContract.FIXED_SCALE]
	for subject in subjects:
		if not _is_ref(subject):
			return "subjects must be refs '<kind>.<n>'"
	for parent in parent_ids:
		if parent < 1 or parent >= next_id:
			return "parent_ids must refer to earlier reasons (1 <= id < %d)" % next_id
	return ""
