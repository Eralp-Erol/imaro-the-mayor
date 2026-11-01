class_name SimCommand
extends SimDto
## Oyuncu niyeti = komut (ADR-0002 §1, TEK-01). Komut tick sınırında doğrulanıp uygulanır; günlüğe yazılır.
##
## Katalog BEYAZ LİSTEDİR ve yalnız belediye başkanı fiillerini içerir (CAN-03): imar, kamu işi, bütçe, politika.
## Özel bina yaratan bir komut türü YOKTUR ve eklenemez: `FORBIDDEN_PREFIXES` ile başlayan türler
## `command.reject.not_a_mayor_verb` ile reddedilir (sözleşme testi kataloğun bu öneklerden arınık
## olduğunu da denetler).
## Yeni komut = katalog satırı + MINOR sürüm artışı (ADR-0005 değişiklik protokolü).
##
## `validate_shape()` her uygulamanın (mock + SimFacadeImpl) ORTAK ilk doğrulamasıdır: tür, zorunlu parametre,
## parametre tipi ve değer aralığı. Duruma bağlı doğrulama (parsel var mı, bütçe yeter mi) uygulamanındır.

const KIND_ZONING_PROPOSE := &"zoning.propose"
const KIND_BUDGET_PROPOSE := &"budget.propose"
## v1.3 (T-042, ADR-0005 Ek E): belediye inşası ilk fiili. Oyuncu yolu yalnız KOŞULU (ağ + bölge altyapı kapasitesi)
## değiştirir; özel bina doğurmaz (CAN-03).
const KIND_PUBLIC_WORK_ROAD := &"public_work.road"
const KIND_PUBLIC_WORK_UNDO_LAST := &"public_work.undo_last"
## v1.6 (T-042c, D-014 §1): duran bir oyuncu yolunu YIK (her zaman mümkün, maliyeti var; alınan
## parselleri/binaları geri GETİRMEZ). Yalnız koşulu değiştirir, özel bina doğurmaz (CAN-03).
const KIND_PUBLIC_WORK_DEMOLISH := &"public_work.demolish"
## v1.5 isteğe bağlı ek (ADR-0005 Ek F): oyuncunun gündem öğesine yanıtı. `AgendaItemView.options` listesindeki bir
## seçeneği seçer; etkisi yalnız mevcut sistem durumlarına (şikâyet, güven, yatırımcı riski ...) zamana yayılarak
## yazılır, özel bina doğurmaz (CAN-03).
const KIND_AGENDA_RESPOND := &"agenda.respond"
## `points_cm` parametresi koordinat taşır (sıfır/negatif geçerli); kimlik dizisi kuralı (>= 1) burada uygulanmaz.
## Çift sayıda eleman, en az iki nokta, en çok `MAX_ROAD_POINTS`; değerler ±`COORD_LIMIT_CM` içinde.
const COORDINATE_PARAMS: Array[String] = ["points_cm"]
const MAX_ROAD_POINTS := 16
const COORD_LIMIT_CM := 100_000_000

## Tür → {"required": {param: TYPE_*}, "optional": {param: TYPE_*}}. Sayısal değerler ≥ 0 olmalıdır.
const CATALOG := {
	&"zoning.propose": {
		"required": {"parcel_ids": TYPE_PACKED_INT64_ARRAY, "land_use": TYPE_STRING_NAME},
		"optional": {"density": TYPE_INT, "max_height_m": TYPE_INT},
	},
	&"budget.propose": {
		"required": {"lines": TYPE_DICTIONARY},
		"optional": {},
	},
	&"public_work.road": {
		"required": {"points_cm": TYPE_PACKED_INT64_ARRAY, "road_class": TYPE_STRING_NAME},
		"optional": {"expropriate": TYPE_BOOL},  # v1.5 (T-042b, D-011): yok/false = Ek E davranışı
	},
	&"public_work.undo_last": {
		"required": {},
		"optional": {},
	},
	&"public_work.demolish": {
		"required": {"command_id": TYPE_INT},  # yolu yapan komutun kimliği (`PublicWorkView.command_id`)
		"optional": {},
	},
	&"agenda.respond": {
		"required": {"item_id": TYPE_INT, "option_id": TYPE_STRING_NAME},
		"optional": {},
	},
}

## Özel geliştirmeyi doğrudan yaratacak fiil ad alanları (CAN-03). Katalogda asla bulunmaz.
const FORBIDDEN_PREFIXES: Array[String] = ["building.", "private.", "spawn."]

var kind: StringName = &""
var params: Dictionary = {}
## UI'nin kendi eşleştirmesi için serbest etiket (sim yorumlamaz).
var client_tag: StringName = &""


static func make(command_kind: StringName, command_params: Dictionary = {}) -> SimCommand:
	var c := SimCommand.new()
	c.kind = command_kind
	c.params = command_params.duplicate(true)
	return c


static func zoning_propose(parcel_ids: PackedInt64Array, land_use: StringName) -> SimCommand:
	return make(KIND_ZONING_PROPOSE, {"parcel_ids": parcel_ids, "land_use": land_use})


## `lines`: bütçe kalemi anahtarı (StringName) → birimsiz tamsayı tutar (Q-003).
static func budget_propose(lines: Dictionary) -> SimCommand:
	return make(KIND_BUDGET_PROPOSE, {"lines": SimContract.to_name_dict(lines)})


## v1.3 · İki uç (v0) ya da daha çok noktalı yol: `points_cm` = [x0, z0, x1, z1, ...] santimetre tamsayı.
## v1.5 · `expropriate`: yol binalı parsellerden geçerse parselleri alır (bina yıkılır, geri alınabilir). false iken
## parametre HİÇ yazılmaz (komut günlüğü ve hash Ek E ile bit-bit aynı kalır).
static func public_work_road(points_cm: PackedInt64Array, road_class: StringName, expropriate: bool = false) \
		-> SimCommand:
	var params := {"points_cm": points_cm, "road_class": road_class}
	if expropriate:
		params["expropriate"] = true
	return make(KIND_PUBLIC_WORK_ROAD, params)


## v1.3 · Son oyuncu yolunu geri al (LIFO).
static func public_work_undo_last() -> SimCommand:
	return make(KIND_PUBLIC_WORK_UNDO_LAST, {})


## v1.6 (T-042c) · Duran yolu yık: `command_id` = `PublicWorkView.command_id` (>= 1).
static func public_work_demolish(road_command_id: int) -> SimCommand:
	return make(KIND_PUBLIC_WORK_DEMOLISH, {"command_id": road_command_id})


## v1.5 (isteğe bağlı ek) · Gündem öğesine yanıt: `item_id` = `AgendaItemView.item_id`, `option_id` =
## `AgendaOptionView.option_id`. Listede olmayan/kilitli/etkisiz seçenek gerekçeyle reddedilir.
static func agenda_respond(item_id: int, option_id: StringName) -> SimCommand:
	return make(KIND_AGENDA_RESPOND, {"item_id": item_id, "option_id": option_id})


static func is_forbidden_kind(command_kind: StringName) -> bool:
	for prefix in FORBIDDEN_PREFIXES:
		if String(command_kind).begins_with(prefix):
			return true
	return false


## Ortak şekil doğrulaması. Geçerliyse `{}`, değilse `{"reason_key": ..., "args": {...}}`.
func validate_shape() -> Dictionary:
	if is_forbidden_kind(kind):
		return _reject(CommandResult.REJECT_NOT_A_MAYOR_VERB, {"kind": kind})
	if not CATALOG.has(kind):
		return _reject(CommandResult.REJECT_UNKNOWN_KIND, {"kind": kind})
	var spec: Dictionary = CATALOG[kind]
	var required: Dictionary = spec["required"]
	var optional: Dictionary = spec["optional"]
	for p: String in required:
		if not params.has(p):
			return _reject(CommandResult.REJECT_MISSING_PARAM, {"param": p})
	for p: Variant in params:
		var expected: int = required.get(p, optional.get(p, TYPE_NIL))
		if expected == TYPE_NIL:
			return _reject(CommandResult.REJECT_UNKNOWN_PARAM, {"param": str(p)})
		var problem := _coordinate_problem(params[p]) if COORDINATE_PARAMS.has(str(p)) \
			else _param_problem(params[p], expected)
		if not problem.is_empty():
			return _reject(problem, {"param": str(p)})
	return {}


func to_dict() -> Dictionary:
	return {"kind": kind, "params": SimContract.canonical(params), "client_tag": client_tag}


## Katalogdaki türler için parametreleri kanonik tiplere zorlar (JSON/Array → PackedInt64Array, String → StringName,
## float → int). Bilinmeyen parametreler olduğu gibi kalır (şekil doğrulaması reddeder).
static func from_dict(d: Dictionary) -> SimCommand:
	var c := SimCommand.new()
	c.kind = SimContract.to_name(d.get("kind"))
	c.client_tag = SimContract.to_name(d.get("client_tag", ""))
	var raw: Dictionary = d.get("params", {}) if d.get("params") is Dictionary else {}
	var spec: Dictionary = CATALOG.get(c.kind, {})
	var types: Dictionary = (spec.get("required", {}) as Dictionary).merged(spec.get("optional", {}))
	for p: Variant in raw:
		c.params[str(p)] = _coerce(raw[p], types.get(str(p), TYPE_NIL))
	return c


static func _coerce(value: Variant, expected: int) -> Variant:
	match expected:
		TYPE_PACKED_INT64_ARRAY:
			return SimContract.to_int64_array(value) if value is Array else value
		TYPE_STRING_NAME:
			return SimContract.to_name(value) if value is String else value
		TYPE_INT:
			return SimContract.to_int(value) if value is float and value == floorf(value) else value
		TYPE_DICTIONARY:
			return _coerce_amounts(value) if value is Dictionary else value
	return value


static func _coerce_amounts(value: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in value:
		var v: Variant = value[k]
		out[SimContract.to_name(k)] = SimContract.to_int(v) if v is float and v == floorf(v) else v
	return out


# Koordinat dizisi: tip, çift sayıda eleman (>= 4), üst sınır, mutlak değer sınırı.
static func _coordinate_problem(value: Variant) -> StringName:
	if typeof(value) != TYPE_PACKED_INT64_ARRAY:
		return CommandResult.REJECT_BAD_PARAM_TYPE
	var coords: PackedInt64Array = value
	if coords.size() < 4 or coords.size() % 2 != 0 or coords.size() > MAX_ROAD_POINTS * 2:
		return CommandResult.REJECT_INVALID_VALUE
	for c in coords:
		if absi(c) > COORD_LIMIT_CM:
			return CommandResult.REJECT_INVALID_VALUE
	return &""


# Parametre sorunu varsa ret anahtarı, yoksa "".
static func _param_problem(value: Variant, expected: int) -> StringName:
	if typeof(value) != expected:
		return CommandResult.REJECT_BAD_PARAM_TYPE
	match expected:
		TYPE_PACKED_INT64_ARRAY:
			var ids: PackedInt64Array = value
			if ids.is_empty() or Array(ids).any(func(i: int) -> bool: return i <= SimContract.NO_ID):
				return CommandResult.REJECT_INVALID_VALUE
		TYPE_STRING_NAME:
			if value == &"":
				return CommandResult.REJECT_INVALID_VALUE
		TYPE_INT:
			if value < 0:
				return CommandResult.REJECT_INVALID_VALUE
		TYPE_DICTIONARY:
			return _amounts_problem(value)
	return &""


# Bütçe kalemleri: boş olmayan StringName anahtar → int ≥ 0.
static func _amounts_problem(lines: Dictionary) -> StringName:
	if lines.is_empty():
		return CommandResult.REJECT_INVALID_VALUE
	for k: Variant in lines:
		if typeof(k) != TYPE_STRING_NAME or k == &"" or typeof(lines[k]) != TYPE_INT:
			return CommandResult.REJECT_BAD_PARAM_TYPE
		if lines[k] < 0:
			return CommandResult.REJECT_INVALID_VALUE
	return &""


static func _reject(reason_key: StringName, args: Dictionary) -> Dictionary:
	return {"reason_key": reason_key, "args": args}
