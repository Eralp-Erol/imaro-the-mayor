class_name UiText
extends RefCounted
## Merkezi metin erişimi (ux-text-system §1): oyuncuya görünen TÜM metin `data/ui/strings.tr.json` tablosundan
## gelir.
## `get` adı Object.get ile çakıştığı için erişim `UiText.t(key, args)` (kısa) adıyladır.
##
## - Eksik anahtar: ekranda anahtar adı görünür, kayıt altına alınır (`missing_keys()`), `report_missing`
## açıksa
##   geliştirme günlüğüne hata yazılır. Sessiz boş metin yoktur.
## - Yer tutucu `{ad}` adlandırılmıştır; verilmeyen argüman yer tutucuyu görünür bırakır.
## - Para: `money(int)`; simge yalnız `UiConfig`'ten (Q-003). Şablondaki `{money}` int argüman olarak verilirse
##   otomatik biçimlenir. `₺`/`TL` hiçbir yerde üretilmez.
## - Sim'den gelen ref/anahtar argümanları (`parcel.12`, `zone.mixed`) okunur metne çevrilir (UI neden/ad
## UYDURMAZ).

const TABLE_PATH := "res://data/ui/strings.tr.json"
const MINUS := "−"

## Geliştirmede eksik anahtar için push_error yazılsın mı (testler kapatır).
static var report_missing: bool = true
static var _table: Dictionary = {}
static var _loaded: bool = false
static var _missing: PackedStringArray = PackedStringArray()


static func reset() -> void:
	_table = {}
	_loaded = false
	_missing = PackedStringArray()
	report_missing = true
	UiConfig.reset()


## Testler için tabloyu bellekten verir (dosya okunmaz).
static func set_table(table: Dictionary) -> void:
	_table = table.duplicate()
	_loaded = true


static func has(key: StringName) -> bool:
	_ensure_loaded()
	return _table.has(String(key))


static func missing_keys() -> PackedStringArray:
	return _missing


static func t(key: StringName, args: Dictionary = {}) -> String:
	_ensure_loaded()
	var k := String(key)
	if not _table.has(k):
		_note_missing(k)
		return k
	var text: String = str(_table[k])
	for arg_key: Variant in args:
		var placeholder := "{%s}" % str(arg_key)
		if text.contains(placeholder):
			text = text.replace(placeholder, _arg_text(str(arg_key), args[arg_key]))
	return text


## Birimsiz tamsayıyı yapılandırmadaki simgeyle gösterir: `1.234.567 ¤`.
static func money(amount: int) -> String:
	return t(&"format.money", {"amount": number(amount), "currency": UiConfig.currency_symbol()})


## Türkçe binlik ayracı (nokta) ve gerçek eksi işareti.
static func number(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "." + out
		out = digits[i] + out
		count += 1
	return (MINUS if value < 0 else "") + out


## Aktör görünen adı: kanon adı UYDURULMAZ; tür etiketi + sıra numarası (yer tutucu). Ad anahtarı tabloda
## varsa o.
static func actor_name(actor: ActorRef) -> String:
	if actor == null or not actor.is_valid():
		return t(&"common.unknown")
	if actor.name_key != &"" and has(actor.name_key):
		return t(actor.name_key)
	var kind_key := StringName("actor.kind.%s" % actor.kind)
	var kind_text := t(kind_key) if has(kind_key) else String(actor.kind)
	if not has(kind_key):
		_note_missing(String(kind_key))
	return t(&"actor.placeholder", {"kind": kind_text, "n": actor.id})


## Ret gerekçesi (CommandResult.reason_key + args ya da `command.rejected` olayı): sim'in kaydettiği neden
## UYDURULMADAN
## çevrilir; `why` argümanı varsa ikinci cümle olarak eklenir (örn. `zoning.reject.protected_area`).
static func reject_reason(reason_key: StringName, args: Dictionary = {}) -> String:
	var text := t(reason_key, args)
	if args.has("why"):
		text += ". " + t(&"reason.because", {"reason": humanize(args["why"])})
	return text


## Bildirim satırı metni: `command.rejected` olaylarında message_key bir ret anahtarıdır.
static func event_text(event: SimEvent) -> String:
	if event.kind == SimEvent.KIND_COMMAND_REJECTED:
		return t(&"state.error.command_rejected", {"reason": reject_reason(event.message_key, event.args)})
	return t(event.message_key, event.args)


## Sim anahtarı/ref'i okunur metne çevirir; bilinmeyen ham değer olduğu gibi (ve eksik olarak kaydedilerek)
## döner.
static func humanize(value: Variant) -> String:
	if value is int:
		return number(value)
	var s := str(value)
	if has(StringName(s)):
		return t(StringName(s))
	var parsed := SimContract.parse_ref(StringName(s))
	var id: int = parsed["id"]
	if id != SimContract.NO_ID:
		match str(parsed["kind"]):
			"parcel":
				return "%s %d" % [t(&"inspector.parcel"), id]
			"vote":
				return "%s %d" % [t(&"council.vote_label"), id]
			"command":
				return "%s %d" % [t(&"command.label"), id]
			"actor.investor", "actor.landowner", "actor.group", "actor.council", "actor.council_bloc":
				return actor_name(ActorRef.make(StringName(str(parsed["kind"]).trim_prefix("actor.")), id))
	return s


static func _arg_text(arg_name: String, value: Variant) -> String:
	if arg_name == "money" and value is int:
		return money(value)
	# Sim ad alanı önekleri: param.<ad> (komut parametresi), command.kind.<tür> (komut türü).
	var prefixed := {"param": "param.", "kind": "command.kind."}
	if prefixed.has(arg_name):
		var key := StringName(str(prefixed[arg_name]) + str(value))
		if has(key):
			return t(key)
	return humanize(value)


static func _note_missing(key: String) -> void:
	if not _missing.has(key):
		_missing.append(key)
		if report_missing:
			push_error("UiText: missing string key '%s'" % key)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	if parsed is Dictionary:
		_table = parsed
	else:
		push_error("UiText: cannot parse %s" % TABLE_PATH)
