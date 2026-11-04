class_name PolicyState
extends RefCounted
## Belediyenin KALICI politikaları durum bölümü `state.systems["policy"]` (T-065 Aşama 1, ADR-0009 A/C/D, D-016 §1).
## Bölüm YALNIZ ilk KABUL EDİLEN `policy.set` komutunda yaratılır (`set_enabled`); okuma, önizleme, doğrulama ve ret
## bölüm YARATMAZ. Böylece politika hiç değiştirilmemiş koşuda sim durumuna ve hash'e tek bayt yazılmaz (GOLDEN_A/B ve
## GOLDEN_X bit-bit aynı). Yokluk = KAPALI: bu sabit bir kuraldır, veri varsayılanı yoktur (eski kayıtlar kapalı
## açılır).
## Kapatmak bölümü SİLMEZ (`enabled: false` kalır: kim/ne zaman bilgisi kaybolmaz). `SimSave.VERSION` artmaz.
##
## Düzen (düz veri):
##   version        VERSION
##   <politika>     {enabled: bool, changed_tick: int >= 0, command_id: int >= 1}   (şimdilik yalnız `resettlement`)
## Bilinmeyen politika anahtarı reddedilmez (ileriye dönük), okunmaz.

const KEY := "policy"
const VERSION := 1
const IDS: Array[StringName] = [PolicyView.ID_RESETTLEMENT]


## Bölüm (DOĞRUDAN durumun parçası); yoksa boş sözlük. Bölüm YARATMAZ.
static func data(state: GameState) -> Dictionary:
	var d: Variant = state.systems.get(KEY, null)
	return d if d is Dictionary else {}


## Politika açık mı? Bölüm/anahtar yoksa false. O(1).
static func enabled(state: GameState, policy_id: StringName) -> bool:
	var row: Variant = data(state).get(String(policy_id), null)
	return row is Dictionary and bool(row.get("enabled", false))


## Son değişimin tick'i; hiç değişmediyse -1.
static func changed_tick(state: GameState, policy_id: StringName) -> int:
	var row: Variant = data(state).get(String(policy_id), null)
	return int(row["changed_tick"]) if row is Dictionary else -1


## Son değişimi yapan komutun kimliği; hiç değişmediyse 0.
static func changed_by(state: GameState, policy_id: StringName) -> int:
	var row: Variant = data(state).get(String(policy_id), null)
	return int(row["command_id"]) if row is Dictionary else 0


## Politikayı yazar (bölüm yoksa YARATIR). YALNIZ `PolicySetHandler` çağırır.
static func set_enabled(state: GameState, policy_id: StringName, value: bool, command_id: int) -> void:
	var d := state.system_data(StringName(KEY))
	if not d.has("version"):
		d["version"] = VERSION
	d[String(policy_id)] = {"enabled": value, "changed_tick": state.tick, "command_id": command_id}


## Bölüm biçim hatası (Türkçe) ya da "". Bölüm yoksa geçerli.
static func validate_data(value: Variant) -> String:
	if value == null:
		return ""
	if not (value is Dictionary) or value.get("version", null) != VERSION:
		return "durum.systems.policy sözlük değil ya da sürümü geçersiz"
	for id in IDS:
		if not (value as Dictionary).has(String(id)):
			continue
		var row: Variant = value[String(id)]
		if not (row is Dictionary) or typeof(row.get("enabled", null)) != TYPE_BOOL:
			return "durum.systems.policy.%s.enabled bool değil" % String(id)
		if typeof(row.get("changed_tick", null)) != TYPE_INT or int(row["changed_tick"]) < 0:
			return "durum.systems.policy.%s.changed_tick negatif olmayan tamsayı değil" % String(id)
		if typeof(row.get("command_id", null)) != TYPE_INT or int(row["command_id"]) < 1:
			return "durum.systems.policy.%s.command_id pozitif tamsayı değil" % String(id)
	return ""
