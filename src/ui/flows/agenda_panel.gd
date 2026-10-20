class_name AgendaPanel
extends FlowPanel
## Gündem paneli (ux-flows-v0 §I, T-022): modal olmayan, geri sayımlı öğeler. `AgendaItemView` sözleşmede v1.0'da
## YOKTUR (v1.1 isteği); öğeler `AgendaModel.derive` ile açık meclis oylamalarından türetilir ve YANIT SEÇENEĞİ
## taşımaz: panel bunu açıkça söyler, seçenek/ertele düğmesi uydurmaz. Seçenekli öğe gelirse (`item_provider`
## değişince ya da v1.1 uyarlayıcısıyla) kartlar bedel + TAHMİN işaretli önizleme + "Bu seçeneği uygula"/"Ertele" ile
## çizilir; bu yol v1.0 verisiyle erişilemez ve yalnız birim testlidir.
## Kaynak kurulmamışsa ("Olay sistemi henüz kurulmadı") yalnız durum bileşeni görünür.
## Otomatik duraklatma: yalnız AYAR (`UiPrefs.auto_pause_agenda`); varsayılanı AÇIK SORU (Q-011/AS-11).

## v1.1 yanıt komutu için (`RespondAgenda`): şimdilik bağlayan yok; yalnız seçenekli öğede erişilebilir.
signal option_chosen(item_id: StringName, option_id: StringName)
signal deferred(item_id: StringName)
signal auto_pause_changed(on: bool)

## `func(snapshot: SimSnapshot) -> Array[AgendaModel.Item]`; varsayılan türetme.
var item_provider: Callable = Callable()
var items: Array[AgendaModel.Item] = []

var _auto_pause_button: Button = null


static func create(ctx: UiContext, facade: SimFacade) -> AgendaPanel:
	var p := AgendaPanel.new()
	p._setup_flow(ctx, facade)
	p._render()
	return p


## Öğe kaynağını değiştirir (v1.1 `AgendaItemView` uyarlayıcısı ya da dev önizlemesi) ve yeniden çizer.
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


func _render() -> void:
	if _body == null:
		return
	_signature = signature_now()
	var focus_role := _begin_render()
	_auto_pause_button = null
	var snap := _facade.snapshot()
	items = item_provider.call(snap) if item_provider.is_valid() else AgendaModel.derive(snap)
	if not AgendaModel.source_built(snap) and not item_provider.is_valid():
		state_view.show_not_built(&"agenda.not_built")
		return
	state_view.show_normal()
	if items.is_empty():
		_body.add_child(UiFactory.label(UiText.t(&"agenda.empty"), &"", true))
	for it in items:
		_body.add_child(_item_card(it))
	if not item_provider.is_valid():
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
	if it.kind == AgendaModel.KIND_COUNCIL_VOTE:
		var open := UiFactory.button(_ctx, UiText.t(&"zoning.see_vote"), true)
		_tag(open, "open_item_%s" % it.id)
		open.pressed.connect(func() -> void: navigate_requested.emit(&"council"))
		inner.add_child(open)
	for o in it.options:
		inner.add_child(_option_card(it, o))
	if it.can_defer:
		inner.add_child(_muted(UiText.t(&"agenda.defer_note")))
		var defer := UiFactory.button(_ctx, UiText.t(&"agenda.defer"), false)
		_tag(defer, "defer_%s" % it.id)
		defer.pressed.connect(func() -> void: deferred.emit(it.id))
		inner.add_child(defer)
	return parts[0]


## Yanıtlanabilir öğe: "yanıt için kalan"; oylama gibi yalnız izlenen öğe: "sonuç ... içinde".
func _time_text(it: AgendaModel.Item) -> String:
	if it.days_left <= 0:
		return UiText.t(&"agenda.due_today" if it.answerable() else &"council.closes_today")
	if it.answerable():
		return UiText.t(&"agenda.time_left", {"days": it.days_left})
	return UiText.t(&"council.closes_in", {"days": it.days_left})


func _option_card(it: AgendaModel.Item, o: AgendaModel.Option) -> Control:
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(UiFactory.label(UiText.t(o.label_key), UiTheme.V_LABEL_TITLE, true))
	if o.has_cost:
		inner.add_child(UiFactory.label(UiText.t(&"agenda.option_cost", {"money": o.cost}), &"", true))
	if o.preview_key != &"":
		var head := HBoxContainer.new()
		head.add_child(UiFactory.label(UiText.t(&"agenda.preview"), UiTheme.V_LABEL_MUTED, true))
		if o.preview_is_estimate:
			head.add_child(_estimate_chip())
		inner.add_child(head)
		inner.add_child(UiFactory.label(UiText.t(o.preview_key), &"", true))
	var choose := UiFactory.button(_ctx, UiText.t(&"agenda.choose"), true)
	_tag(choose, "choose_%s_%s" % [it.id, o.id])
	choose.pressed.connect(func() -> void: option_chosen.emit(it.id, o.id))
	inner.add_child(choose)
	return parts[0]


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
