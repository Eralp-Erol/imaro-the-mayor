class_name ZoningFlowPanel
extends FlowPanel
## İmar önerisi paneli (ux-flows-v0 §B, T-022): `ZoningFlowModel`in görünümü. Masaüstü ve dokunmatik AYNI bileşenler
## (hedefler `UiContext`ten; hover'a bağlı bilgi yok). Panel yeniden kurulsa da (yön/profil değişimi) akış durumu
## modeldedir ve kaybolmaz.
##
## Okuduğu sim alanları: `plan_state` (parsel satırı: Plansız / Teklif verildi / Planlı ...), `ParcelView.zone`,
## `CommandResult` (ön doğrulama, gönderim), `SimEvent` (sonuç: modelde), `reason_ids` ("Nedenini gör").
## T-043A (D-010): yoğunluk seçenekleri yapılandırma verisidir (Q-024 AÇIK); ÖNİZLEME yalnız `SimFacade.plan_preview`
## sayılarıdır (toplam birim, altyapı yükü, bölge kapasite/boş pay/sığıyor mu); yarar/zarar işareti sim'de yok ->
## "henüz kurulmadı". "Meclis" sözcüğü yalnız gerçek sim bayrağı true iken. Kaynak plan önizlemesi sunmuyorsa (mock)
## bölüm dürüst "kurulu değil" yazar.
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
var _warning: Label = null
var _notes: Label = null
var _use_buttons: Dictionary = {}
var _parcels_open: bool = false


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
	_warning = null
	_notes = null
	_body.add_child(UiFactory.label(UiText.t(&"zoning.step_line", {"n": model.step_number(),
		"total": ZoningFlowModel.step_count(), "name": UiText.t(model.step_name_key())}), UiTheme.V_LABEL_MUTED, true))
	_add_area()
	if model.parcel_ids.is_empty():
		_restore_focus(focus_role)
		return
	_add_uses()
	_add_density()
	_add_preview()
	_add_send_and_status()
	_body.add_child(_muted(UiText.t(&"zoning.no_instant_building")))
	_restore_focus(focus_role)


func _add_area() -> void:
	_body.add_child(_section(&"zoning.area_parcels"))
	if model.parcel_ids.is_empty():
		_body.add_child(UiFactory.label(UiText.t(&"zoning.pick_parcel"), &"", true))
		_body.add_child(_muted(UiText.t(&"zoning.area_add_hint")))
		_add_municipal_entry()
		return
	var views := _facade.parcel_views(model.parcel_ids)
	var by_id := {}
	for v in views:
		by_id[v.id] = v
	if model.municipal_mode:
		_add_municipal_summary(by_id)
	else:
		for id in model.parcel_ids:
			_body.add_child(_parcel_row(id, by_id.get(id) as ParcelView))
	if model.municipal_mode:
		var mode_note := _muted(UiText.t(&"zoning.municipal.mode"))
		_tag(mode_note, "municipal_mode")
		_body.add_child(mode_note)
	elif not model.is_locked():
		_add_municipal_entry()
	if not model.is_locked():
		var limit := model.max_parcels()
		if limit > 0:
			_body.add_child(_muted(UiText.t(&"zoning.too_many", {"max": limit}) if model.at_parcel_limit()
				else UiText.t(&"zoning.count_line", {"n": model.parcel_ids.size(), "max": limit})))
		_body.add_child(_muted(UiText.t(&"zoning.municipal.no_mix" if model.municipal_mode
				else &"zoning.area_add_hint")))
		if model.parcel_ids.size() > 1 or model.municipal_mode:
			var clear := UiFactory.button(_ctx, UiText.t(&"zoning.clear_area"), false)
			_tag(clear, "area_clear")
			clear.pressed.connect(func() -> void:
				model.clear_area()
				_render())
			_body.add_child(clear)


## D-018: yalnız sim `municipal_lands()` içinde uygun satır varsa görünür (sayı gerçek). Alan boşken düğme, sıradan
## parsel varken yalnız "önce alanı temizleyin" notu.
func _add_municipal_entry() -> void:
	if model.is_locked():
		return
	var n := model.municipal_available_ids().size()
	if n == 0:
		return
	if not model.parcel_ids.is_empty():
		_body.add_child(_muted(UiText.t(&"zoning.municipal.clear_first", {"n": UiText.number(n)})))
		return
	var b := UiFactory.button(_ctx, UiText.t(&"zoning.municipal.open", {"n": UiText.number(n)}), false)
	# B-024: uzun metin sarılır; asgari genişlik panel genişliğini aşmaz.
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag(b, "municipal_open")
	b.pressed.connect(open_municipal_land)
	_body.add_child(b)


## B-023: belediye arazisi tek özet satırı (parsel sayısı + sim `area_m2` toplamı); parsel listesi katlanabilir
## (varsayılan kapalı) ki kullanım seçimi ve gönder düğmesi ilk ekranda kalsın.
func _add_municipal_summary(by_id: Dictionary) -> void:
	var total_m2 := 0
	var wanted := {}
	for id in model.parcel_ids:
		wanted[id] = true
	for land in _facade.municipal_lands():
		if wanted.has(land.id):
			total_m2 += land.area_m2
	var n := UiText.number(model.parcel_ids.size())
	var text := UiText.t(&"zoning.municipal.summary_area", {"n": n, "m2": UiText.number(total_m2)}) \
		if total_m2 > 0 else UiText.t(&"zoning.municipal.summary", {"n": n})
	var summary := UiFactory.label(text, &"", true)
	_tag(summary, "municipal_summary")
	_body.add_child(summary)
	var toggle := UiFactory.button(_ctx, UiText.t(&"zoning.municipal.hide_list" if _parcels_open
		else &"zoning.municipal.show_list"), false, true)
	toggle.button_pressed = _parcels_open
	_tag(toggle, "municipal_list_toggle")
	toggle.pressed.connect(func() -> void:
		_parcels_open = not _parcels_open
		_render())
	_body.add_child(toggle)
	if _parcels_open:
		for id in model.parcel_ids:
			_body.add_child(_parcel_row(id, by_id.get(id) as ParcelView))


func open_municipal_land() -> bool:
	var ok := model.use_municipal_land()
	_render()
	return ok


func _parcel_row(id: int, view: ParcelView) -> Control:
	# Kompakt satır (çok parselli teklifte önizleme ekranda kalsın): başlık + plan durumu aynı satırda, "Çıkar" sağda.
	var card_parts := _card()
	var card: PanelContainer = card_parts[0]
	var inner: VBoxContainer = card_parts[1]
	var head := HBoxContainer.new()
	var plan := model.plan_state_of(id)
	var plan_text := PlanStateText.label(plan, true)
	if model.municipal_mode:
		# Belediye arazisi yapılı değildir ("Yapılı parsel" yanlış olur): sim `municipal_lands()` satırı.
		plan_text = UiText.t(&"zoning.municipal.row")
	var title_text := UiText.humanize(SimContract.parcel_ref(id))
	if plan_text != "":
		title_text += " · " + plan_text
	elif view != null:
		title_text += " · %s" % (UiText.humanize(view.zone) if view.zone != &"" else UiText.t(&"common.unknown"))
		if view.pending_zone != &"":
			title_text += " · %s: %s" % [UiText.t(&"zoning.pending_zone"), UiText.humanize(view.pending_zone)]
	var title := UiFactory.label(title_text, UiTheme.V_LABEL_DANGER if PlanStateText.needs_plan(plan) else &"", true)
	_tag(title, "plan_state_%d" % id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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


## Yoğunluk seçenekleri (yalnız hazırlıkta): "Varsayılan" + yapılandırma seçenekleri; seçim komuta `density` gider.
func _add_density() -> void:
	if model.is_locked() or model.land_use == &"":
		return
	var options := ZoningFlowModel.density_options()
	if options.is_empty():
		return
	_body.add_child(_section(&"zoning.density.title"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", int(_ctx.spacing()))
	flow.add_theme_constant_override(&"v_separation", int(_ctx.spacing()))
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(flow)
	var choices: Array[int] = [-1]
	choices.append_array(options)
	for pm in choices:
		var text := UiText.t(&"zoning.density.default") if pm < 0 else UiText.t(&"zoning.density.value",
				{"pct": UiText.number(pm / 10)})
		var b := UiFactory.button(_ctx, text, true, true)
		_tag(b, "density_%d" % pm)
		b.set_pressed_no_signal(pm == model.density_pm)
		b.pressed.connect(choose_density.bind(pm))
		flow.add_child(b)
	_body.add_child(_muted(UiText.t(&"zoning.density.note")))


func choose_density(pm: int) -> void:
	model.choose_density(pm)
	_render()


## Önizleme: YALNIZ `plan_preview` sayıları. Sim'den gelmeyen hiçbir sayı yazılmaz.
func _add_preview() -> void:
	var pv := model.preview()
	if pv == null or model.is_locked():
		return
	_body.add_child(_section(&"zoning.preview.title"))
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	_tag(parts[0], "plan_preview")
	if not pv.ok:
		var reason := UiText.t(pv.reason) if UiText.has(pv.reason) else UiText.humanize(String(pv.reason))
		inner.add_child(_muted(UiText.t(&"zoning.preview.unavailable", {"reason": reason})))
	else:
		inner.add_child(UiFactory.label(UiText.t(&"zoning.preview.units", {"n": UiText.number(pv.total_units)}),
				UiTheme.V_LABEL_HEADING, true))
		inner.add_child(UiFactory.label(UiText.t(&"zoning.preview.infra",
				{"n": UiText.number(pv.total_infra_units)}), &"", true))
		if pv.total_units == 0:
			inner.add_child(_muted(UiText.t(&"zoning.preview.no_units")))
		for r: Dictionary in pv.regions:
			inner.add_child(_muted(UiText.t(&"zoning.preview.region", {"code": String(r["code"]),
					"cap": UiText.number(int(r["capacity_units"])), "load": UiText.number(int(r["load_units"])),
					"head": UiText.number(int(r["headroom_units"]))})))
			inner.add_child(UiFactory.label(UiText.t(&"zoning.preview.fits" if bool(r["fits"])
					else &"zoning.preview.exceeds"), UiTheme.V_LABEL_MUTED if bool(r["fits"])
					else UiTheme.V_LABEL_DANGER, true))
		inner.add_child(_muted(UiText.t(&"zoning.preview.effect")))
		inner.add_child(_muted(UiText.t(&"zoning.preview.caveat")))
	_body.add_child(parts[0])


func _add_send_and_status() -> void:
	if model.phase() == ZoningFlowModel.Phase.READY:
		_body.add_child(UiFactory.label(UiText.t(&"zoning.summary", {"parcels": _area_text(),
			"use": UiText.t(model.land_use)}), &"", true))
	_add_honesty_notes()
	if not model.is_locked():
		_body.add_child(_muted(model.path_text()))
		_add_route_note()
		_send = ActionButton.create(_ctx, model.submit_label(), true)
		_tag(_send.button, "send")
		_send.set_enabled(model.can_send(), model.send_block_reason())
		_send.pressed.connect(send)
		_body.add_child(_send)
	if model.is_locked():
		_add_route_note()
	_status = UiFactory.label(model.status_text(), &"", true)
	_status.visible = not _status.text.is_empty()
	if model.phase() == ZoningFlowModel.Phase.REFUSED or model.phase() == ZoningFlowModel.Phase.VOTE_FAILED:
		_status.theme_type_variation = UiTheme.V_LABEL_DANGER
	_body.add_child(_status)
	_add_followups()


## SIM-12: planın meclise gitme/gitmeme nedeni (eşik sim'den); eşik yoksa satır yok. Gönderimden sonra da kalır.
func _add_route_note() -> void:
	var text := model.route_text()
	if text != "":
		var note := _muted(text)
		_tag(note, "route_note")
		_body.add_child(note)


func route_note_text() -> String:
	return model.route_text()


## Onay adımında (gönderimden önce) yapılı parsel uyarısı ve "özel yatırım yapılmaz" notu; sim davranışından türer.
## Gönderim sonrası yapı uyarısı durum satırında (model.status_text) tekrar yazılır.
func _add_honesty_notes() -> void:
	if model.land_use == &"":
		return
	var note := model.no_private_use_note()
	if note != "":
		_notes = UiFactory.label(note, UiTheme.V_LABEL_MUTED, true)
		_body.add_child(_notes)
	if not model.is_locked():
		var warn := model.structure_warning()
		if warn != "":
			_warning = UiFactory.label(warn, UiTheme.V_LABEL_DANGER, true)
			_body.add_child(_warning)


func warning_text() -> String:
	return _warning.text if _warning != null and is_instance_valid(_warning) else ""


func note_text() -> String:
	return _notes.text if _notes != null and is_instance_valid(_notes) else ""


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
	if model.municipal_mode:
		return UiText.t(&"zoning.municipal.summary", {"n": UiText.number(model.parcel_ids.size())})
	var parts := PackedStringArray()
	for id in model.parcel_ids:
		parts.append(UiText.humanize(SimContract.parcel_ref(id)))
	return ", ".join(parts)
