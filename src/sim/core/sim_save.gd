class_name SimSave
extends RefCounted
## Kayıt/yükleme (T-002 ölçüt 6-7, ADR-0002 Karar 5). Biçim: Godot ikili/metin Variant serileştirmesi
## (`var_to_bytes` / `var_to_str`) — JSON DEĞİL: JSON int'i float'a çevirir ve durum hash'ini bozar (T-900 bulgusu).
## Zarf: {format, version (int), state_hash (SHA-256, bütünlük), state (GameState.to_dict())}.
## Yükleme sırası: biçim işareti -> sürüm -> durum biçimi -> bütünlük hash'i; her hata anlaşılır kod + Türkçe
## mesaj verir, istisna fırlatmaz. Sürüm artınca `MIN_SUPPORTED_VERSION` sabit kalır ve eski sürümler için taşıma
## (migration) eklenir; taşıma yoksa eski sürüm `version_too_old` ile reddedilir.
## Dosya/slot G/Ç bu sınıfın işi değildir (src/app): buraya yalnız bayt/metin verilir.

const FORMAT := "imaro-sim-save"
const VERSION := 1
const MIN_SUPPORTED_VERSION := 1


## Yükleme sonucu. ok ise `state` dolu; değilse `error_code` (&"empty", &"corrupt", &"bad_format",
## &"version_too_old", &"version_too_new", &"hash_mismatch") ve insan-okur `message`.
class LoadResult:
	extends RefCounted
	var ok: bool = false
	var state: GameState = null
	var error_code: StringName = &""
	var message: String = ""


## Durumu bayta çevirir. Durum hash'lenemiyorsa (Object vb.) push_error + BOŞ dizi: bozuk kayıt yazılmaz.
static func encode(state: GameState) -> PackedByteArray:
	var envelope := _envelope(state)
	if envelope.is_empty():
		return PackedByteArray()
	return var_to_bytes(envelope)


static func encode_text(state: GameState) -> String:
	var envelope := _envelope(state)
	if envelope.is_empty():
		return ""
	return var_to_str(envelope)


static func decode(bytes: PackedByteArray) -> LoadResult:
	if bytes.is_empty():
		return _fail(&"empty", "Kayıt boş.")
	return _open(bytes_to_var(bytes))


static func decode_text(text: String) -> LoadResult:
	if text.strip_edges().is_empty():
		return _fail(&"empty", "Kayıt boş.")
	return _open(str_to_var(text))


static func _envelope(state: GameState) -> Dictionary:
	var body := state.to_dict()
	var digest := StateHash.of(body)
	if digest.is_empty():
		return {}
	return {"format": FORMAT, "version": VERSION, "state_hash": digest, "state": body}


static func _open(envelope: Variant) -> LoadResult:
	if not (envelope is Dictionary):
		return _fail(&"corrupt", "Kayıt dosyası bozuk veya tanınmayan biçimde.")
	if envelope.get("format", null) != FORMAT:
		return _fail(&"bad_format", "Bu dosya bir Imaro simülasyon kaydı değil.")
	var version: Variant = envelope.get("version", null)
	if typeof(version) != TYPE_INT:
		return _fail(&"corrupt", "Kayıtta sürüm alanı yok veya geçersiz.")
	if int(version) < MIN_SUPPORTED_VERSION:
		return _fail(&"version_too_old",
			"Kayıt sürümü %d çok eski; desteklenen en eski sürüm %d." % [version, MIN_SUPPORTED_VERSION])
	if int(version) > VERSION:
		return _fail(&"version_too_new",
			"Kayıt sürümü %d bu oyun sürümünden yeni; desteklenen en yeni sürüm %d." % [version, VERSION])
	var body: Variant = envelope.get("state", null)
	var shape_error := GameState.validate_dict(body)
	if not shape_error.is_empty():
		return _fail(&"corrupt", "Kayıt bozuk: %s." % shape_error)
	if typeof(envelope.get("state_hash", null)) != TYPE_STRING or StateHash.of(body) != envelope["state_hash"]:
		return _fail(&"hash_mismatch", "Kayıt bütünlük denetimini geçemedi (içerik değişmiş veya bozulmuş).")
	var result := LoadResult.new()
	result.state = GameState.from_dict(body)
	result.ok = result.state != null
	if not result.ok:
		return _fail(&"corrupt", "Kayıt durumu kurulamadı.")
	return result


static func _fail(code: StringName, message: String) -> LoadResult:
	var result := LoadResult.new()
	result.error_code = code
	result.message = message
	return result
