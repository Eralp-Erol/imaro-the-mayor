class_name CouncilModel
extends RefCounted
## Meclis görünümü modeli (ux-flows-v0 §E, SIM-05, T-022): `CouncilView` -> sıralanmış satırlar + TAHMİN.
## UI sim kuralı uydurmaz: sonuç (`status`, sayılar) sim'dendir. Açık oylama için "beklenen sonuç" bir TAHMİNDİR ve
## kaynağı açıkça söylenir: sim bloklara BEKLENEN oy verdiyse (`positions`) o; vermediyse blokların destek eğilimi
## (`stance`) işaretine göre (artı = evet, eksi = hayır, sıfır = kararsız). Kabul kuralı sözleşmede `yes > no`dur;
## eşitlikte sonuç belirsiz gösterilir (eşitlik kuralı sim yapılandırmasındadır, ÇM).
## Tek bir "destek" toplamı yoktur (SIM-09).

enum Stance { SUPPORTIVE, OPPOSED, NEUTRAL }
enum Source { NONE, POSITIONS, STANCE }
enum Verdict { UNKNOWN, PASS, FAIL, TIE }

var view: CouncilView = null
var tick: int = 0
var blocs: Array[BlocRow] = []
var pending: Array[VoteRow] = []
var resolved: Array[VoteRow] = []


class BlocRow:
	extends RefCounted
	var actor: ActorRef = null
	var seats: int = 0
	var stance: int = 0
	## Koltuk payı, binde (tamsayı; görsel çubuk içindir).
	var share_permille: int = 0

	func stance_kind() -> Stance:
		if stance > 0:
			return Stance.SUPPORTIVE
		return Stance.OPPOSED if stance < 0 else Stance.NEUTRAL


class Expectation:
	extends RefCounted
	var source: Source = Source.NONE
	var yes: int = 0
	var no: int = 0
	var undecided: int = 0
	var verdict: Verdict = Verdict.UNKNOWN


class VoteRow:
	extends RefCounted
	var vote: CouncilVoteView = null
	var is_pending: bool = false
	## Sonucun beklendiği güne kalan (≥ 0); çözülmüş oylamada 0.
	var days_left: int = 0
	## Yalnız açık oylamada dolu.
	var expectation: Expectation = null


static func build(council: CouncilView, current_tick: int) -> CouncilModel:
	var m := CouncilModel.new()
	m.view = council
	m.tick = current_tick
	for b in council.blocs:
		var row := BlocRow.new()
		row.actor = b.bloc
		row.seats = b.seats
		row.stance = b.stance
		row.share_permille = _permille(b.seats, council.seats_total)
		m.blocs.append(row)
	for v in council.votes:
		var vr := VoteRow.new()
		vr.vote = v
		vr.is_pending = v.status == CouncilVoteView.STATUS_PENDING
		if vr.is_pending:
			vr.days_left = maxi(0, v.closes_tick - current_tick)
			vr.expectation = expectation_for(council, v)
			m.pending.append(vr)
		else:
			m.resolved.append(vr)
	m.pending.sort_custom(func(a: VoteRow, b: VoteRow) -> bool:
		return a.vote.closes_tick < b.vote.closes_tick or (a.vote.closes_tick == b.vote.closes_tick
			and a.vote.vote_id < b.vote.vote_id))
	m.resolved.sort_custom(func(a: VoteRow, b: VoteRow) -> bool: return a.vote.vote_id > b.vote.vote_id)
	return m


static func expectation_for(council: CouncilView, vote: CouncilVoteView) -> Expectation:
	var e := Expectation.new()
	var has_positions := false
	for p in vote.positions:
		if p.position != CouncilBlocView.POSITION_UNDECIDED:
			has_positions = true
	var rows: Array[CouncilBlocView] = vote.positions if has_positions else council.blocs
	if rows.is_empty():
		return e
	e.source = Source.POSITIONS if has_positions else Source.STANCE
	for b in rows:
		var leaning := _leaning(b, has_positions)
		if leaning > 0:
			e.yes += b.seats
		elif leaning < 0:
			e.no += b.seats
	e.undecided = maxi(0, council.seats_total - e.yes - e.no)
	if e.yes > e.no:
		e.verdict = Verdict.PASS
	elif e.no > e.yes:
		e.verdict = Verdict.FAIL
	else:
		e.verdict = Verdict.TIE
	return e


## Koltuk toplamı ile blok koltukları (ve oylama sayıları) uyuşmuyorsa veri hatası anahtarları (sessiz kabul yok).
func issues() -> PackedStringArray:
	var out := PackedStringArray()
	var sum := 0
	for b in blocs:
		sum += b.seats
	if not blocs.is_empty() and sum != view.seats_total:
		out.append("seats_mismatch")
	for row in pending + resolved:
		if row.vote.yes + row.vote.no + row.vote.abstain > view.seats_total:
			out.append("tally_exceeds_seats")
			break
	return out


func has_content() -> bool:
	return not blocs.is_empty() or not pending.is_empty() or not resolved.is_empty()


static func _leaning(b: CouncilBlocView, from_positions: bool) -> int:
	if from_positions:
		if b.position == CouncilBlocView.POSITION_YES:
			return 1
		return -1 if b.position == CouncilBlocView.POSITION_NO else 0
	return signi(b.stance)


@warning_ignore("integer_division")
static func _permille(part: int, total: int) -> int:
	return clampi(part * 1000 / total, 0, 1000) if total > 0 else 0
