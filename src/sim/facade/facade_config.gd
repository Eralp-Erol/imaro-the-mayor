class_name FacadeConfig
extends RefCounted
## SimFacadeImpl yapılandırması (T-027). Çalışma-modeli sayıları/sözlükleri kodda değil `data/sim/facade_config.json`'da
## (F05-C: ayarlanabilir, kanon değil). Kurulumda okunur (tick dışında).
##
##   facade.speed_levels         sözleşme hız seviyesi (indeks 0..n) -> TickDriver hız adı; 0 = paused.
##   facade.parcel_reason_limit  ParcelView.reason_ids için parsel başına en fazla kaç güncel gerekçe.
##   zoning.land_uses            kabul edilen arazi kullanımı anahtarları (sözlük sim yapılandırmasıdır).
##   zoning.apply_delay_days     imar önerisi kaç gün sonra yürürlüğe girer (>= 1; T-013 gerçek süreci getirene dek).

const DEFAULT_PATH := "res://data/sim/facade_config.json"

var speed_levels: Array[StringName] = []
var parcel_reason_limit: int = 5
var land_uses: Array[StringName] = []
var apply_delay_days: int = 3
## Geçersizse insan-okur hata metni, geçerliyse "".
var error: String = ""


static func load_default() -> FacadeConfig:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> FacadeConfig:
	if not FileAccess.file_exists(path):
		return _invalid("facade yapılandırma dosyası yok: %s" % path)
	return from_json_text(FileAccess.get_file_as_string(path))


static func from_json_text(text: String) -> FacadeConfig:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _invalid("facade yapılandırma JSON ayrıştırılamadı (satır %d: %s)"
			% [json.get_error_line(), json.get_error_message()])
	if not (json.data is Dictionary):
		return _invalid("facade yapılandırma JSON nesnesi değil")
	return from_dict(json.data)


static func from_dict(data: Dictionary) -> FacadeConfig:
	var facade_in: Variant = data.get("facade", null)
	var zoning_in: Variant = data.get("zoning", null)
	if not (facade_in is Dictionary):
		return _invalid("'facade' bölümü eksik")
	if not (zoning_in is Dictionary):
		return _invalid("'zoning' bölümü eksik")
	var cfg := FacadeConfig.new()
	var levels := _names(facade_in.get("speed_levels", null))
	if levels.is_empty() or levels[0] != &"paused" or _has_duplicates(levels):
		return _invalid("facade.speed_levels boş, tekrarlı veya ilk öğesi 'paused' değil (speed_levels)")
	cfg.speed_levels = levels
	var limit: Variant = _positive_int(facade_in.get("parcel_reason_limit", null))
	if limit == null:
		return _invalid("facade.parcel_reason_limit eksik veya pozitif tam sayı değil (parcel_reason_limit)")
	cfg.parcel_reason_limit = limit
	var uses := _names(zoning_in.get("land_uses", null))
	if uses.is_empty() or _has_duplicates(uses):
		return _invalid("zoning.land_uses boş veya tekrarlı (land_uses)")
	cfg.land_uses = uses
	var delay: Variant = _positive_int(zoning_in.get("apply_delay_days", null))
	if delay == null:
		return _invalid("zoning.apply_delay_days eksik veya pozitif tam sayı değil (apply_delay_days)")
	cfg.apply_delay_days = delay
	return cfg


func is_valid() -> bool:
	return error.is_empty()


func is_land_use(use: StringName) -> bool:
	return land_uses.has(use)


static func _invalid(message: String) -> FacadeConfig:
	var cfg := FacadeConfig.new()
	cfg.error = message
	return cfg


## Boş olmayan metin dizisi -> StringName dizisi; biçim bozuksa boş dizi.
static func _names(value: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if not (value is Array):
		return out
	for item: Variant in value:
		if typeof(item) != TYPE_STRING or (item as String).is_empty():
			return []
		out.append(StringName(item))
	return out


static func _has_duplicates(names: Array[StringName]) -> bool:
	for i in names.size():
		if names.find(names[i]) != i:
			return true
	return false


## int ya da tam sayı değerli float (JSON) ise >= 1 için int; aksi halde null.
static func _positive_int(value: Variant) -> Variant:
	var as_int: Variant = null
	if typeof(value) == TYPE_INT:
		as_int = value
	elif typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
		as_int = int(value)
	return as_int if as_int != null and int(as_int) >= 1 else null
