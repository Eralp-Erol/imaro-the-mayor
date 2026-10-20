class_name ActorRef
extends SimDto
## Aktöre değer referansı (ADR-0005). Ad TAŞIMAZ; yalnız yer tutucu kimlik + yerelleştirme anahtarı (T-015:
## `actor.<tür>.<n>`). Türler açık uçludur (`investor`, `group`, `council`, `council_bloc`, `media`, `municipality`,
## `player`…); taksonomi T-015/T-016'dadır, sözleşme sabitlemez.

var kind: StringName = &""
var id: int = SimContract.NO_ID
## Görünen adın metin anahtarı (örn. `actor.investor.3.name`); ad AÇIK ise yer tutucu anahtar.
var name_key: StringName = &""


static func make(actor_kind: StringName, actor_id: int, actor_name_key: StringName = &"") -> ActorRef:
	var a := ActorRef.new()
	a.kind = actor_kind
	a.id = actor_id
	a.name_key = actor_name_key
	return a


## Kanonik referans dizgesi: `actor.<kind>.<id>`.
func ref() -> StringName:
	return SimContract.actor_ref(kind, id)


func is_valid() -> bool:
	return kind != &"" and id > SimContract.NO_ID


func to_dict() -> Dictionary:
	return {"kind": kind, "id": id, "name_key": name_key}


static func from_dict(d: Dictionary) -> ActorRef:
	return make(SimContract.to_name(d.get("kind")), SimContract.to_int(d.get("id")),
		SimContract.to_name(d.get("name_key")))


## null güvenli: sözlük değilse null.
static func from_variant(v: Variant) -> ActorRef:
	return from_dict(v) if v is Dictionary else null


static func to_variant(a: ActorRef) -> Variant:
	return null if a == null else a.to_dict()
