class_name AgendaPanel
extends FlowPanel
## Gündem paneli (ux-flows-v0 §I, T-022): modal olmayan, geri sayımlı öğeler. Öğeler meclis oylamalarından (yalnız
## izlenir) ve sim'in açık gündem öğelerinden (`AgendaItemView`) gelir. Sim öğesinde `options` varsa her seçenek bir
## kart olur:
## `label_key` metni, düz Türkçe etki önizlemesi (yön + zaman; büyüklük YOK), kilitliyse gri + nedeni; "Bu yanıtı ver"
## `SimFacade.submit_command(SimCommand.agenda_respond(...))` gönderir, ret nedeni sim'in `reason_key`/`args.why`ından
## gösterilir. `options` boşsa düğme YOKTUR. Bedel yazılmaz (sim düşmüyor); "ertele" yoktur (sim'de etkisiz).
## Başarıda öğe sonraki tick'te listeden kalkar; panel bunu olduğu gibi yansıtır (iyimser silme yok).
## Otomatik duraklatma: yalnız AYAR (`UiPrefs.auto_pause_agenda`); varsayılanı AÇIK SORU (Q-011/AS-11).

## Yanıt komutu gönderildikten sonra (kabul ya da ret) yayımlanır; `result` sim'in sonucudur.
signal option_chosen(item_id: StringName, option_id: StringName, result: CommandResult)
signal auto_pause_changed(on: bool)

## `func(snapshot: SimSnapshot) -> Array[AgendaModel.Item]`; varsayılan türetme.
var item_provider: Callable = Callable()
var items: Array[AgendaModel.Item] = []

var _auto_pause_button: Button = null
## Öğe ref -> son ret sonucu (gönderimde ya da tick sınırında); öğe gündemden kalkınca silinir.
var _refusals: Dictionary = {}
## Öğe ref -> {command_id, tick}: kuyrukta bekleyen yanıt (çift gönderimi engeller).
var _pending: Dictionary = {}


static func create(ctx: UiContext, facade: SimFacade) -> AgendaPanel:
	var p := AgendaPanel.new()
	p._setup_flow(ctx, facade)
	p._render()
	return p


## Öğe kaynağını değiştirir (dev önizlemesi / test) ve yeniden çizer.
func set_item_provider(provider: Callable) -> void:
	item_provider = provider
	_render()


func auto_pause_button() -> Button:
	return _auto_pause_button


func signature_now() -> String:
	var snap := _facade.snapshot()
	return "%s|%d|%s" % [var_to_str(snap.council.to_dict()), snap.tick(), UiPrefs.auto_pause_agenda()]


func refresh() -> void:
	refresh_if_changed(signature_now())


## Tick sınırında reddedilen yanıt (`command.rejected`): nedeni öğe kartında gösterilir.
func handle_event(event: SimEvent) -> void:
	if event.kind != SimEvent.KIND_COMMAND_REJECTED:
		return
	for ref: Variant in _pending.keys():
		if int(_pending[ref]["command_id"]) == event.command_id:
			_refusals[ref] = {"reason_key": event.message_key, "args": event.args, "late": true}
			_pending.erase(ref)
			_render()
			return


func _render() -> void:
	if _body == null:
		return
	_signature = signature_now()
	var focus_role := _begin_render()
	_auto_pause_button = null
	var snap := _facade.snapshot()
	items = item_provider.call(snap) if item_provider.is_valid() else AgendaModel.derive_all(_facade, snap)
	_prune_tracking(snap.tick())
	if not AgendaModel.source_built(snap) and items.is_empty() and not item_provider.is_valid():
		state_view.show_not_built(&"agenda.not_built")
		return
	state_view.show_normal()
	if items.is_empty():
		_body.add_child(UiFactory.label(UiText.t(&"agenda.empty"), &"", true))
	for it in items:
		_body.add_child(_item_card(it))
	if not item_provider.is_valid() and not items.any(func(i: AgendaModel.Item) -> bool:
			return i.kind != AgendaModel.KIND_COUNCIL_VOTE):  # not, "yalnız meclis oylaması" iken doğrudur
		_body.add_child(_muted(UiText.t(&"agenda.derived_note")))
	_add_settings()
	_restore_focus(focus_role)


func _item_card(it: AgendaModel.Item) -> Control:
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	var title := UiText.t(it.title_key) if UiText.has(it.title_key) else UiText.t(&"agenda.item_new")
	inner.add_child(UiFactory.label(title, UiTheme.V_LABEL_TITLE, true))
	var kind_key := StringName("agenda.kind.%s" % it.kind)
	if UiText.has(kind_key):
		inner.add_child(_muted(UiText.t(kind_key)))
	if it.subject_ref != &"":
		inner.add_child(_pair(UiText.t(&"council.subject"), UiText.humanize(String(it.subject_ref))))
	inner.add_child(UiFactory.label(_time_text(it), &"", true))
	_add_displacement_cause(inner, it)
	if it.kind == AgendaModel.KIND_COUNCIL_VOTE:
		var open := UiFactory.button(_ctx, UiText.t(&"zoning.see_vote"), true)
		_tag(open, "open_item_%s" % it.id)
		open.pressed.connect(func() -> void: navigate_requested.emit(&"council"))
		inner.add_child(open)
	_add_response_state(inner, it)
	for o in it.options:
		inner.add_child(_option_card(it, o))
	return parts[0]


## Yerinden edilme tepkisi (PE-01, T-042b): hane sayısı öğenin gerekçe zincirindeki sim kaydından okunur; kayıtta sayı
## yoksa satır ve düğme çıkmaz. "Nedenini gör" zinciri (öğe kaydı -> yerinden edilme nedeni) gerekçe panelini açar.
func _add_displacement_cause(inner: VBoxContainer, it: AgendaModel.Item) -> void:
	if it.reason_ids.is_empty():
		return
	var cause := AgendaModel.displaced_cause(_facade, it.reason_ids)
	if not bool(cause["found"]):
		return
	inner.add_child(UiFactory.label(UiText.t(&"agenda.displacement.households", {"count": UiText.number(
		int(cause["households"]))}), &"", true))
	var ids := it.reason_ids
	var why := UiFactory.button(_ctx, UiText.t(&"agenda.displacement.why"), false)
	_tag(why, "why_%s" % it.id)
	why.pressed.connect(func() -> void: _request_reason(func(p: ReasonPanel) -> void: p.show_reason_ids(ids)))
	inner.add_child(why)


## Yanıtlanabilir öğe: "yanıt için kalan"; oylama gibi yalnız izlenen öğe: "sonuç ... içinde".
func _time_text(it: AgendaModel.Item) -> String:
	if it.days_left <= 0:
		return UiText.t(&"agenda.due_today" if it.answerable() else &"council.closes_today")
	if it.answerable():
		return UiText.t(&"agenda.time_left", {"days": it.days_left})
	return UiText.t(&"council.closes_in", {"days": it.days_left})


## Gündemden kalkan öğelerin izini sil; tick ilerlediyse bekleyen kaydı bırak.
func _prune_tracking(tick: int) -> void:
	var live: Dictionary = {}
	for it in items:
		live[it.id] = true
	for store: Dictionary in [_refusals, _pending]:
		for ref: Variant in store.keys():
			if not live.has(ref):
				store.erase(ref)
	for ref: Variant in _pending.keys():
		if tick > int(_pending[ref]["tick"]) + 1:
			_pending.erase(ref)   # olay yenilemeden sonra gelebilir: 1 tick pay; sonra bekleyen kaydı bırak


func _option_card(it: AgendaModel.Item, o: AgendaModel.Option) -> Control:
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(UiFactory.label(UiText.t(o.label_key), UiTheme.V_LABEL_TITLE, true))
	var note_key := StringName("agenda.note.%s" % o.verb)
	if UiText.has(note_key):
		inner.add_child(_muted(UiText.t(note_key)))
	if not o.effects.is_empty():
		var head := HBoxContainer.new()
		head.add_child(UiFactory.label(UiText.t(&"agenda.preview"), UiTheme.V_LABEL_MUTED, true))
		head.add_child(_estimate_chip())
		inner.add_child(head)
		for effect: Variant in o.effects:
			inner.add_child(UiFactory.label("• " + AgendaModel.effect_text(effect as Dictionary), &"", true))
	if not o.available:
		inner.add_child(_muted(_locked_text(o)))
	var choose := UiFactory.button(_ctx, UiText.t(&"agenda.choose"), true)
	choose.disabled = not o.available or _pending.has(it.id)
	_tag(choose, "choose_%s_%s" % [it.id, o.id])
	choose.pressed.connect(func() -> void: respond(it, o))
	inner.add_child(choose)
	return parts[0]


func _locked_text(o: AgendaModel.Option) -> String:
	var key := StringName("agenda.locked.%s" % o.locked_by)
	if UiText.has(key):
		return UiText.t(key)
	return UiText.t(&"agenda.locked.generic", {"authority": UiText.humanize(o.locked_by)})


## Yanıtı sim'e gönderir (tek yol `submit_command`); sonuç kartta gösterilir. Gönderilemezse null.
func respond(it: AgendaModel.Item, o: AgendaModel.Option) -> CommandResult:
	if it.agenda_item_id == SimContract.NO_ID or not o.available or _pending.has(it.id):
		return null
	var result := _facade.submit_command(SimCommand.agenda_respond(it.agenda_item_id, o.id))
	if result.is_rejected():
		_refusals[it.id] = {"reason_key": result.reason_key, "args": result.args, "late": false}
		_pending.erase(it.id)
	else:
		_refusals.erase(it.id)
		_pending[it.id] = {"command_id": result.command_id, "tick": _facade.snapshot().tick()}
	option_chosen.emit(it.id, o.id, result)
	_render()
	return result


## Durum satırı: bekleyen yanıt ya da son ret (sim'in gerekçesiyle).
func _add_response_state(inner: VBoxContainer, it: AgendaModel.Item) -> void:
	if _pending.has(it.id):
		inner.add_child(UiFactory.label(UiText.t(&"agenda.respond.sent"), &"", true))
	elif _refusals.has(it.id):
		var r: Dictionary = _refusals[it.id]
		var key := &"agenda.respond.refused_at_tick" if bool(r["late"]) else &"agenda.respond.rejected"
		inner.add_child(UiFactory.label(UiText.t(key, {"reason": _reason_text(r["reason_key"], r["args"])}), &"",
			true))


## Ret nedeni: önce sim'in `args.why`ı (kısa Türkçe karşılık), sonra `reason_key` metni; ikisi de yoksa genel metin.
func _reason_text(reason_key: StringName, args: Dictionary) -> String:
	var why := StringName("agenda.respond.why.%s" % String(args.get("why", "")))
	if args.has("why") and UiText.has(why):
		return UiText.t(why)
	if UiText.has(reason_key):
		return UiText.reject_reason(reason_key, args)
	return UiText.t(&"agenda.respond.rejected_generic")


func _add_settings() -> void:
	var on := UiPrefs.auto_pause_agenda()
	_body.add_child(_section(&"settings.title"))
	_auto_pause_button = UiFactory.button(_ctx, "%s: %s" % [UiText.t(&"settings.auto_pause_agenda"),
		UiText.t(&"agenda.auto_pause_state_on" if on else &"agenda.auto_pause_state_off")], true, true)
	_auto_pause_button.set_pressed_no_signal(on)
	_auto_pause_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auto_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag(_auto_pause_button, "auto_pause")
	_auto_pause_button.toggled.connect(_on_auto_pause_toggled)
	_body.add_child(_auto_pause_button)
	_body.add_child(_muted(UiText.t(&"agenda.auto_pause_note")))


func _on_auto_pause_toggled(on: bool) -> void:
	UiPrefs.set_auto_pause_agenda(on)
	auto_pause_changed.emit(on)
	_render()
