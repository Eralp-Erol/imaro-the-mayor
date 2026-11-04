class_name ReasonSubjectCache
extends RefCounted
## `parcel_views` gerekçe dizini önbelleği (2026-11-01, ADR önerisi §2.3). Eski yol her çağrıda TÜM gerekçe günlüğünü
## `ReasonLog.subject_index` ile tarıyordu (kapasite 1000). Bu önbellek aynı sonucu verir:
## `lookup(state, wanted, limit)` == `state.reasons.subject_index(wanted, limit)` (konu başına en yeni `limit` id,
## artan; BİT-BİT aynı). TÜRETİLMİŞTİR: durum/hash/kayıt dışı, facade-yerel; yalnız ana iş parçacığında kullanılır.
##
## Doğruluk: günlük yalnız SONDAN eklenir ve BAŞTAN budanır (kimlikler artar, tekrar kullanılmaz). Bu yüzden
##   * önbellek TÜM konuların dizinidir ve günlükle birlikte artımlı büyür: son kimlik ilerleyince yalnız YENİ kayıtlar
##     (`peek`, kopyasız) işlenir (O(yeni kayıt)); ilk kurulum günlüğü bir kez gezer;
##   * anahtar: durum + günlük ÖRNEĞİ (referans tutulur, kimlik yeniden kullanımı olamaz) + limit; ayrıca günlüğün
##     son kimliği geriye giderse ya da ilk kimliği küçülürse (günlük başka bir geçmişe geçti) önbellek ATILIR;
##   * budanan eski kimlikler konu listesinden okuma anında düşülür (liste artan: `bsearch`). Listeden `limit` aşımı
##     için atılanlar listedekilerin hepsinden eskidir; onlar budanmadan listedekiler budanamaz => sonuç aynı;
##   * hiç sorulmayan eski konular birikmesin diye dizin günlük boyutunun çok üstüne çıkarsa sıfırdan kurulur.

const _SLACK_FACTOR := 8  # konu sayısı > bu x günlük boyutu (+ _SLACK_MIN) olunca yeniden kur
const _SLACK_MIN := 64

var _state: GameState
var _log: ReasonLog
var _limit: int = -1
var _first: int = 0
var _last: int = 0  # dizinin işlediği son kimlik (0 = hiç)
var _refs: Dictionary = {}  # konu referansı -> PackedInt64Array (artan; budanmış kimlikler tembelce düşülür)


## `wanted` içindeki her konu için {konu: PackedInt64Array}; günlükte yoksa boş. Diziler KOPYADIR.
func lookup(state: GameState, wanted: Dictionary, limit: int) -> Dictionary:
	var log := state.reasons
	if _state != state or _log != log or _limit != limit or log.last_id() < _last or log.first_id() < _first \
			or _refs.size() > _SLACK_FACTOR * log.size() + _SLACK_MIN:
		reset()
		_state = state
		_log = log
		_limit = limit
	_add_new_records()
	_first = log.first_id()
	var out := {}
	for ref in wanted:
		var ids: PackedInt64Array = _refs.get(ref, PackedInt64Array())
		if not ids.is_empty() and ids[0] < _first:  # budanmış eski kimlikleri düş
			ids = ids.slice(ids.bsearch(_first))
			_refs[ref] = ids
		out[ref] = ids.duplicate()  # Packed diziler REFERANSLA geçer: çağıranın değişikliği önbelleğe sızmasın
	return out


## Önbelleği ve tuttuğu durum/günlük referanslarını bırakır (kayıt yükleme).
func reset() -> void:
	_state = null
	_log = null
	_limit = -1
	_first = 0
	_last = 0
	_refs = {}


## Dizinin son kimliğinden sonra yazılan kayıtları ekler (`ReasonLog.subject_index` ile aynı sıra ve kırpma).
func _add_new_records() -> void:
	var log := _log
	for id in range(maxi(_last + 1, log.first_id()), log.last_id() + 1):
		var rec := log.peek(id)
		if rec.is_empty():
			continue
		for subject in rec["subjects"] as PackedStringArray:
			var ids: PackedInt64Array = _refs.get(subject, PackedInt64Array())
			ids.append(rec["id"])
			if ids.size() > _limit:
				ids = ids.slice(ids.size() - _limit)
			_refs[subject] = ids
	_last = log.last_id()
