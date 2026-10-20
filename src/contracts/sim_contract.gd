class_name SimContract
extends RefCounted
## Sim↔View↔UI sözleşmesinin sabitleri ve yardımcıları (ADR-0005, T-023). Saf mantık: sahne, zaman, OS, rastgelelik yok.
##
## - Sürüm `MAJOR.MINOR`: MINOR = geriye uyumlu ekleme (yeni isteğe bağlı alan, yeni komut/olay türü);
##   MAJOR = kaldırma/yeniden adlandırma/anlam değişikliği. Tüketici yalnız MAJOR eşitliğini şart koşar.
## - Sabit nokta: oran/ağırlık/duruş değerleri `FIXED_SCALE` ile çarpılmış tamsayıdır (0.42 → 420).
## - Para: birimsiz tamsayı (Q-003). Ad/simge yalnız yapılandırmadan (`economy.currency_name/_symbol`) biçimlenir.
## - Kaynak (provenance): gerçek sim `&"sim"`, mock `&"mock"`. UI `&"sim"` dışındaki her şeyi "MOCK" diye işaretler.
## - Referans dizgesi (subject ref): `<tür>.<id>` (örn. `parcel.12`, `actor.investor.3`, `vote.2`); `ref()` üretir.

const VERSION_MAJOR := 1
const VERSION_MINOR := 0
const VERSION := "1.0"

const FIXED_SCALE := 1000

const PROVENANCE_SIM := &"sim"
const PROVENANCE_MOCK := &"mock"

## Kimlik yok (0). Tüm kimlikler 1'den başlar.
const NO_ID := 0

const REF_PARCEL := &"parcel"
const REF_ACTOR := &"actor"
const REF_COMMAND := &"command"
const REF_EVENT := &"event"
const REF_REASON := &"reason"
const REF_VOTE := &"vote"
const REF_BUDGET := &"budget"


## `version` bu sözleşmeyle uyumlu mu (aynı MAJOR, biçim `A.B`)?
static func is_compatible(version: String) -> bool:
	var parts := version.split(".")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return false
	return int(parts[0]) == VERSION_MAJOR


static func ref(kind: StringName, id: int) -> StringName:
	return StringName("%s.%d" % [kind, id])


static func parcel_ref(id: int) -> StringName:
	return ref(REF_PARCEL, id)


static func actor_ref(actor_kind: StringName, id: int) -> StringName:
	return StringName("%s.%s.%d" % [REF_ACTOR, actor_kind, id])


## `ref` → `{"kind": "actor.investor", "id": 3}`; geçersizse `{"kind": "", "id": 0}`.
static func parse_ref(value: StringName) -> Dictionary:
	var text := String(value)
	var dot := text.rfind(".")
	if dot <= 0 or not text.substr(dot + 1).is_valid_int():
		return {"kind": "", "id": NO_ID}
	return {"kind": text.substr(0, dot), "id": int(text.substr(dot + 1))}


## Doğrusal katkı: (değer × ağırlık) / FIXED_SCALE, sıfıra doğru kesilir (deterministik tamsayı).
@warning_ignore("integer_division")
static func contribution(value: int, weight: int) -> int:
	return (value * weight) / FIXED_SCALE


# --- Tür zorlama (JSON tüm sayıları float verir; sözleşme tamsayı ister) ---

static func to_int(value: Variant, fallback: int = 0) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return int(String(value)) if String(value).is_valid_int() else fallback
		TYPE_BOOL:
			return 1 if value else 0
	return fallback


static func to_float(value: Variant, fallback: float = 0.0) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return fallback


static func to_name(value: Variant) -> StringName:
	if value == null:
		return &""
	return StringName(str(value))


static func to_bool(value: Variant) -> bool:
	return value == true or (typeof(value) in [TYPE_INT, TYPE_FLOAT] and value != 0)


static func to_int64_array(value: Variant) -> PackedInt64Array:
	var out := PackedInt64Array()
	if value is Array or value is PackedInt64Array or value is PackedInt32Array or value is PackedFloat64Array:
		for v: Variant in value:
			out.append(to_int(v))
	return out


static func to_int32_array(value: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if value is Array or value is PackedInt64Array or value is PackedInt32Array or value is PackedFloat64Array:
		for v: Variant in value:
			out.append(to_int(v))
	return out


static func to_string_array(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array or value is PackedStringArray:
		for v: Variant in value:
			out.append(str(v))
	return out


## Sözlük → anahtarları StringName, değerleri olduğu gibi (kanonik). Sözlük değilse boş.
static func to_name_dict(value: Variant) -> Dictionary:
	var out := {}
	if value is Dictionary:
		for k: Variant in value:
			out[to_name(k)] = value[k]
	return out


## Metin şablonu argümanları (kanonik): anahtar String; değer int / String / bool (ondalık yok: sabit nokta int
## kullanılır). JSON'dan gelen tam sayılı float → int, StringName → String. Sözlük değilse boş.
static func to_args(value: Variant) -> Dictionary:
	var out := {}
	if value is Dictionary:
		for k: Variant in sorted_keys(value):
			var v: Variant = value[k]
			if v is float and v == floorf(v):
				v = int(v)
			elif v is StringName:
				v = String(v)
			out[str(k)] = v
	return out


## Sözlük anahtarları String gösterimine göre sıralı (kanonik bayt sırası için; StringName `<` güvenilmez).
static func sorted_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	return keys


## Açık uçlu sözlükleri (komut parametreleri, uzantılar) anahtar sırası kanonik derin kopyaya çevirir.
static func canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for k: Variant in sorted_keys(value):
			out[k] = canonical(value[k])
		return out
	if value is Array:
		var arr: Array = []
		for v: Variant in value:
			arr.append(canonical(v))
		return arr
	return value


static func to_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() == 2:
		return Vector2(to_float(value[0]), to_float(value[1]))
	return Vector2.ZERO


## Hash'lenebilir biçim: Vector2 → [x, y] (StateHash tekil Vector2 kabul etmez).
static func vector2_to_array(v: Vector2) -> Array:
	return [v.x, v.y]
