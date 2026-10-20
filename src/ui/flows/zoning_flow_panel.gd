class_name ZoningFlowPanel
extends FlowPanel
## İmar önerisi paneli (ux-flows-v0 §B, T-022): `ZoningFlowModel`in görünümü. Masaüstü ve dokunmatik AYNI bileşenler
## (hedefler `UiContext`ten; hover'a bağlı bilgi yok). Panel yeniden kurulsa da (yön/profil değişimi) akış durumu
## modeldedir ve kaybolmaz.
##
## Okuduğu sim alanları: `ParcelView.zone/pending_zone` (alan satırları), `CommandResult` (ön doğrulama, gönderim),
## `SimEvent` (sonuç: applied/rejected/vote/parcel.changed — modelde), `reason_ids` ("Nedenini gör").
## Etki önizlemesi (`ZoningPreview`) sözleşmede yok (v1.1 isteği): bölüm GİZLİ, UI tahmin üretmez.
## Yoğunluk/yükseklik alanları da yok: sim birim/aralık vermiyor, değer uydurulmaz (v1.1 `ZoningOptions`).
## CAN-03: yalnız imar KOŞULU önerilir; metin bunu söyler.

signal submitted(result: CommandResult)

var model: ZoningFlowModel = null
## Salt okunur kısayollar (ui_lab/testler): modelin son ön doğrulaması ve gönderimi.
var last_validation: CommandResult:
	get:
		return model.last_validation
var last_submit: CommandResult:
	get:
		return model.last_submit

var _verdict: Label = null
var _send: ActionButton = null
var _status: Label = null
var _use_buttons: Dictionary = {}


static func create(ctx: UiContext, facade: SimFacade, flow: ZoningFlowModel) -> ZoningFlowPanel:
	var p := ZoningFlowPanel.new()
	p.model = flow
	p._setup_flow(ctx, facade)
	p._render()
	return p


# --- Dış API (ui_lab/testler; model fiilleri + yeniden çizim) ---

func choose_use(use: StringName) -> void:
	model.choose_use(use)
	_render()


func send() -> void:
	if model.send():
		submitted.emit(model.last_submit)
	_render()


func add_parcel(parcel_id: int) -> bool:
	var added := model.add_parcel(parcel_id)
	_render()
	return added


func handle_event(event: SimEvent) -> void:
	model.handle_event(event)
	_render()


func verdict_text() -> String:
	return _verdict.text if _verdict != null and _verdict.visible else ""


## Gönderim/sonuç durumunun görünen metni (yoksa "").
func queued_text() -> String:
	return _status.text if _status != null and _status.visible else ""


func send_button() -> ActionButton:
	return _send


func use_button(use: StringName) -> Button:
	return _use_buttons.get(use) as Button


# --- Çizim ---

func _render() -> void:
	if _body == null:
		return
	var focus_role := _begin_render()
	_use_buttons.clear()
	_verdict = null
	_send = null
	_status = null
	_body.add_child(UiFactory.label(UiText.t(&"zoning.step_line", {"n": model.step_number(),
		"total": ZoningFlowModel.step_count(), "name": UiText.t(model.step_name_key())}), UiTheme.V_LABEL_MUTED, true))
	_add_area()
	if model.parcel_ids.is_empty():
		_restore_focus(focus_role)
		return
	_add_uses()
	_add_send_and_status()
	_body.add_child(_muted(UiText.t(&"zoning.no_instant_building")))
	_restore_focus(focus_role)


func _add_area() -> void:
	_body.add_child(_section(&"zoning.area_parcels"))
	if model.parcel_ids.is_empty():
		_body.add_child(UiFactory.label(UiText.t(&"zoning.pick_parcel"), &"", true))
		_body.add_child(_muted(UiText.t(&"zoning.area_add_hint")))
		return
	var views := _facade.parcel_views(model.parcel_ids)
	var by_id := {}
	for v in views:
		by_id[v.id] = v
	for id in model.parcel_ids:
		_body.add_child(_parcel_row(id, by_id.get(id) as ParcelView))
	if not model.is_locked():
		_body.add_child(_muted(UiText.t(&"zoning.area_add_hint")))
		if model.parcel_ids.size() > 1:
			var clear := UiFactory.button(_ctx, UiText.t(&"zoning.clear_area"), false)
			_tag(clear, "area_clear")
			clear.pressed.connect(func() -> void:
				model.clear_area()
				_render())
			_body.add_child(clear)


func _parcel_row(id: int, view: ParcelView) -> Control:
	var card_parts := _card()
	var card: PanelContainer = card_parts[0]
	var inner: VBoxContainer = card_parts[1]
	var head := HBoxContainer.new()
	var title := UiFactory.label(UiText.humanize(SimContract.parcel_ref(id)), UiTheme.V_LABEL_TITLE, true)
	head.add_child(title)
	if not model.is_locked():
		var remove := UiFactory.button(_ctx, UiText.t(&"zoning.remove_parcel"), false)
		_tag(remove, "area_remove_%d" % id)
		remove.size_flags_horizontal = Control.SIZE_SHRINK_END
		remove.pressed.connect(func() -> void:
			model.remove_parcel(id)
			_render())
		head.add_child(remove)
	inner.add_child(head)
	if view != null:
		inner.add_child(_pair(UiText.t(&"zoning.current_zone"), UiText.humanize(view.zone) if view.zone != &""
			else UiText.t(&"common.unknown")))
		inner.add_child(_pair(UiText.t(&"zoning.pending_zone"), UiText.humanize(view.pending_zone)
			if view.pending_zone != &"" else UiText.t(&"inspector.none_pending")))
	else:
		inner.add_child(_muted(UiText.t(&"common.unknown")))
	return card


func _add_uses() -> void:
	_body.add_child(_section(&"zoning.use"))
	if model.is_locked():
		# Gönderilmiş öneri: seçenekler değil, gönderilen kullanım gösterilir (devre dışı düğme yığını yok).
		_body.add_child(UiFactory.label(UiText.t(model.land_use), &"", true))
		_verdict = null
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", int(_ctx.spacing()))
	flow.add_theme_constant_override(&"v_separation", int(_ctx.spacing()))
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(flow)
	for use in UiConfig.land_uses():
		var b := UiFactory.button(_ctx, UiText.t(use), true, true)
		_tag(b, "use_%s" % use)
		b.set_pressed_no_signal(use == model.land_use)
		b.pressed.connect(choose_use.bind(use))
		_use_buttons[use] = b
		flow.add_child(b)
	_verdict = UiFactory.label(model.verdict_text(), &"", true)
	_verdict.visible = model.last_validation != null
	if model.last_validation != null and model.last_validation.is_rejected():
		_verdict.theme_type_variation = UiTheme.V_LABEL_DANGER
	_body.add_child(_verdict)


func _add_send_and_status() -> void:
	if model.phase() == ZoningFlowModel.Phase.READY:
		_body.add_child(UiFactory.label(UiText.t(&"zoning.summary", {"parcels": _area_text(),
			"use": UiText.t(model.land_use)}), &"", true))
	if not model.is_locked():
		_body.add_child(_muted(model.path_text()))
		_send = ActionButton.create(_ctx, model.submit_label(), true)
		_tag(_send.button, "send")
		_send.set_enabled(model.can_send(), model.send_block_reason())
		_send.pressed.connect(send)
		_body.add_child(_send)
	_status = UiFactory.label(model.status_text(), &"", true)
	_status.visible = not _status.text.is_empty()
	if model.phase() == ZoningFlowModel.Phase.REFUSED or model.phase() == ZoningFlowModel.Phase.VOTE_FAILED:
		_status.theme_type_variation = UiTheme.V_LABEL_DANGER
	_body.add_child(_status)
	_add_followups()


func _add_followups() -> void:
	if model.can_open_reason():
		var why := UiFactory.button(_ctx, UiText.t(&"alert.open_reason"), true)
		_tag(why, "open_reason")
		why.pressed.connect(_on_reason_pressed)
		_body.add_child(why)
	if model.vote_ref != &"":
		var vote := UiFactory.button(_ctx, UiText.t(&"zoning.see_vote"), false)
		_tag(vote, "open_vote")
		vote.pressed.connect(func() -> void: navigate_requested.emit(&"council"))
		_body.add_child(vote)
	if model.is_finished():
		var again := UiFactory.button(_ctx, UiText.t(&"zoning.new_proposal"), true)
		_tag(again, "new_proposal")
		again.pressed.connect(func() -> void:
			model.reset()
			_render())
		_body.add_child(again)


func _on_reason_pressed() -> void:
	if model.refusal_event != null:
		var event := model.refusal_event
		_request_reason(func(p: ReasonPanel) -> void: p.show_event(event))
	elif model.refusal_result != null:
		var result := model.refusal_result
		_request_reason(func(p: ReasonPanel) -> void: p.show_command_result(result))
	elif not model.reason_ids.is_empty():
		var ids := model.reason_ids
		_request_reason(func(p: ReasonPanel) -> void: p.show_reason_ids(ids))


func _area_text() -> String:
	var parts := PackedStringArray()
	for id in model.parcel_ids:
		parts.append(UiText.humanize(SimContract.parcel_ref(id)))
	return ", ".join(parts)
