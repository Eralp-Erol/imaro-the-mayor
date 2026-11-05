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
## Teklif alanındaki parseller (her çizimde; haritada vurgu için, yalnız görünüm). Dedupe alıcıdadır.
signal area_changed(parcel_ids: PackedInt64Array)

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
## Çekmece kipi (dokunmatik): eylem alanı altlıkta, genişken alan | kullanım iki sütun. Dışında `_target` = gövde.
var _target: Container = null
var _cols: BoxContainer = null
var _left: VBoxContainer = null
var _right: VBoxContainer = null
var _wide: bool = false
var _actions_row: HFlowContainer = null


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


## Çekmece genişse (yatay iPad/geniş dikey) alan ve kullanım yan yana, değilse alt alta (içerik yeniden çizilmez).
func set_wide_layout(wide: bool) -> void:
	_wide = wide
	if _cols != null:
		_cols.vertical = not wide


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
	_target = _body
	_cols = null
	_actions_row = null
	if _sticky:
		_cols = BoxContainer.new()
		_cols.vertical = not _wide
		_cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cols.add_theme_constant_override(&"separation", int(_ctx.spacing()) * 2)
		_left = _column()
		_right = _column()
		_right.size_flags_stretch_ratio = 1.4   # kullanım düğmeleri tek satıra sığsın
		_cols.add_child(_left)
		_cols.add_child(_right)
		_body.add_child(_cols)
		_target = _left
	_put(UiFactory.label(UiText.t(&"zoning.step_line", {"n": model.step_number(),
		"total": ZoningFlowModel.step_count(), "name": UiText.t(model.step_name_key())}), UiTheme.V_LABEL_MUTED, true))
	_add_area()
	area_changed.emit(model.parcel_ids)
	if model.parcel_ids.is_empty():
		_restore_focus(focus_role)
		return
	if _sticky:
		_target = _right
	_add_uses()
	_add_density()
	_target = _body
	_add_preview()
	_add_send_and_status()
	_put(_muted(UiText.t(&"zoning.no_instant_building")))
	_restore_focus(focus_role)


func _column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_space_for_touch(col)
	return col


func _put(child: Node) -> void:
	_target.add_child(child)


## Birincil eylem alanı: çekmecede altlık (kaydırma dışı), aksi halde gövde.
## Alan eylemleri (liste aç/kapa, alanı temizle): çekmecede tek satıra yan yana dizilir (dikey yer kazancı).
func _area_action(btn: Button) -> void:
	if not _sticky:
		_put(btn)
		return
	if _actions_row == null:
		_actions_row = _button_row()
		_put(_actions_row)
	_actions_row.add_child(btn)


func _act(child: Node) -> void:
	if _sticky:
		footer.add_child(child)
	else:
		_body.add_child(child)


func _add_area() -> void:
	_put(_section(&"zoning.area_parcels"))
	if model.parcel_ids.is_empty():
		_put(UiFactory.label(UiText.t(&"zoning.pick_parcel"), &"", true))
		_put(_muted(UiText.t(&"zoning.area_add_hint")))
		_add_municipal_entry()
		return
	var views := _facade.parcel_views(model.parcel_ids)
	var by_id := {}
	for v in views:
		by_id[v.id] = v
	if model.municipal_mode:
		_add_municipal_summary(by_id)
	elif ZoningParcelText.folds(model.parcel_ids.size()):
		_add_folded_area(by_id)
	else:
		for i in model.parcel_ids.size():
			_put(_parcel_row(model.parcel_ids[i], by_id.get(model.parcel_ids[i]) as ParcelView, i + 1))
	if model.municipal_mode:
		var mode_note := _muted(UiText.t(&"zoning.municipal.mode"))
		_tag(mode_note, "municipal_mode")
		_put(mode_note)
	elif not model.is_locked():
		_add_municipal_entry()
	if not model.is_locked():
		# Sıkı düzen (dokunmatikte kullanım seçimi ve gönder ilk ekranda kalsın): özet satırı zaten sayıyı söyler;
		# ipucu/sayaç yalnız küçük alanda, sınırda uyarı her zaman.
		var compact := ZoningParcelText.folds(model.parcel_ids.size()) or model.municipal_mode
		var limit := model.max_parcels()
		if limit > 0 and (model.at_parcel_limit() or not compact):
			_put(_muted(UiText.t(&"zoning.too_many", {"max": limit}) if model.at_parcel_limit()
				else UiText.t(&"zoning.count_line", {"n": model.parcel_ids.size(), "max": limit})))
		if not compact:
			_put(_muted(UiText.t(&"zoning.area_add_hint")))
		if model.parcel_ids.size() > 1 or model.municipal_mode:
			var clear := UiFactory.button(_ctx, UiText.t(&"zoning.clear_area"), false)
			_tag(clear, "area_clear")
			clear.pressed.connect(func() -> void:
				model.clear_area()
				_render())
			_area_action(clear)


## D-018: yalnız sim `municipal_lands()` içinde uygun satır varsa görünür (sayı gerçek). Alan boşken düğme, sıradan
## parsel varken yalnız "önce alanı temizleyin" notu.
func _add_municipal_entry() -> void:
	if model.is_locked():
		return
	var n := model.municipal_available_ids().size()
	if n == 0:
		return
	if not model.parcel_ids.is_empty():
		_put(_muted(UiText.t(&"zoning.municipal.clear_first", {"n": UiText.number(n)})))
		return
	var b := UiFactory.button(_ctx, UiText.t(&"zoning.municipal.open", {"n": UiText.number(n)}), false)
	# B-024: uzun metin sarılır; asgari genişlik panel genişliğini aşmaz.
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag(b, "municipal_open")
	b.pressed.connect(open_municipal_land)
	_act(b)   # çekmecede boş alanın birincil eylemi: altlıkta, her zaman görünür


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
	_put(summary)
	var toggle := UiFactory.button(_ctx, UiText.t(&"zoning.municipal.hide_list" if _parcels_open
		else &"zoning.municipal.show_list"), false, true)
	toggle.button_pressed = _parcels_open
	_tag(toggle, "municipal_list_toggle")
	toggle.pressed.connect(func() -> void:
		_parcels_open = not _parcels_open
		_render())
	_area_action(toggle)
	if _parcels_open:
		for i in model.parcel_ids.size():
			_put(_parcel_row(model.parcel_ids[i], by_id.get(model.parcel_ids[i]) as ParcelView, i + 1))


## Çok parselli sıradan teklif: tek özet satırı (parsel sayısı, sim `area_m2` toplamı, bölge kodları) + katlanır liste.
func _add_folded_area(by_id: Dictionary) -> void:
	var summary := UiFactory.label(ZoningParcelText.summary(model.parcel_ids.size(), _views_in_order(by_id)), &"", true)
	_tag(summary, "area_summary")
	_put(summary)
	# Katlı listede parsel durumları (ör. "reddedildi") görünür kalsın: sim plan durumu etiketine göre sayım.
	var tally := {}
	for id in model.parcel_ids:
		var state_text := PlanStateText.label(model.plan_state_of(id), true)
		if state_text != "":
			tally[state_text] = int(tally.get(state_text, 0)) + 1
	var tally_parts := PackedStringArray()
	for state_text: String in tally:
		tally_parts.append(UiText.t(&"zoning.state_tally", {"label": state_text, "n": UiText.number(tally[state_text])}))
	if not tally_parts.is_empty():
		var line := _muted(" · ".join(tally_parts))
		_tag(line, "area_states")
		_put(line)
	var toggle := UiFactory.button(_ctx, UiText.t(&"zoning.municipal.hide_list" if _parcels_open
		else &"zoning.municipal.show_list"), false, true)
	toggle.button_pressed = _parcels_open
	_tag(toggle, "area_list_toggle")
	toggle.pressed.connect(func() -> void:
		_parcels_open = not _parcels_open
		_render())
	_area_action(toggle)
	if _parcels_open:
		for i in model.parcel_ids.size():
			_put(_parcel_row(model.parcel_ids[i], by_id.get(model.parcel_ids[i]) as ParcelView, i + 1))


func _views_in_order(by_id: Dictionary) -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	for id in model.parcel_ids:
		var v := by_id.get(id) as ParcelView
		if v != null:
			out.append(v)
	return out


func open_municipal_land() -> bool:
	var ok := model.use_municipal_land()
	_render()
	return ok


func _parcel_row(id: int, view: ParcelView, ordinal: int) -> Control:
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
	var title_text := ZoningParcelText.row_head(ordinal, view)
	if plan_text != "":
		title_text += " · " + plan_text
	elif view != null:
		title_text += " · %s" % (UiText.humanize(view.zone) if view.zone != &"" else UiText.t(&"common.unknown"))
		if view.pending_zone != &"":
			title_text += " · %s: %s" % [UiText.t(&"zoning.pending_zone"), UiText.humanize(view.pending_zone)]
	# Boş belediye arazisi normal durumdur (H3): kırmızı yalnız gerçekten plansız sıradan parselde.
	var warn := PlanStateText.needs_plan(plan) and not model.municipal_mode
	var title := UiFactory.label(title_text, UiTheme.V_LABEL_DANGER if warn else &"", true)
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
	_put(_section(&"zoning.use"))
	if model.is_locked():
		# Gönderilmiş öneri: seçenekler değil, gönderilen kullanım gösterilir (devre dışı düğme yığını yok).
		_put(UiFactory.label(UiText.t(model.land_use), &"", true))
		_verdict = null
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", int(_ctx.spacing()))
	flow.add_theme_constant_override(&"v_separation", int(_ctx.spacing()))
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_put(flow)
	for use in UiConfig.land_uses():
		var b := UiFactory.button(_ctx, UiText.t(use), not _sticky, true)
		_tag(b, "use_%s" % use)
		b.set_pressed_no_signal(use == model.land_use)
		b.pressed.connect(choose_use.bind(use))
		_use_buttons[use] = b
		flow.add_child(b)
	_verdict = UiFactory.label(model.verdict_text(), &"", true)
	_verdict.visible = model.last_validation != null
	if model.last_validation != null and model.last_validation.is_rejected():
		_verdict.theme_type_variation = UiTheme.V_LABEL_DANGER
	_put(_verdict)


## Yoğunluk seçenekleri (yalnız hazırlıkta): "Varsayılan" + yapılandırma seçenekleri; seçim komuta `density` gider.
func _add_density() -> void:
	if model.is_locked() or model.land_use == &"":
		return
	var options := ZoningFlowModel.density_options()
	if options.is_empty():
		return
	_put(_section(&"zoning.density.title"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", int(_ctx.spacing()))
	flow.add_theme_constant_override(&"v_separation", int(_ctx.spacing()))
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_put(flow)
	var choices: Array[int] = [-1]
	choices.append_array(options)
	for pm in choices:
		var text := UiText.t(&"zoning.density.default") if pm < 0 else UiText.t(&"zoning.density.value",
				{"pct": UiText.number(pm / 10)})
		var b := UiFactory.button(_ctx, text, not _sticky, true)
		_tag(b, "density_%d" % pm)
		b.set_pressed_no_signal(pm == model.density_pm)
		b.pressed.connect(choose_density.bind(pm))
		flow.add_child(b)
	_put(_muted(UiText.t(&"zoning.density.note")))


func choose_density(pm: int) -> void:
	model.choose_density(pm)
	_render()


## Önizleme: YALNIZ `plan_preview` sayıları. Sim'den gelmeyen hiçbir sayı yazılmaz.
func _add_preview() -> void:
	var pv := model.preview()
	if pv == null or model.is_locked():
		return
	_put(_section(&"zoning.preview.title"))
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
	_put(parts[0])


func _add_send_and_status() -> void:
	if model.phase() == ZoningFlowModel.Phase.READY:
		_put(UiFactory.label(UiText.t(&"zoning.summary", {"parcels": _area_text(),
			"use": UiText.t(model.land_use)}), &"", true))
	_add_honesty_notes()
	if not model.is_locked():
		_put(_muted(model.path_text()))
		_add_route_note()
		_send = ActionButton.create(_ctx, model.submit_label(), true)
		_tag(_send.button, "send")
		_send.set_enabled(model.can_send(), model.send_block_reason())
		_send.pressed.connect(send)
		_act(_send)
	if model.is_locked():
		_add_route_note()
	_status = UiFactory.label(model.status_text(), &"", true)
	_status.visible = not _status.text.is_empty()
	if model.phase() == ZoningFlowModel.Phase.REFUSED or model.phase() == ZoningFlowModel.Phase.VOTE_FAILED:
		_status.theme_type_variation = UiTheme.V_LABEL_DANGER
	_act(_status)
	_add_followups()


## SIM-12: planın meclise gitme/gitmeme nedeni (eşik sim'den); eşik yoksa satır yok. Gönderimden sonra da kalır.
func _add_route_note() -> void:
	var text := model.route_text()
	if text != "":
		var note := _muted(text)
		_tag(note, "route_note")
		_put(note)


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
		_put(_notes)
	if not model.is_locked():
		var warn := model.structure_warning()
		if warn != "":
			_warning = UiFactory.label(warn, UiTheme.V_LABEL_DANGER, true)
			_put(_warning)


func warning_text() -> String:
	return _warning.text if _warning != null and is_instance_valid(_warning) else ""


func note_text() -> String:
	return _notes.text if _notes != null and is_instance_valid(_notes) else ""


func _add_followups() -> void:
	if model.can_open_reason():
		var why := UiFactory.button(_ctx, UiText.t(&"alert.open_reason"), true)
		_tag(why, "open_reason")
		why.pressed.connect(_on_reason_pressed)
		_act(why)
	if model.vote_ref != &"":
		var vote := UiFactory.button(_ctx, UiText.t(&"zoning.see_vote"), false)
		_tag(vote, "open_vote")
		vote.pressed.connect(func() -> void: navigate_requested.emit(&"council"))
		_act(vote)
	if model.is_finished():
		var again := UiFactory.button(_ctx, UiText.t(&"zoning.new_proposal"), true)
		_tag(again, "new_proposal")
		again.pressed.connect(func() -> void:
			model.reset()
			_render())
		_act(again)


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
	var by_id := {}
	for v in _facade.parcel_views(model.parcel_ids):
		by_id[v.id] = v
	return ZoningParcelText.area_phrase(model.parcel_ids.size(), _views_in_order(by_id))
