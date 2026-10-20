class_name ActorSchema
extends RefCounted
## Aktör veri dosyalarının doğrulama yardımcıları (T-016, characters-npc §3, §7). SAF: dosya G/Ç yok (dosyaları
## `ActorConfig` okur). Doğrulayıcılar hata dizisine EKLER (ilk hatada durmaz): yazar tüm sorunları tek seferde görür.
## Hata biçimi: `<dosya>.<yol>: <açıklama>` (yol + kimlik, bozuk veri anlaşılır).

const VERSION := 1
const SCALE := SimContract.FIXED_SCALE
## Aktör anahtarı öneki; anahtarın geri kalanı veriden gelir (kodda ad/anahtar sabiti yok, S-N3).
const KEY_PREFIX := "actor"
const LODS: Array[String] = ["full", "cohort", "abstract"]
## `kinds.json` state_fields tip adları.
const FIELD_TYPES: Array[String] = [
	"permille", "count", "axis_map", "topic_map", "ref_list", "ref_map", "nullable_string", "string", "any_array",
	"any_dict",
]


## int ya da tam sayı değerli float (JSON) ise int; aksi halde null.
static func as_int(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
		return int(value)
	return null


## Derin kopya: tam sayı değerli float -> int (kesirli float olduğu gibi kalır; `float_problems` bulur).
static func to_ints(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = to_ints(value[key])
		return out
	if value is Array:
		var arr: Array = []
		for item: Variant in value:
			arr.append(to_ints(item))
		return arr
	var as_whole: Variant = as_int(value)
	return value if as_whole == null else as_whole


## Kesirli/sonlu olmayan sayıları bulur (kalıcı durumda float yok: permille tamsayı).
static func float_problems(value: Variant, path: String, errors: PackedStringArray) -> void:
	if value is Dictionary:
		for key: Variant in value:
			float_problems(value[key], "%s.%s" % [path, key], errors)
	elif value is Array:
		for i in (value as Array).size():
			float_problems(value[i], "%s[%d]" % [path, i], errors)
	elif typeof(value) == TYPE_FLOAT and as_int(value) == null:
		errors.append("%s: kesirli sayı (%s); permille tamsayı olmalı" % [path, str(value)])


static func in_range(value: Variant, low: int, high: int) -> bool:
	return typeof(value) == TYPE_INT and value >= low and value <= high


## `[a-z][a-z0-9_]*`.
static func is_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or (value as String).is_empty():
		return false
	var text: String = value
	for i in text.length():
		var code := text.unicode_at(i)
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not (is_lower or (i > 0 and (is_digit or code == 95))):
			return false
	return true


static func is_index(text: String) -> bool:
	return text.is_valid_int() and int(text) >= 1 and str(int(text)) == text


## Anahtar, türün biçimine uyuyor mu? Hata metni ya da "".
## Tekil: `actor.<tür>`; bölgesel: `actor.<tür>.<bölge>.<n>`; aksi `actor.<tür>.<n>` (n >= 1).
static func key_problem(key: Variant, kind: String, kind_spec: Dictionary) -> String:
	if typeof(key) != TYPE_STRING:
		return "anahtar metin olmalı"
	var parts := (key as String).split(".")
	var shape := ""
	var ok := parts.size() >= 2 and parts[0] == KEY_PREFIX and parts[1] == kind
	if kind_spec.get("singleton", false):
		shape = "%s.%s" % [KEY_PREFIX, kind]
		ok = ok and parts.size() == 2
	elif kind_spec.get("regional", false):
		shape = "%s.%s.<bölge>.<n>" % [KEY_PREFIX, kind]
		ok = ok and parts.size() == 4 and is_id(parts[2]) and is_index(parts[3])
	else:
		shape = "%s.%s.<n>" % [KEY_PREFIX, kind]
		ok = ok and parts.size() == 3 and is_index(parts[2])
	return "" if ok else "anahtar '%s' tür '%s' biçimine uymuyor (%s)" % [key, kind, shape]


## `data[field]` benzersiz kimlik dizisi mi? Geçerliyse kopyası, değilse boş dizi.
static func id_list(data: Dictionary, field: String, file: String, errors: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = data.get(field, null)
	if not (raw is Array) or (raw as Array).is_empty():
		errors.append("%s.%s: boş olmayan kimlik listesi olmalı" % [file, field])
		return out
	for i in (raw as Array).size():
		var item: Variant = raw[i]
		if not is_id(item):
			errors.append("%s.%s[%d]: geçersiz kimlik (%s)" % [file, field, i, str(item)])
		elif out.has(item):
			errors.append("%s.%s[%d]: yinelenen kimlik '%s'" % [file, field, i, item])
		else:
			out.append(item)
	return out


## Bilinmeyen alan anahtarlarını raporlar (yazım hatası koruması).
static func check_unknown(d: Dictionary, allowed: Array, path: String, errors: PackedStringArray) -> void:
	for key: Variant in d:
		if not allowed.has(key):
			errors.append("%s: bilinmeyen alan '%s'" % [path, str(key)])


## `map` {kimlik: int}; kimlikler `allowed` içinde, değerler [low, high].
static func check_map(map: Variant, allowed: Array, low: int, high: int, path: String,
		errors: PackedStringArray) -> void:
	if not (map is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return
	for key: Variant in map:
		if not allowed.has(key):
			errors.append("%s: bilinmeyen kimlik '%s'" % [path, str(key)])
		elif not in_range(map[key], low, high):
			errors.append("%s.%s: %d..%d dışında veya tamsayı değil (%s)" % [path, str(key), low, high, str(map[key])])


## İsteğe bağlı int alan: yoksa `fallback`; varsa aralık dışı ise hata.
static func optional_int(d: Dictionary, field: String, fallback: int, low: int, high: int, path: String,
		errors: PackedStringArray) -> int:
	if not d.has(field):
		return fallback
	if not in_range(d[field], low, high):
		errors.append("%s.%s: %d..%d dışında veya tamsayı değil (%s)" % [path, field, low, high, str(d[field])])
		return fallback
	return d[field]


## Zorunlu int alan.
static func required_int(d: Dictionary, field: String, low: int, high: int, path: String,
		errors: PackedStringArray) -> int:
	if not d.has(field):
		errors.append("%s.%s: eksik" % [path, field])
		return low
	return optional_int(d, field, low, low, high, path, errors)


## `kinds.json` state alanı tipine göre değer doğrulaması (ref'lerin VARLIĞI kadro kurulunca ayrıca denetlenir).
static func check_state_field(type: String, value: Variant, ctx: Dictionary, path: String,
		errors: PackedStringArray) -> void:
	match type:
		"permille":
			if not in_range(value, 0, SCALE):
				errors.append("%s: 0..%d dışında veya tamsayı değil (%s)" % [path, SCALE, str(value)])
		"count":
			if not in_range(value, 0, 1_000_000_000):
				errors.append("%s: negatif olmayan tamsayı olmalı (%s)" % [path, str(value)])
		"axis_map":
			check_map(value, ctx["axes"], -SCALE, SCALE, path, errors)
		"topic_map":
			check_map(value, ctx["topics"], 0, SCALE, path, errors)
		"ref_list":
			if not (value is Array):
				errors.append("%s: dizi olmalı" % path)
		"ref_map":
			check_map(value, (value as Dictionary).keys() if value is Dictionary else [], 0, SCALE, path, errors)
		"nullable_string", "string":
			_check_string(type == "nullable_string", value, path, errors)
		"any_array":
			if not (value is Array):
				errors.append("%s: dizi olmalı" % path)
		"any_dict":
			if not (value is Dictionary):
				errors.append("%s: sözlük olmalı" % path)
		_:
			errors.append("%s: bilinmeyen alan tipi '%s'" % [path, type])


static func _check_string(nullable: bool, value: Variant, path: String, errors: PackedStringArray) -> void:
	if value == null and nullable:
		return
	if typeof(value) != TYPE_STRING or (value as String).is_empty():
		errors.append("%s: boş olmayan metin%s olmalı" % [path, " ya da null" if nullable else ""])


## Aktör referansı olması gereken değerler: `kind_spec`i bilinmeyen/biçimsiz referans hata verir.
static func ref_problem(ref: Variant, known_keys: Array) -> String:
	if typeof(ref) != TYPE_STRING:
		return "referans metin olmalı"
	if not known_keys.has(ref):
		return "referans verilen aktör kadroda yok: '%s'" % ref
	return ""
