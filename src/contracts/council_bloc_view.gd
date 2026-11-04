class_name CouncilBlocView
extends SimDto
## Mecliste bir blok (ADR-0005). Parti/blok adları ve sayısı AÇIKTIR (F05-D, Q-005): yalnız yer tutucu ActorRef.
## Aynı DTO bir oylamadaki blok pozisyonu için de kullanılır (`position`, `reason_id`).

const POSITION_UNDECIDED := &"undecided"
const POSITION_YES := &"yes"
const POSITION_NO := &"no"
const POSITION_ABSTAIN := &"abstain"

var bloc: ActorRef = null
var seats: int = 0
## Oyuncu yönetimine destek eğilimi: sabit nokta, −FIXED_SCALE … +FIXED_SCALE.
var stance: int = 0
## Oylama bağlamında blok pozisyonu ve gerekçesi (meclis görünümünde POSITION_UNDECIDED / 0).
var position: StringName = POSITION_UNDECIDED
var reason_id: int = SimContract.NO_ID


func to_dict() -> Dictionary:
	return {
		"bloc": ActorRef.to_variant(bloc), "seats": seats, "stance": stance, "position": position,
		"reason_id": reason_id,
	}


static func from_dict(d: Dictionary) -> CouncilBlocView:
	var b := CouncilBlocView.new()
	b.bloc = ActorRef.from_variant(d.get("bloc"))
	b.seats = SimContract.to_int(d.get("seats"))
	b.stance = SimContract.to_int(d.get("stance"))
	b.position = SimContract.to_name(d.get("position", POSITION_UNDECIDED))
	b.reason_id = SimContract.to_int(d.get("reason_id"))
	return b
