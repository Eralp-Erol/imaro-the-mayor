class_name CouncilPanel
extends FlowPanel
## Meclis oylaması paneli (ux-flows-v0 §E, SIM-05, CAN-06, T-022): `CouncilView` -> gruplar, açık oylamalar,
## sonuçlanan oylamalar. Kurulmamışsa (`SimSections.council_built` false) yalnız "Henüz kurulmadı" durumu görünür.
##
## Okuduğu sim alanları: `CouncilView.seats_total/blocs[bloc, seats, stance]/votes[...]`,
## `CouncilVoteView.status/yes/no/abstain/closes_tick/positions[position, reason_id]/reason_ids/title_key/subject_ref`.
## - Açık oylamada "beklenen sonuç" bir TAHMİNDİR: tahmin çipi + kaynağı söyleyen not (sim'in beklenen oyları ya da
##   grupların destek eğilimi). Sim sonucu yalnız `status` ve sayılar çözülünce görünür.
## - Oylama sonrası her grubun oyu için "Bu grubun gerekçesi" ve oylama için "Nedenini gör" -> `ReasonPanel`.
## - Oyuncu fiili (destek arama/taviz) sözleşmede YOK: düğme uydurulmaz. Tek bir toplam "destek" göstergesi yoktur.

var model: CouncilModel = null


static func create(ctx: UiContext, facade: SimFacade) -> CouncilPanel:
	var p := CouncilPanel.new()
	p._setup_flow(ctx, facade)
	p._render()
	return p


## Anlık görüntünün meclis bölümünün imzası: değişmediyse yeniden çizmeye gerek yok (odak/kaydırma korunur).
func signature_now() -> String:
	var snap := _facade.snapshot()
	var pending_tick := snap.tick() if not snap.council.pending_votes().is_empty() else -1
	return "%s|%d|%s" % [var_to_str(snap.council.to_dict()), pending_tick, SimSections.council_built(snap)]


func refresh() -> void:
	refresh_if_changed(signature_now())


func _render() -> void:
	if _body == null:
		return
	_signature = signature_now()
	var focus_role := _begin_render()
	var snap := _facade.snapshot()
	model = null
	if not SimSections.council_built(snap):
		state_view.show_not_built(&"council.not_built")
		return
	state_view.show_normal()
	model = CouncilModel.build(snap.council, snap.tick())
	_add_issues()
	# Oylamalar önce (karar bilgisi), grupların dağılımı sonra: alt sayfada ilk görünen yer oylamadır.
	_add_pending()
	_add_resolved()
	if model.pending.is_empty() and model.resolved.is_empty():
		_body.add_child(_muted(UiText.t(&"council.no_votes")))
	_add_blocs()
	_restore_focus(focus_role)


func _add_issues() -> void:
	for key in model.issues():
		var box := PanelContainer.new()
		box.theme_type_variation = UiTheme.V_PANEL_ALERT
		var row := HBoxContainer.new()
		row.add_child(ReasonGlyph.create(_ctx, ReasonGlyph.Kind.WARN, _ctx.tokens.color("danger"),
			UiText.t(&"reason.inconsistent_row")))
		row.add_child(UiFactory.label(UiText.t(StringName("council.issue.%s" % key)), UiTheme.V_LABEL_DANGER, true))
		box.add_child(row)
		_body.add_child(box)


func _add_blocs() -> void:
	_body.add_child(_section(&"council.blocs_title"))
	_body.add_child(_muted(UiText.t(&"council.seats_total", {"seats": model.view.seats_total})))
	for b in model.blocs:
		var parts := _card()
		var inner: VBoxContainer = parts[1]
		inner.add_child(UiFactory.label(UiText.actor_name(b.actor), UiTheme.V_LABEL_TITLE, true))
		var seats := HBoxContainer.new()
		seats.add_child(MeterBar.create(_ctx, b.share_permille))
		var seat_label := UiFactory.label(UiText.t(&"council.seat_count", {"seats": b.seats}))
		seat_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		seats.add_child(seat_label)
		inner.add_child(seats)
		inner.add_child(_stance_row(b))
		_body.add_child(parts[0])


func _stance_row(b: CouncilModel.BlocRow) -> Control:
	var caption := UiText.t(&"council.stance")
	var value := UiText.fixed(b.stance, true)
	match b.stance_kind():
		CouncilModel.Stance.SUPPORTIVE:
			return _direction_row(ReasonGlyph.Kind.UP, "ok", UiTheme.V_LABEL_OK,
				"%s: %s (%s)" % [caption, UiText.t(&"council.stance.supportive"), value])
		CouncilModel.Stance.OPPOSED:
			return _direction_row(ReasonGlyph.Kind.DOWN, "danger", UiTheme.V_LABEL_DANGER,
				"%s: %s (%s)" % [caption, UiText.t(&"council.stance.opposed"), value])
	return _direction_row(ReasonGlyph.Kind.FLAT, "text_muted", UiTheme.V_LABEL_MUTED,
		"%s: %s" % [caption, UiText.t(&"council.stance.neutral")])


func _add_pending() -> void:
	if model.pending.is_empty():
		return
	_body.add_child(_section(&"council.votes_pending"))
	for row in model.pending:
		_body.add_child(_vote_card(row))


func _add_resolved() -> void:
	if model.resolved.is_empty():
		return
	_body.add_child(_section(&"council.votes_resolved"))
	for row in model.resolved:
		_body.add_child(_vote_card(row))


func _vote_card(row: CouncilModel.VoteRow) -> Control:
	var v := row.vote
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(UiFactory.label(_vote_title(v), UiTheme.V_LABEL_TITLE, true))
	if v.subject_ref != &"":
		inner.add_child(_pair(UiText.t(&"council.subject"), UiText.humanize(String(v.subject_ref))))
	if row.is_pending:
		inner.add_child(UiFactory.label("%s — %s" % [UiText.t(&"council.status.pending"), _closes_text(row)], &"", true))
		inner.add_child(_muted(UiText.t(&"council.game_runs")))
		_add_expectation(inner, row.expectation)
		_add_positions(inner, v, false)
	else:
		_add_result(inner, v)
		_add_positions(inner, v, true)
		if not v.reason_ids.is_empty():
			var ids := v.reason_ids
			var why := UiFactory.button(_ctx, UiText.t(&"council.why_vote"), true)
			_tag(why, "vote_reason_%d" % v.vote_id)
			why.pressed.connect(func() -> void: _request_reason(func(p: ReasonPanel) -> void: p.show_reason_ids(ids)))
			inner.add_child(why)
	var subject := SimContract.parse_ref(v.subject_ref)
	if str(subject["kind"]) == String(SimContract.REF_BUDGET):
		var open := UiFactory.button(_ctx, UiText.t(&"council.open_budget"), false)
		_tag(open, "open_budget_%d" % v.vote_id)
		open.pressed.connect(func() -> void: navigate_requested.emit(&"budget"))
		inner.add_child(open)
	return parts[0]


func _add_expectation(inner: VBoxContainer, e: CouncilModel.Expectation) -> void:
	var head := HBoxContainer.new()
	head.add_child(UiFactory.label(UiText.t(&"council.expected"), UiTheme.V_LABEL_TITLE, true))
	head.add_child(_estimate_chip())
	inner.add_child(head)
	if e == null or e.source == CouncilModel.Source.NONE:
		inner.add_child(_muted(UiText.t(&"council.expect.unknown")))
		return
	inner.add_child(UiFactory.label(UiText.t(&"council.expected_tally",
		{"yes": e.yes, "no": e.no, "undecided": e.undecided}), &"", true))
	var verdict_key := &"council.expect.tie"
	match e.verdict:
		CouncilModel.Verdict.PASS:
			verdict_key = &"council.expect.pass"
		CouncilModel.Verdict.FAIL:
			verdict_key = &"council.expect.fail"
	inner.add_child(UiFactory.label("%s (%s)" % [UiText.t(verdict_key), UiText.t(&"common.estimate")], &"", true))
	inner.add_child(_muted(UiText.t(&"council.estimate_from_positions" if e.source == CouncilModel.Source.POSITIONS
		else &"council.estimate_from_stance")))


func _add_result(inner: VBoxContainer, v: CouncilVoteView) -> void:
	var passed := v.status == CouncilVoteView.STATUS_PASSED
	inner.add_child(_direction_row(ReasonGlyph.Kind.UP if passed else ReasonGlyph.Kind.DOWN,
		"ok" if passed else "danger", UiTheme.V_LABEL_OK if passed else UiTheme.V_LABEL_DANGER,
		UiText.t(&"council.outcome.approved" if passed else &"council.outcome.rejected")))
	inner.add_child(UiFactory.label(UiText.t(&"council.tally", {"yes": v.yes, "no": v.no, "abstain": v.abstain}),
		&"", true))
	inner.add_child(_tally_row(&"council.vote.for", v.yes, "ok"))
	inner.add_child(_tally_row(&"council.vote.against", v.no, "danger"))
	if v.abstain > 0:
		inner.add_child(_tally_row(&"council.vote.abstain", v.abstain, "text_muted"))


## Etiket + koltuk payı çubuğu + sayı (sayı ve etiket anlamı taşır; renk yalnız vurgudur).
@warning_ignore("integer_division")
func _tally_row(caption_key: StringName, count: int, token: String) -> Control:
	var total := maxi(1, model.view.seats_total)
	var row := HBoxContainer.new()
	var cap := UiFactory.label(UiText.t(caption_key))
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.custom_minimum_size.x = _ctx.px(72.0)
	row.add_child(cap)
	row.add_child(MeterBar.create(_ctx, count * 1000 / total, token))
	var num := UiFactory.label(str(count))
	num.custom_minimum_size.x = _ctx.px(28.0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(num)
	return row


func _add_positions(inner: VBoxContainer, v: CouncilVoteView, show_reason: bool) -> void:
	if v.positions.is_empty():
		return
	inner.add_child(UiFactory.label(UiText.t(&"council.positions"), UiTheme.V_LABEL_MUTED, true))
	for p in v.positions:
		var line := HBoxContainer.new()
		line.add_child(UiFactory.label("%s (%s)" % [UiText.actor_name(p.bloc), UiText.t(&"council.seat_count",
			{"seats": p.seats})], &"", true))
		var pos := _position_row(p.position)
		pos.size_flags_horizontal = Control.SIZE_SHRINK_END
		line.add_child(pos)
		inner.add_child(line)
		if show_reason and p.reason_id != SimContract.NO_ID:
			var rid := p.reason_id
			var b := UiFactory.button(_ctx, UiText.t(&"council.reasons_for_bloc"), false)
			_tag(b, "bloc_reason_%d_%d" % [v.vote_id, rid])
			b.pressed.connect(func() -> void: _request_reason(func(rp: ReasonPanel) -> void: rp.show_record(rid)))
			inner.add_child(b)


func _position_row(position: StringName) -> Control:
	match position:
		CouncilBlocView.POSITION_YES:
			return _direction_row(ReasonGlyph.Kind.UP, "ok", UiTheme.V_LABEL_OK, UiText.t(&"council.vote.for"), false)
		CouncilBlocView.POSITION_NO:
			return _direction_row(ReasonGlyph.Kind.DOWN, "danger", UiTheme.V_LABEL_DANGER,
				UiText.t(&"council.vote.against"), false)
		CouncilBlocView.POSITION_ABSTAIN:
			return _direction_row(ReasonGlyph.Kind.FLAT, "text_muted", UiTheme.V_LABEL_MUTED,
				UiText.t(&"council.vote.abstain"), false)
	return _direction_row(ReasonGlyph.Kind.FLAT, "text_muted", UiTheme.V_LABEL_MUTED,
		UiText.t(&"council.position.undecided"), false)


func _vote_title(v: CouncilVoteView) -> String:
	if v.title_key != &"" and UiText.has(v.title_key):
		return UiText.t(v.title_key)
	return "%s %d" % [UiText.t(&"council.vote_label"), v.vote_id]


func _closes_text(row: CouncilModel.VoteRow) -> String:
	if row.days_left <= 0:
		return UiText.t(&"council.closes_today")
	return UiText.t(&"council.closes_in", {"days": row.days_left})
