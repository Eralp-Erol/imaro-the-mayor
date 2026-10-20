class_name ReasonPanel
extends VBoxContainer
## Nedensellik paneli "Neden böyle oldu?" (T-021, SIM-12). `ReasonRecord` -> okunur Türkçe anlatım: sonuç, kim/ne
## zaman/nerede, etken çubukları (değer×ağırlık, yön simgesi+metin, tahmin işareti), eşik çizgisi ve marj, neden
## zinciri (`parent_ids`) gezinmesi, aynı konudaki kayıtların zaman çizelgesi, aktör/parsel bağlantıları.
##
## - Veri yalnız `SimFacade` (`reasons_for`, `reason`) ile okunur; metin yalnız `UiText` anahtarlarıyla. UI neden
##   UYDURMAZ: sim kayıt vermediyse "henüz kayıtlı gerekçe yok"; önerilen eylem yok (sözleşmede yok).
## - Kayıt değişmezi UI'da yeniden hesaplanır (`ReasonModel`); tutmayan kayıt görünürde "Kayıt tutarsız: veri
##   hatası" kutusu + satır işaretiyle verilir, sessizce kabul edilmez.
## - MOCK: `facade.is_mock()` ya da kaydın kaynağı `sim` değilse MOCK rozeti.
## - Girişler: `show_subject(ref)` (parsel denetçisi/aktör/oylama), `show_reason_ids(ids)` / `show_event(event)`
##   (olay şeridi), `show_command_result(result)` (reddedilen komut), `show_record(id)`.
## - Gezinti: yığın (liste -> ayrıntı -> önceki neden ...); "Geri" yığını çözer. Durum `nav_state()` ile saklanır,
##   profil değişince panel yeniden kurulurken `restore_nav` ile geri yüklenir.
## - Dokunmatik: tüm eylemler etiketli düğme (≥ hedef boyutu); hover'a bağlı bilgi yok (ayrıntı hep görünür).
## - Klavye: Tab/Enter ile gezinme, Geri tuşu (Backspace) bir adım geri.

signal map_focus_requested(subject_ref: StringName)
signal nav_changed

const MODE_NONE := &"none"
const MODE_LIST := &"list"
const MODE_DETAIL := &"detail"
const MODE_REJECTION := &"rejection"
const MAX_STACK := 32
const META_ROLE := &"role"
const NAME_FACTOR := "FactorRow"
const NAME_PARENT := "ChainParent"
const NAME_ROW := "ListRow"
const NAME_TIMELINE := "TimelineRow"
const NAME_SUBJECT := "SubjectLink"
const NAME_BANNER := "InconsistentBanner"

## Haritada göster düğmesi yalnız bunu dinleyen bir sahip varsa görünür (ölü düğme yok).
var map_enabled: bool = false
## Test/odak erişimi (salt okunur kullanılır).
var badge: MockBadge = null
var back_button: Button = null
var state_view: StateView = null

var _ctx: UiContext = null
var _facade: SimFacade = null
var _body: VBoxContainer = null
var _stack: Array[Dictionary] = []
var _shown_non_sim: bool = false
var _last_request: Callable = Callable()


static func create(ctx: UiContext, facade: SimFacade) -> ReasonPanel:
	var p := ReasonPanel.new()
	p._ctx = ctx
	p._facade = facade
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.badge = MockBadge.create()
	p.badge.visible = facade != null and facade.is_mock()
	p.add_child(p.badge)
	p.back_button = UiFactory.button(ctx, UiText.t(&"common.back"), false)
	p.back_button.visible = false
	p.back_button.tooltip_text = UiText.t(&"common.back")
	p.back_button.pressed.connect(p.back)
	p.back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.add_child(p.back_button)
	p._body = VBoxContainer.new()
	p._body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.state_view = StateView.create(ctx)
	p.state_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.state_view.set_content(p._body)
	p.state_view.retry_requested.connect(p._retry)
	p.add_child(p.state_view)
	return p


# --- Girişler ---

## Bir varlığın gerçek kayıtları (`parcel.12`, `actor.group.2`, `vote.1`): 1 kayıt -> doğrudan ayrıntı, çok kayıt
## -> zaman sıralı liste.
func show_subject(subject_ref: StringName) -> void:
	_last_request = show_subject.bind(subject_ref)
	_stack.clear()
	_open_list({"mode": MODE_LIST, "ref": String(subject_ref), "ids": []}, true)


## Olay şeridi / komut sonucu gibi kimlik listesi veren girişler.
func show_reason_ids(ids: PackedInt64Array) -> void:
	_last_request = show_reason_ids.bind(ids)
	_stack.clear()
	var plain: Array = []
	for id in ids:
		plain.append(int(id))
	_open_list({"mode": MODE_LIST, "ref": "", "ids": plain}, true)


func show_record(reason_id: int) -> void:
	_last_request = show_record.bind(reason_id)
	_stack = [{"mode": MODE_DETAIL, "id": reason_id}]
	_changed()


## Olay şeridinden: gerekçe kimlikleri varsa kayıtlar, reddedilen komut ise ret görünümü.
func show_event(event: SimEvent) -> void:
	if not event.reason_ids.is_empty() and event.kind != SimEvent.KIND_COMMAND_REJECTED:
		show_reason_ids(event.reason_ids)
	elif event.kind == SimEvent.KIND_COMMAND_REJECTED:
		_last_request = show_event.bind(event)
		_stack = [{"mode": MODE_REJECTION, "kind": "", "reason_key": String(event.message_key),
			"args": event.args.duplicate(), "command_id": event.command_id, "tick": event.tick,
			"reason_ids": _ints(event.reason_ids)}]
		_changed()
	else:
		_last_request = show_event.bind(event)
		_stack.clear()
		_changed()


## Reddedilen `CommandResult` (anında ret): ret gerekçesi + bağlı kayıtlar.
func show_command_result(result: CommandResult) -> void:
	_last_request = show_command_result.bind(result)
	_stack = [{"mode": MODE_REJECTION, "kind": String(result.kind), "reason_key": String(result.reason_key),
		"args": result.args.duplicate(), "command_id": result.command_id, "tick": result.tick,
		"reason_ids": _ints(result.reason_ids)}]
	_changed()


func show_loading() -> void:
	state_view.loading_delay_s = 0.0
	state_view.show_loading()


func show_error(detail: String = "") -> void:
	state_view.show_error(detail if not detail.is_empty() else UiText.t(&"state.error.reason_unavailable"), true)


# --- Gezinti ---

func can_go_back() -> bool:
	return _stack.size() > 1


func back() -> void:
	if _stack.size() > 1:
		_stack.pop_back()
		_changed()
		_focus_back_or_first()


func current_mode() -> StringName:
	return StringName(_stack.back()["mode"]) if not _stack.is_empty() else MODE_NONE


func stack_depth() -> int:
	return _stack.size()


func nav_state() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _stack:
		out.append(entry.duplicate(true))
	return out


func restore_nav(state: Array[Dictionary]) -> void:
	_stack.clear()
	for entry in state:
		_stack.append(entry.duplicate(true))
	_changed()


## Facade verisi değişti (yeni tick): açık görünümü yeniden okur, gezinti korunur.
func refresh() -> void:
	_render()


## Görünür tüm etiket ve düğme metinleri (test/erişilebilirlik).
func texts() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_texts(self, out)
	return out


func named_buttons(role_prefix: String) -> Array[Button]:
	var out: Array[Button] = []
	for b in _buttons_in(_body):
		if String(b.get_meta(META_ROLE, "")).begins_with(role_prefix):
			out.append(b)
	return out


## Rol önekiyle eşleşen kontroller (düğüm adları sim anahtarındaki '.' yüzünden güvenilmez; rol meta'dadır).
func find_roles(role_prefix: String) -> Array[Control]:
	var out: Array[Control] = []
	_roles_in(_body, role_prefix, out)
	return out


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_BACKSPACE and can_go_back() \
			and is_visible_in_tree():
		back()
		get_viewport().set_input_as_handled()


# --- Çizim ---

func _changed() -> void:
	_render()
	nav_changed.emit()


func _retry() -> void:
	if _last_request.is_valid():
		_last_request.call()
	else:
		_render()


func _open_list(entry: Dictionary, auto_detail: bool) -> void:
	if _facade == null:
		_stack.append(entry)
		_changed()
		return
	var records := _records_of(entry)
	if auto_detail and records.size() == 1:
		_stack.append({"mode": MODE_DETAIL, "id": records[0].id})
	else:
		_stack.append(entry)
	while _stack.size() > MAX_STACK:
		_stack.pop_front()
	_changed()


func _render() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_shown_non_sim = false
	back_button.visible = can_go_back()
	badge.visible = _facade != null and _facade.is_mock()
	if _facade == null:
		state_view.show_error(UiText.t(&"state.error.sim_unavailable"), true)
		return
	if _stack.is_empty():
		state_view.show_empty(&"state.empty.no_reasons")
		return
	var entry: Dictionary = _stack.back()
	match StringName(entry["mode"]):
		MODE_LIST:
			_render_list(entry)
		MODE_DETAIL:
			_render_detail(int(entry["id"]))
		MODE_REJECTION:
			_render_rejection(entry)
		_:
			state_view.show_empty(&"state.empty.no_reasons")
	if _shown_non_sim:
		badge.visible = true


func _render_list(entry: Dictionary) -> void:
	var records := _records_of(entry)
	if records.is_empty():
		state_view.show_empty(&"state.empty.no_reasons")
		return
	state_view.show_normal()
	_body.add_child(UiFactory.label(UiText.t(&"reason.list_title"), UiTheme.V_LABEL_TITLE, true))
	if String(entry["ref"]) != "":
		_body.add_child(UiFactory.label(UiText.humanize(String(entry["ref"])), UiTheme.V_LABEL_HEADING, true))
	_body.add_child(UiFactory.label(UiText.t(&"reason.count", {"n": records.size()}), UiTheme.V_LABEL_MUTED, true))
	for r in records:
		_body.add_child(_list_row(r, NAME_ROW))


func _render_detail(reason_id: int) -> void:
	var record := _facade.reason(reason_id)
	if record == null:
		state_view.show_empty(&"reason.expired")
		return
	state_view.show_normal()
	_note_provenance(record)
	var model := ReasonModel.from_record(record, int(UiConfig.value("reason.top_n", 3)))
	# 1) Sonuç (üst satır).
	_body.add_child(UiFactory.label(UiText.t(&"reason.outcome"), UiTheme.V_LABEL_MUTED))
	_body.add_child(UiFactory.label(_decision_text(record), UiTheme.V_LABEL_HEADING, true))
	_body.add_child(UiFactory.label(UiText.t(&"reason.outcome_positive" if record.outcome ==
		ReasonRecord.OUTCOME_POSITIVE else &"reason.outcome_negative"), UiTheme.V_LABEL_MUTED, true))
	# 2) Veri hatası kutusu (tutarsız kayıt görünürde).
	if not model.is_consistent():
		_body.add_child(_inconsistent_box(model))
	# 3) Başlık satırı: toplam, eşik ve marj (dar alt sayfada kaydırmadan görünür).
	_body.add_child(_margin_label(model))
	_body.add_child(UiFactory.label(UiText.t(&"reason.sum_line", {
		"sum": UiText.fixed(record.score), "threshold": UiText.fixed(record.threshold)}), &"", true))
	# 4) Kim / ne zaman / nerede.
	_body.add_child(_meta_block(record))
	# 5) Özet cümlesi (sim vermişse onu; yoksa etken listesinden türetilir) + eşik ölçeği.
	var summary := _summary_text(model)
	if not summary.is_empty():
		_body.add_child(UiFactory.label(summary, &"", true))
	_body.add_child(_section(&"reason.threshold_section"))
	_body.add_child(ReasonMeter.create(_ctx, model, UiText.t(&"reason.threshold")))
	# 6) Etkenler.
	_body.add_child(_section(&"reason.factors"))
	_body.add_child(UiFactory.label(UiText.t(&"reason.direction_hint"), UiTheme.V_LABEL_MUTED, true))
	if model.rows.is_empty():
		_body.add_child(UiFactory.label(UiText.t(&"reason.no_factors"), UiTheme.V_LABEL_MUTED, true))
	for i in model.rows.size():
		_body.add_child(_factor_row(model.rows[i], i, record.id))
	# 7) Neden zinciri.
	_body.add_child(_section(&"reason.chain"))
	_add_chain(record, model)
	# 8) Zaman içinde.
	_add_timeline(record)
	# 9) Haritada göster.
	_add_map_buttons(record)


func _render_rejection(entry: Dictionary) -> void:
	state_view.show_normal()
	_body.add_child(UiFactory.label(UiText.t(&"reason.rejected_title"), UiTheme.V_LABEL_HEADING, true))
	var kind := String(entry.get("kind", ""))
	if kind != "":
		_body.add_child(_pair(UiText.t(&"reason.rejected_command"),
			UiText.t(StringName("command.kind.%s" % kind)) if UiText.has(StringName("command.kind.%s" % kind)) \
			else kind))
	var command_id := int(entry.get("command_id", 0))
	if command_id != SimContract.NO_ID:
		_body.add_child(_pair(UiText.t(&"command.label"), UiText.humanize(SimContract.ref(
			SimContract.REF_COMMAND, command_id))))
	_body.add_child(_pair(UiText.t(&"reason.rejected_when"), UiText.tick_date(int(entry.get("tick", 0)))))
	var args: Dictionary = entry.get("args", {})
	_body.add_child(_pair(UiText.t(&"reason.rejected_reason"),
		UiText.reject_reason(StringName(String(entry["reason_key"])), args)))
	var ids: Array = entry.get("reason_ids", [])
	if ids.is_empty():
		_body.add_child(UiFactory.label(UiText.t(&"reason.rejected_no_record"), UiTheme.V_LABEL_MUTED, true))
		return
	_body.add_child(_section(&"reason.rejected_linked"))
	for id: Variant in ids:
		var rec := _facade.reason(int(id))
		if rec == null:
			_body.add_child(UiFactory.label(UiText.t(&"reason.expired"), UiTheme.V_LABEL_MUTED, true))
		else:
			_note_provenance(rec)
			_body.add_child(_list_row(rec, NAME_ROW))


# --- Parçalar ---

func _list_row(r: ReasonRecord, node_name: String) -> Button:
	_note_provenance(r)
	var model := ReasonModel.from_record(r)
	var text := _decision_text(r)
	var meta := "%s, %s" % [UiText.actor_name(r.actor), UiText.tick_date(r.tick)]
	if not model.is_consistent():
		meta += "\n" + UiText.t(&"reason.inconsistent_row")
	var b := _link_button(text + "\n" + meta, node_name)
	b.pressed.connect(_push_detail.bind(r.id))
	return b


func _push_detail(reason_id: int) -> void:
	_stack.append({"mode": MODE_DETAIL, "id": reason_id})
	while _stack.size() > MAX_STACK:
		_stack.pop_front()
	_changed()
	_focus_back_or_first()


func _push_subject(subject_ref: StringName) -> void:
	_stack.append({"mode": MODE_LIST, "ref": String(subject_ref), "ids": []})
	while _stack.size() > MAX_STACK:
		_stack.pop_front()
	_changed()
	_focus_back_or_first()


func _meta_block(record: ReasonRecord) -> Control:
	# Kim / ne zaman / nerede: tek akış kabında (dar iPad dikey alt sayfasında satır sayısı az kalır).
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override(&"h_separation", int(_ctx.spacing() * 3.0))
	flow.add_theme_constant_override(&"v_separation", int(_ctx.spacing()))
	var actor_ref: StringName = record.actor.ref() if record.actor != null and record.actor.is_valid() else &""
	flow.add_child(_meta_item(UiText.t(&"reason.who"), UiText.actor_name(record.actor), actor_ref, record.id,
		NAME_SUBJECT + "_actor"))
	flow.add_child(_meta_item(UiText.t(&"reason.when"), UiText.tick_date(record.tick), &"", record.id, ""))
	for s in record.subjects:
		flow.add_child(_meta_item(UiText.t(&"reason.related"), UiText.humanize(s), StringName(s), record.id,
			NAME_SUBJECT + "_" + s))
	return flow


## "Başlık değer" öğesi (başlık sönük). `ref` verilmişse ve o varlığın BAŞKA kaydı varsa değer bağlantı düğmesi,
## yoksa düz etiket (boş sayfaya giden bağlantı yok).
func _meta_item(caption: String, value: String, ref: StringName, current_id: int, role: String) -> Control:
	var item := HBoxContainer.new()
	item.add_theme_constant_override(&"separation", int(_ctx.spacing() / 2.0))
	var cap := UiFactory.label(caption, UiTheme.V_LABEL_MUTED)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item.add_child(cap)
	if ref != &"" and _has_other_records(ref, current_id):
		var link := _link_button(value, role)
		link.autowrap_mode = TextServer.AUTOWRAP_OFF
		link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		link.tooltip_text = UiText.t(&"reason.open_subject", {"subject": value})
		link.pressed.connect(_push_subject.bind(ref))
		item.add_child(link)
	else:
		var label := UiFactory.label(value, &"")
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(label)
	return item


func _factor_row(row: ReasonModel.Row, index: int, current_id: int) -> Control:
	var box := VBoxContainer.new()
	_tag(box, "%s_%d" % [NAME_FACTOR, index])
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dir_text: String
	var dir_glyph: ReasonGlyph.Kind
	var dir_color: Color
	var dir_variation: StringName
	if row.is_info_only:
		dir_text = UiText.t(&"reason.info_only")
		dir_glyph = ReasonGlyph.Kind.FLAT
		dir_color = _ctx.tokens.color("text_muted")
		dir_variation = UiTheme.V_LABEL_MUTED
	elif row.direction == ReasonModel.DIR_FOR:
		dir_text = UiText.t(&"reason.direction.for")
		dir_glyph = ReasonGlyph.Kind.UP
		dir_color = _ctx.tokens.color("ok")
		dir_variation = UiTheme.V_LABEL_OK
	elif row.direction == ReasonModel.DIR_AGAINST:
		dir_text = UiText.t(&"reason.direction.against")
		dir_glyph = ReasonGlyph.Kind.DOWN
		dir_color = _ctx.tokens.color("danger")
		dir_variation = UiTheme.V_LABEL_DANGER
	else:
		dir_text = UiText.t(&"reason.direction.neutral")
		dir_glyph = ReasonGlyph.Kind.FLAT
		dir_color = _ctx.tokens.color("text_muted")
		dir_variation = UiTheme.V_LABEL_MUTED
	var head := HBoxContainer.new()
	head.add_child(ReasonGlyph.create(_ctx, dir_glyph, dir_color, dir_text))
	var name_text := UiText.t(row.name_key)
	if row.is_estimate:
		name_text += " (%s)" % UiText.t(&"common.estimate")
	var name_label := UiFactory.label(name_text, &"", true)
	head.add_child(name_label)
	var dir_label := UiFactory.label(dir_text, dir_variation, true)
	dir_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	dir_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	dir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(dir_label)
	box.add_child(head)
	if not row.is_info_only:
		box.add_child(ReasonFactorBar.create(_ctx, row))
	var calc := UiText.t(&"reason.calc", {"value": UiText.fixed(row.value), "weight": UiText.fixed(row.weight),
		"contribution": UiText.fixed(row.contribution, true)})
	box.add_child(UiFactory.label(calc, UiTheme.V_LABEL_MUTED, true))
	box.tooltip_text = calc
	if row.has_trend:
		var trend_key := &"a11y.trend_flat"
		if row.trend > 0:
			trend_key = &"a11y.trend_up"
		elif row.trend < 0:
			trend_key = &"a11y.trend_down"
		box.add_child(UiFactory.label(UiText.t(trend_key), UiTheme.V_LABEL_MUTED, true))
	if row.source_ref != &"":
		var src_text := UiText.t(&"reason.source", {"subject": UiText.humanize(String(row.source_ref))})
		if _has_other_records(row.source_ref, current_id):
			var src := _link_button(src_text, NAME_SUBJECT + "_src_" + String(row.source_ref))
			src.pressed.connect(_push_subject.bind(row.source_ref))
			box.add_child(src)
		else:
			box.add_child(UiFactory.label(src_text, UiTheme.V_LABEL_MUTED, true))
	return box


func _margin_label(model: ReasonModel) -> Label:
	var state_key := &"reason.margin_over"
	if model.margin == 0:
		state_key = &"reason.margin_exact"
	elif model.margin < 0:
		state_key = &"reason.margin_under"
	# Tutarsız kayıtta marj da veri hatası renginde (üstteki kutu metinle açıklar).
	var l := UiFactory.label(UiText.t(&"reason.margin_line", {
		"margin": UiText.fixed(model.margin, true), "state": UiText.t(state_key)}),
		UiTheme.V_LABEL_DANGER if not model.is_consistent() else UiTheme.V_LABEL_TITLE, true)
	_tag(l, "MarginLabel")
	return l


func _inconsistent_box(model: ReasonModel) -> Control:
	var card := PanelContainer.new()
	_tag(card, NAME_BANNER)
	card.theme_type_variation = UiTheme.V_PANEL_ALERT
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_child(ReasonGlyph.create(_ctx, ReasonGlyph.Kind.WARN, _ctx.tokens.color("danger"),
		UiText.t(&"reason.inconsistent_title")))
	head.add_child(UiFactory.label(UiText.t(&"reason.inconsistent_title"), UiTheme.V_LABEL_DANGER, true))
	col.add_child(head)
	for issue in model.issues:
		col.add_child(UiFactory.label(_issue_text(issue), &"", true))
	col.add_child(UiFactory.label(UiText.t(&"reason.inconsistent_note"), UiTheme.V_LABEL_MUTED, true))
	return card


func _issue_text(issue: Dictionary) -> String:
	var args: Dictionary = (issue["args"] as Dictionary).duplicate()
	var code: StringName = issue["code"]
	for k: Variant in args.keys():
		var v: Variant = args[k]
		if (code == ReasonModel.ISSUE_SCORE or code == ReasonModel.ISSUE_OUTCOME) and v is int \
				and k != "outcome":
			args[k] = UiText.fixed(int(v))
	if code == ReasonModel.ISSUE_OUTCOME:
		args["outcome"] = UiText.t(&"reason.outcome_positive" if args["outcome"] == ReasonRecord.OUTCOME_POSITIVE
			else &"reason.outcome_negative")
	if code == ReasonModel.ISSUE_DIRECTION:
		args["factor"] = UiText.t(StringName(args["factor"]))
	return UiText.t(StringName("reason.issue.%s" % code), args)


func _summary_text(model: ReasonModel) -> String:
	if model.summary_key != &"":
		return UiText.t(model.summary_key, model.summary_args)
	if model.top_names.is_empty():
		return ""
	var names := PackedStringArray()
	for n in model.top_names:
		names.append(UiText.t(n))
	return UiText.t(&"reason.summary", {"factors": ", ".join(names)})


func _add_chain(record: ReasonRecord, model: ReasonModel) -> void:
	if record.parent_ids.is_empty() and model.cause_refs.is_empty():
		_body.add_child(UiFactory.label(UiText.t(&"reason.no_parents"), UiTheme.V_LABEL_MUTED, true))
		return
	if not record.parent_ids.is_empty():
		_body.add_child(UiFactory.label(UiText.t(&"reason.parents"), UiTheme.V_LABEL_MUTED, true))
	for pid in record.parent_ids:
		var parent := _facade.reason(pid) if pid != record.id else null
		if parent == null:
			_body.add_child(UiFactory.label(UiText.t(&"reason.expired"), UiTheme.V_LABEL_MUTED, true))
			continue
		_body.add_child(_list_row(parent, "%s_%d" % [NAME_PARENT, pid]))
	if not model.cause_refs.is_empty():
		_body.add_child(UiFactory.label(UiText.t(&"reason.causes"), UiTheme.V_LABEL_MUTED, true))
		for ref in model.cause_refs:
			var link := _link_button(UiText.humanize(ref), NAME_SUBJECT + "_cause_" + ref)
			link.pressed.connect(_push_subject.bind(StringName(ref)))
			_body.add_child(link)


func _add_timeline(record: ReasonRecord) -> void:
	var ref := StringName(record.subjects[0]) if not record.subjects.is_empty() else \
		(record.actor.ref() if record.actor != null and record.actor.is_valid() else &"")
	if ref == &"":
		return
	var same := _facade.reasons_for(ref)
	if same.size() < 2:
		return
	_body.add_child(_section(&"reason.over_time"))
	_body.add_child(UiFactory.label(UiText.t(&"reason.timeline_hint") + ": " + UiText.humanize(String(ref)),
		UiTheme.V_LABEL_MUTED, true))
	for r in same:
		if r.id == record.id:
			var here := UiFactory.label("%s (%s)" % [_decision_text(r), UiText.t(&"reason.this_record")], &"", true)
			_tag(here, NAME_TIMELINE + "_current")
			_body.add_child(here)
		else:
			_body.add_child(_list_row(r, "%s_%d" % [NAME_TIMELINE, r.id]))


func _add_map_buttons(record: ReasonRecord) -> void:
	if not map_enabled:
		return
	for s in record.subjects:
		if SimContract.parse_ref(StringName(s))["kind"] == String(SimContract.REF_PARCEL):
			var b := UiFactory.button(_ctx, UiText.t(&"reason.show_on_map") + ": " + UiText.humanize(s), false)
			_tag(b, "MapButton_" + s)
			b.pressed.connect(map_focus_requested.emit.bind(StringName(s)))
			_body.add_child(b)


func _section(key: StringName) -> Label:
	var l := UiFactory.label(UiText.t(key), UiTheme.V_LABEL_TITLE, true)
	return l


func _pair(caption: String, value: String) -> Control:
	var row := _caption_row(caption)
	row.add_child(UiFactory.label(value, &"", true))
	return row


func _caption_row(caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cap := UiFactory.label(caption, UiTheme.V_LABEL_MUTED, true)
	cap.size_flags_stretch_ratio = 0.7
	row.add_child(cap)
	return row


func _has_other_records(ref: StringName, current_id: int) -> bool:
	for r in _facade.reasons_for(ref):
		if r.id != current_id:
			return true
	return false


func _link_button(text: String, node_name: String) -> Button:
	var b := UiFactory.button(_ctx, text, false)
	_tag(b, node_name)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = 1.3
	return b


func _decision_text(r: ReasonRecord) -> String:
	var key := StringName("%s.%s" % [r.decision_key, r.outcome])
	return UiText.t(key) if UiText.has(key) else UiText.humanize(String(r.decision_key))


func _records_of(entry: Dictionary) -> Array[ReasonRecord]:
	var out: Array[ReasonRecord] = []
	if _facade == null:
		return out
	if String(entry.get("ref", "")) != "":
		out = _facade.reasons_for(StringName(String(entry["ref"])))
	else:
		for id: Variant in entry.get("ids", []):
			var r := _facade.reason(int(id))
			if r != null:
				out.append(r)
	out.sort_custom(func(a: ReasonRecord, b: ReasonRecord) -> bool:
		return a.tick < b.tick or (a.tick == b.tick and a.id < b.id))
	return out


func _note_provenance(record: ReasonRecord) -> void:
	if record.provenance != SimContract.PROVENANCE_SIM:
		_shown_non_sim = true


func _focus_back_or_first() -> void:
	if not is_inside_tree():
		return
	if back_button.visible:
		back_button.grab_focus()
	else:
		var first := _first_button()
		if first != null:
			first.grab_focus()


func _first_button() -> Button:
	var found := _buttons_in(_body)
	return found[0] if not found.is_empty() else null


func _roles_in(node: Node, role_prefix: String, out: Array[Control]) -> void:
	for child in node.get_children():
		var c := child as Control
		if c != null and String(c.get_meta(META_ROLE, "")).begins_with(role_prefix):
			out.append(c)
		_roles_in(child, role_prefix, out)


func _tag(node: Control, role: String) -> void:
	node.set_meta(META_ROLE, role)
	node.name = role.validate_node_name()


func _buttons_in(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in node.get_children():
		var b := child as Button
		if b != null:
			out.append(b)
		out.append_array(_buttons_in(child))
	return out


func _collect_texts(node: Node, out: PackedStringArray) -> void:
	for child in node.get_children():
		var c := child as Control
		if c != null and not c.visible:
			continue
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
		_collect_texts(child, out)


func _ints(ids: PackedInt64Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append(int(id))
	return out
