class_name ReasonModel
extends RefCounted
## `ReasonRecord` -> gösterim modeli (SAF mantık, düğüm yok; T-021). SIM-12: sim'in kaydettiği neden gösterilir,
## UI neden UYDURMAZ; SIM-09: kayıt başına tek bir "iyilik" göstergesi değil, etken etken katkı.
##
## UI, kayıt değişmezini (`score == Σ trunc(değer×ağırlık/1000)`, `outcome positive <=> score >= threshold`)
## KENDİ hesaplar; tutmayan kayıt `issues` ile işaretlenir (veri hatası, sessiz kabul yok).
## v1.1 uzantı alanları (`summary_key/args`, `cause_refs`, `factor.direction`, `factor.trend`) varsa kullanılır,
## yoksa zarifçe düşer (`Object.get` null döner); v1.0 alanlarıyla tam çalışır.

const DIR_FOR := 1
const DIR_AGAINST := -1
const DIR_NEUTRAL := 0

const ISSUE_SCORE := &"score_mismatch"
const ISSUE_OUTCOME := &"outcome_mismatch"
const ISSUE_UNKNOWN_OUTCOME := &"unknown_outcome"
const ISSUE_SCORING := &"unsupported_scoring"
const ISSUE_DIRECTION := &"direction_mismatch"
const ISSUE_CHAIN := &"chain_self"


## Tek etken satırı.
class Row:
	extends RefCounted
	var name_key: StringName = &""
	var value: int = 0
	var weight: int = 0
	var contribution: int = 0
	## DIR_FOR / DIR_AGAINST / DIR_NEUTRAL; v1.1 `direction` yoksa value×weight işaretinden.
	var direction: int = DIR_NEUTRAL
	var is_estimate: bool = false
	## weight == 0: yalnız gösterim (karara katılmaz, political-events §3 / characters-npc §6.2).
	var is_info_only: bool = false
	var source_ref: StringName = &""
	## Çubuk uzunluğu, −1 … +1 (kaydın en büyük katkısına göre); sıfır olmayan etkenin görünür payı vardır.
	var bar_fraction: float = 0.0
	var has_trend: bool = false
	var trend: int = 0

var record: ReasonRecord = null
## |katkı| azalan, bilgi-yalnız etkenler sonda; eşitlikte kayıt sırası.
var rows: Array[Row] = []
var computed_score: int = 0
## Kayıtlı toplam − eşik (işaretli).
var margin: int = 0
## `[{code: StringName, args: Dictionary}]` — boşsa kayıt tutarlı.
var issues: Array[Dictionary] = []
## v1.1 `summary_key/args` varsa (sim cümlesi); yoksa boş.
var summary_key: StringName = &""
var summary_args: Dictionary = {}
## v1.1 `cause_refs` (zincir dışı neden varlıkları); yoksa boş.
var cause_refs: PackedStringArray = PackedStringArray()
## En çok etkileyen etkenlerin ad anahtarları (en çok `top_n`, bilgi-yalnız hariç).
var top_names: Array[StringName] = []


static func from_record(rec: ReasonRecord, top_n: int = 3) -> ReasonModel:
	var m := ReasonModel.new()
	m.record = rec
	m._build_rows()
	m._verify()
	m.margin = rec.score - rec.threshold
	for r in m.rows:
		if m.top_names.size() >= top_n:
			break
		if not r.is_info_only and r.contribution != 0:
			m.top_names.append(r.name_key)
	m._read_extensions()
	return m


func is_consistent() -> bool:
	return issues.is_empty()


func has_issue(code: StringName) -> bool:
	for issue in issues:
		if issue["code"] == code:
			return true
	return false


## Eşik ve toplam için ölçek: sıfırı, toplamı ve eşiği kapsayan aralık (+%10 pay). Meter ve testler kullanır.
func scale_range() -> Vector2:
	var low := mini(0, mini(record.score, record.threshold))
	var high := maxi(0, maxi(record.score, record.threshold))
	if high == low:
		high = low + SimContract.FIXED_SCALE
	var pad := int(ceilf(float(high - low) * 0.1))
	return Vector2(float(low - (pad if low < 0 else 0)), float(high + pad))


## `value`'nun [0,1] aralığındaki yeri (scale_range'e göre).
static func position_in(value: float, range_in: Vector2) -> float:
	var span := range_in.y - range_in.x
	if span <= 0.0:
		return 0.0
	return clampf((value - range_in.x) / span, 0.0, 1.0)


func _build_rows() -> void:
	var raw: Array[Row] = []
	var max_abs := 1
	for f in record.factors:
		var row := Row.new()
		row.name_key = f.name_key
		row.value = f.value
		row.weight = f.weight
		row.contribution = SimContract.contribution(f.value, f.weight)
		row.is_estimate = f.is_estimate
		row.source_ref = f.source_ref
		row.is_info_only = f.weight == 0
		row.direction = _direction_of(f.value, f.weight)
		var explicit: Variant = f.get(&"direction")
		if explicit is int and not row.is_info_only:
			row.direction = signi(explicit)
		var trend: Variant = f.get(&"trend")
		if trend is int:
			row.has_trend = true
			row.trend = signi(trend)
		raw.append(row)
		if not row.is_info_only:
			max_abs = maxi(max_abs, absi(row.contribution))
	for row in raw:
		if row.is_info_only or row.direction == DIR_NEUTRAL:
			continue
		var frac := float(absi(row.contribution)) / float(max_abs)
		# Sıfır olmayan etkenin kaybolmaması için küçük bir alt pay.
		row.bar_fraction = float(row.direction) * maxf(frac, 0.02)
	# Kararlı sıralama: |katkı| azalan, bilgi-yalnız sonda, eşitlikte kayıt sırası.
	var indexed: Array[Dictionary] = []
	for i in raw.size():
		indexed.append({"row": raw[i], "i": i})
	indexed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: Row = a["row"]
		var rb: Row = b["row"]
		if ra.is_info_only != rb.is_info_only:
			return rb.is_info_only
		if absi(ra.contribution) != absi(rb.contribution):
			return absi(ra.contribution) > absi(rb.contribution)
		return int(a["i"]) < int(b["i"]))
	for entry in indexed:
		rows.append(entry["row"])


func _verify() -> void:
	computed_score = 0
	for f in record.factors:
		computed_score += SimContract.contribution(f.value, f.weight)
	if record.scoring != ReasonRecord.SCORING_LINEAR:
		issues.append({"code": ISSUE_SCORING, "args": {"value": String(record.scoring)}})
	elif record.score != computed_score:
		issues.append({"code": ISSUE_SCORE, "args": {"recorded": record.score, "computed": computed_score}})
	if record.outcome != ReasonRecord.OUTCOME_POSITIVE and record.outcome != ReasonRecord.OUTCOME_NEGATIVE:
		issues.append({"code": ISSUE_UNKNOWN_OUTCOME, "args": {"value": String(record.outcome)}})
	elif record.scoring == ReasonRecord.SCORING_LINEAR:
		var expected := ReasonRecord.OUTCOME_POSITIVE if computed_score >= record.threshold \
			else ReasonRecord.OUTCOME_NEGATIVE
		if record.outcome != expected:
			issues.append({"code": ISSUE_OUTCOME, "args": {
				"outcome": record.outcome, "computed": computed_score, "threshold": record.threshold}})
	if record.id != SimContract.NO_ID and record.parent_ids.has(record.id):
		issues.append({"code": ISSUE_CHAIN, "args": {}})
	for r in rows:
		if not r.is_info_only and r.direction != DIR_NEUTRAL and r.direction != _direction_of(r.value, r.weight) \
				and _direction_of(r.value, r.weight) != DIR_NEUTRAL:
			issues.append({"code": ISSUE_DIRECTION, "args": {"factor": r.name_key}})


func _read_extensions() -> void:
	var key: Variant = record.get(&"summary_key")
	if (key is StringName or key is String) and not String(key).is_empty():
		summary_key = StringName(String(key))
		var args: Variant = record.get(&"summary_args")
		summary_args = SimContract.to_args(args) if args is Dictionary else {}
	var causes: Variant = record.get(&"cause_refs")
	if causes is Array or causes is PackedStringArray:
		cause_refs = SimContract.to_string_array(causes)


static func _direction_of(value: int, weight: int) -> int:
	return signi(value * weight)
