class_name ReasonLatestCache
extends RefCounted
## B-042: "karar anahtarı + konu için en yeni gerekçe" artımlı önbelleği (facade-yerel, TÜRETİLMİŞ; durum/hash/kayıt
## dışı, sözleşme dışı). `lookup(state, decision, subjects)[konu]` == `reasons_for(konu)` içinden `decision_key ==
## decision` olanların en büyük id'lisi (yoksa anahtar yok). Eski yol her konu için tüm günlüğü tarar ve çevirir.
## Doğruluk `ReasonSubjectCache` ile aynı: günlük SONDAN eklenir, BAŞTAN budanır; son kimlik ilerleyince yalnız yeni
## kayıtlar `peek` ile işlenir; budanan kayıtlar okuma anında düşülür (budanmış kayıttan eski kayıt saklı olamaz).
## Anahtar: durum + günlük ÖRNEĞİ + karar + konu kümesi; günlük geriye giderse/ilk kimlik küçülürse atılır.

var _state: GameState
var _log: ReasonLog
var _key: String = ""
var _first: int = 0
var _last: int = 0
var _found: Dictionary = {}  # konu -> ReasonRecord


func lookup(state: GameState, decision: StringName, subjects: PackedStringArray) -> Dictionary:
	var log := state.reasons
	var key := "%s|%s" % [decision, ",".join(subjects)]
	if _state != state or _log != log or _key != key or log.last_id() < _last or log.first_id() < _first:
		reset()
		_state = state
		_log = log
		_key = key
	var first := log.first_id()
	for id in range(maxi(_last + 1, first), log.last_id() + 1):
		var rec := log.peek(id)
		if rec.is_empty() or str(rec["decision"]) != String(decision):
			continue
		var about := PackedStringArray(rec["subjects"])
		for subject in subjects:
			if str(rec["actor"]) == subject or about.has(subject):
				_found[subject] = ReasonAdapter.to_record(rec, first)
	_last = log.last_id()
	_first = first
	var out := {}
	for subject: String in _found:
		var record: ReasonRecord = _found[subject]
		if record.id >= first:
			out[subject] = record
	return out


func reset() -> void:
	_state = null
	_log = null
	_key = ""
	_first = 0
	_last = 0
	_found = {}
