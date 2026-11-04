class_name CouncilView
extends SimDto
## Küçük meclisin değer kopyası (SIM-05, M2 dilimi). Bloklar ve oylamalar; adlar yalnız yer tutucu anahtar (Q-005).

var council: ActorRef = null
var seats_total: int = 0
var blocs: Array[CouncilBlocView] = []
## Açık ve yakın geçmişteki oylamalar, vote_id artan sırada.
var votes: Array[CouncilVoteView] = []


func vote(id: int) -> CouncilVoteView:
	for v in votes:
		if v.vote_id == id:
			return v
	return null


func pending_votes() -> Array[CouncilVoteView]:
	var out: Array[CouncilVoteView] = []
	for v in votes:
		if v.status == CouncilVoteView.STATUS_PENDING:
			out.append(v)
	return out


func to_dict() -> Dictionary:
	return {
		"council": ActorRef.to_variant(council), "seats_total": seats_total, "blocs": SimDto.dicts_of(blocs),
		"votes": SimDto.dicts_of(votes),
	}


static func from_dict(d: Dictionary) -> CouncilView:
	var c := CouncilView.new()
	c.council = ActorRef.from_variant(d.get("council"))
	c.seats_total = SimContract.to_int(d.get("seats_total"))
	for bd: Variant in d.get("blocs", []):
		if bd is Dictionary:
			c.blocs.append(CouncilBlocView.from_dict(bd))
	for vd: Variant in d.get("votes", []):
		if vd is Dictionary:
			c.votes.append(CouncilVoteView.from_dict(vd))
	return c
