class_name SimEventLog
extends RefCounted
## Sim olay günlüğü (T-027, ADR-0005 §5). Olaylar DURUMUN parçasıdır (`state.systems["events"]`): kayda ve hash'e
## girer, hangi sürücü tick'i ilerletirse ilerletsin aynı olaylar üretilir. Facade `events_since` ile ÇEKER.
##
## Kayıt: {seq, tick, kind, actor (ref dizgesi ya da &""), subjects (PackedStringArray), message_key, args,
## reason_ids (PackedInt64Array), command_id}. `seq` 1'den başlar, boşluksuz artar. Kapasite
## (`config.event_log_capacity`) aşılınca en eskiler budanır; seq hiç yeniden kullanılmaz.
## Okumalar durumu DEĞİŞTİRMEZ (yeni sistem verisi oluşturmaz).

const SYSTEM_KEY := "events"


## Olay ekler, seq döndürür (>= 1). Argümanlar düz veridir: ondalık yok (SimContract.to_args).
static func emit(state: GameState, kind: StringName, message_key: StringName, subjects: PackedStringArray,
		args: Dictionary = {}, reason_ids: PackedInt64Array = PackedInt64Array(), command_id: int = 0,
		actor: StringName = &"") -> int:
	var data := state.system_data(StringName(SYSTEM_KEY))
	var seq: int = data.get("next_seq", 1)
	var records: Array = data.get("records", [])
	records.append({
		"seq": seq, "tick": state.tick, "kind": kind, "actor": actor, "subjects": subjects.duplicate(),
		"message_key": message_key, "args": SimContract.to_args(args), "reason_ids": reason_ids.duplicate(),
		"command_id": command_id,
	})
	var capacity := int(state.config["event_log_capacity"])
	while records.size() > capacity:
		records.pop_front()
	data["records"] = records
	data["next_seq"] = seq + 1
	return seq


## Yayımlanmış son seq; hiç olay yoksa 0.
static func last_seq(state: GameState) -> int:
	var data: Variant = state.systems.get(SYSTEM_KEY, null)
	return 0 if not (data is Dictionary) else int(data.get("next_seq", 1)) - 1


## Hâlâ saklanan en eski seq; hiç olay yoksa last_seq + 1.
static func first_seq(state: GameState) -> int:
	var records := _records(state)
	return last_seq(state) + 1 if records.is_empty() else int((records[0] as Dictionary)["seq"])


## `seq > after_seq` olaylar (kopya), eskiden yeniye; `max_count > 0` ise en fazla o kadar (en eskiler).
static func since(state: GameState, after_seq: int, max_count: int = 0) -> Array:
	var out: Array = []
	for rec: Dictionary in _records(state):
		if int(rec["seq"]) <= after_seq:
			continue
		if max_count > 0 and out.size() >= max_count:
			break
		out.append(rec.duplicate(true))
	return out


## Kayıtlı olay verisinin (`systems["events"]`) biçim hatası; yoksa/geçerliyse "". GameState.validate_dict çağırır.
static func validate_data(data: Variant) -> String:
	if data == null:
		return ""
	if not (data is Dictionary):
		return "durum.systems.events sözlük değil"
	if typeof(data.get("next_seq", null)) != TYPE_INT or int(data["next_seq"]) < 1:
		return "durum.systems.events.next_seq eksik veya geçersiz"
	if not (data.get("records", null) is Array):
		return "durum.systems.events.records dizi değil"
	var expected := -1
	for rec: Variant in data["records"]:
		if not (rec is Dictionary):
			return "durum.systems.events.records öğesi sözlük değil"
		for key in ["seq", "tick", "command_id"]:
			if typeof(rec.get(key, null)) != TYPE_INT:
				return "olay kaydında %s int değil" % key
		for key in ["kind", "actor", "subjects", "message_key", "args", "reason_ids"]:
			if not rec.has(key):
				return "olay kaydında %s yok" % key
		if expected >= 0 and int(rec["seq"]) != expected:
			return "olay seq dizisi boşluklu"
		expected = int(rec["seq"]) + 1
	if expected >= 0 and expected != int(data["next_seq"]):
		return "olay next_seq son seq ile uyuşmuyor"
	return ""


static func _records(state: GameState) -> Array:
	var data: Variant = state.systems.get(SYSTEM_KEY, null)
	return [] if not (data is Dictionary) else data.get("records", [])
