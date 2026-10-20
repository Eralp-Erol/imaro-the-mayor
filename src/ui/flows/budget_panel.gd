class_name BudgetPanel
extends FlowPanel
## Bütçe paneli (ux-flows-v0 §F, CAN-06, T-022): `BudgetView` -> özet + kalemler + (kilitli değilse) tahsis düzenleyici.
## Para birimsiz tamsayıdır ve YALNIZ `UiText.money` ile yapılandırmadan (`¤` yer tutucusu) biçimlenir (Q-003).
## Kurulmamışsa (`SimSections.budget_built` false) yalnız "Henüz kurulmadı" durumu görünür; düzenleyici yoktur.
##
## Okuduğu sim alanları: `BudgetView.period/status/revenue/balance/lines[line_key, amount, proposed, actual]/
## pending_vote_id/reason_ids`. Öngörü ve hizmet kapasitesi sözleşmede YOK (v1.1): bölüm gizli, tahmin uydurulmaz.
## Düzenleme: kalem başına +/- adımlayıcı (masaüstü ve dokunmatik aynı); öneri `budget.propose` komutudur, önce
## `validate_command` (gerekçeli ret ekranda), sonra gönder; sonuç meclis oylamasıdır (SIM-05) ve oylama durumundayken
## düzenleme kilitlidir (sim aynı konuda ikinci öneriyi reddeder).

var model: BudgetModel = null
var draft: BudgetDraft = null


static func create(ctx: UiContext, facade: SimFacade, budget_draft: BudgetDraft) -> BudgetPanel:
	var p := BudgetPanel.new()
	p.draft = budget_draft
	p._setup_flow(ctx, facade)
	p._render()
	return p


func signature_now() -> String:
	var snap := _facade.snapshot()
	return "%s|%s|%d" % [var_to_str(snap.budget.to_dict()), SimSections.budget_built(snap),
		draft.last_submit.command_id if draft.last_submit != null else -1]


func refresh() -> void:
	refresh_if_changed(signature_now())


func handle_event(event: SimEvent) -> void:
	draft.handle_event(event)
	_render()


func step(key: StringName, direction: int) -> void:
	draft.step(key, direction)
	_render()


func send() -> void:
	if draft.last_validation == null or draft.last_validation.is_rejected() or not draft.has_changes():
		return
	var result := _facade.submit_command(draft.command())
	draft.last_submit = result
	draft.refusal_event = null
	if not result.is_rejected():
		draft.reset()  # bekleyen öneri artık sim'dedir; taslak yürürlükteki tutarlara döner
	_render()


func _render() -> void:
	if _body == null:
		return
	_signature = signature_now()
	var focus_role := _begin_render()
	var snap := _facade.snapshot()
	model = null
	if not SimSections.budget_built(snap):
		state_view.show_not_built(&"budget.not_built")
		return
	state_view.show_normal()
	model = BudgetModel.build(snap.budget)
	draft.sync(model)
	_add_summary()
	_add_lines(not model.is_locked())
	if model.is_locked():
		_add_locked()
	else:
		_add_editor(snap.tick())
	_restore_focus(focus_role)


func _add_summary() -> void:
	_body.add_child(UiFactory.label("%s · %s" % [UiText.t(&"budget.period", {"n": model.period}),
		UiText.t(StringName("budget.status.%s" % model.status))], UiTheme.V_LABEL_TITLE, true))
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(_pair(UiText.t(&"budget.income"), UiText.money(model.revenue)))
	inner.add_child(_pair(UiText.t(&"budget.expenses_total"), UiText.money(model.expenses)))
	inner.add_child(_pair(UiText.t(&"budget.balance"), UiText.money(model.balance)))
	if model.is_debt():
		inner.add_child(_direction_row(ReasonGlyph.Kind.WARN, "danger", UiTheme.V_LABEL_DANGER,
			UiText.t(&"budget.debt")))
	_body.add_child(parts[0])
	if (model.status == BudgetView.STATUS_APPROVED or model.status == BudgetView.STATUS_REJECTED) \
			and not model.reason_ids.is_empty():
		var ids := model.reason_ids
		var why := UiFactory.button(_ctx, UiText.t(&"alert.open_reason"), false)
		_tag(why, "budget_reason")
		why.pressed.connect(func() -> void: _request_reason(func(p: ReasonPanel) -> void: p.show_reason_ids(ids)))
		_body.add_child(why)


func _add_lines(editable: bool) -> void:
	_body.add_child(_section(&"budget.edit_title" if editable else &"budget.lines"))
	if editable:
		_body.add_child(_muted(UiText.t(&"budget.step_hint", {"money": UiPrefs.budget_step()})))
	for r in model.rows:
		var parts := _card()
		var inner: VBoxContainer = parts[1]
		inner.add_child(UiFactory.label(UiText.humanize(String(r.key)), UiTheme.V_LABEL_TITLE, true))
		inner.add_child(_pair(UiText.t(&"budget.col.current"), UiText.money(r.amount)))
		inner.add_child(_muted(UiText.t(&"budget.share")))
		var share := HBoxContainer.new()
		share.add_child(MeterBar.create(_ctx, r.share_permille))
		var pct := UiFactory.label(UiText.t(&"format.percent", {"value": roundi(float(r.share_permille) / 10.0)}))
		pct.autowrap_mode = TextServer.AUTOWRAP_OFF
		share.add_child(pct)
		inner.add_child(share)
		if r.delta() != 0:
			inner.add_child(_pair(UiText.t(&"budget.col.proposed"), "%s (%s)" % [UiText.money(r.proposed),
				_signed_money(r.delta())]))
		if r.actual != 0:
			inner.add_child(_pair(UiText.t(&"budget.col.actual"), UiText.money(r.actual)))
		if editable:
			_add_stepper(inner, r.key)
		_body.add_child(parts[0])


func _add_locked() -> void:
	_body.add_child(UiFactory.label(UiText.t(&"budget.vote_pending"), UiTheme.V_LABEL_TITLE, true))
	_body.add_child(_muted(UiText.t(&"budget.apply_note")))
	var vote := UiFactory.button(_ctx, UiText.t(&"budget.open_vote"), true)
	_tag(vote, "open_vote")
	vote.pressed.connect(func() -> void: navigate_requested.emit(&"council"))
	_body.add_child(vote)


func _add_editor(current_tick: int) -> void:
	var changed := draft.has_changes()
	_body.add_child(UiFactory.label(UiText.t(&"budget.pending_total") + ": " + _signed_money(draft.total_delta())
		if changed else UiText.t(&"budget.no_changes"), &"", true))
	if changed:
		draft.last_validation = _facade.validate_command(draft.command())
	if draft.last_validation != null and draft.last_validation.is_rejected():
		_body.add_child(UiFactory.label(UiText.reject_reason(draft.last_validation.reason_key,
			draft.last_validation.args), UiTheme.V_LABEL_DANGER, true))
	if changed:
		var reset := UiFactory.button(_ctx, UiText.t(&"budget.reset_draft"), false)
		_tag(reset, "reset")
		reset.pressed.connect(func() -> void:
			draft.reset()
			_render())
		_body.add_child(reset)
	var send_btn := ActionButton.create(_ctx, UiText.t(&"budget.submit"), true)
	_tag(send_btn.button, "send")
	var in_flight := draft.in_flight(current_tick)
	var blocked := ""
	if in_flight:
		blocked = UiText.t(&"zoning.queued")
	elif not changed:
		blocked = UiText.t(&"budget.submit_need_change")
	elif draft.last_validation != null and draft.last_validation.is_rejected():
		blocked = UiText.t(&"zoning.validate.rejected")
	send_btn.set_enabled(blocked.is_empty(), blocked)
	send_btn.pressed.connect(send)
	_body.add_child(send_btn)
	_add_result()


func _add_result() -> void:
	if draft.refusal_event != null:
		var event := draft.refusal_event
		_body.add_child(UiFactory.label("%s: %s" % [UiText.t(&"zoning.outcome.rejected"),
			UiText.reject_reason(event.message_key, event.args)], UiTheme.V_LABEL_DANGER, true))
		var why := UiFactory.button(_ctx, UiText.t(&"alert.open_reason"), true)
		_tag(why, "open_reason")
		why.pressed.connect(func() -> void: _request_reason(func(p: ReasonPanel) -> void: p.show_event(event)))
		_body.add_child(why)
	elif draft.last_submit != null and draft.last_submit.is_rejected():
		_body.add_child(UiFactory.label("%s: %s" % [UiText.t(&"zoning.rejected_now"),
			UiText.reject_reason(draft.last_submit.reason_key, draft.last_submit.args)], UiTheme.V_LABEL_DANGER, true))
	elif draft.last_submit != null:
		_body.add_child(UiFactory.label(UiText.t(&"budget.queued"), &"", true))


func _add_stepper(inner: VBoxContainer, key: StringName) -> void:
	var row := HBoxContainer.new()
	var down := UiFactory.button(_ctx, "%s %s" % [UiText.MINUS, UiText.t(&"budget.step_down")], true)
	down.tooltip_text = "%s: %s" % [UiText.t(&"budget.step_down"), UiText.humanize(String(key))]
	down.disabled = not draft.can_step_down(key)
	_tag(down, "step_down_%s" % key)
	down.pressed.connect(step.bind(key, -1))
	row.add_child(down)
	var value_box := VBoxContainer.new()
	value_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := UiFactory.label(UiText.t(&"budget.draft_value", {"value": UiText.money(draft.amount(key))}),
		UiTheme.V_LABEL_TITLE, true)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_box.add_child(value)
	if draft.delta(key) != 0:
		var delta := _muted(_signed_money(draft.delta(key)))
		delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_box.add_child(delta)
	row.add_child(value_box)
	var up := UiFactory.button(_ctx, "+ %s" % UiText.t(&"budget.step_up"), true)
	up.tooltip_text = "%s: %s" % [UiText.t(&"budget.step_up"), UiText.humanize(String(key))]
	_tag(up, "step_up_%s" % key)
	up.pressed.connect(step.bind(key, 1))
	row.add_child(up)
	inner.add_child(row)


func _signed_money(amount: int) -> String:
	if amount == 0:
		return UiText.money(0)
	var key := &"format.delta_plus" if amount > 0 else &"format.delta_minus"
	return UiText.t(key, {"value": UiText.money(absi(amount))})
