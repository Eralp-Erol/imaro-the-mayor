class_name InspectorPanel
extends FlowPanel
## Parsel/bölge denetçisi paneli (T-041): seçilen parselin karar -> gerekçe -> inşaat -> sonuç zincirini TEK
## panelde okutur. Tüm değerler `InspectorModel` (yani `SimFacade`) okumasıdır; sabit sayı, ölü düğme, ham anahtar yok.
## - Sunum kamera ölçek bandına göre sadeleşir (`InspectorModel.Detail`): sokak = parsel ayrıntısı + etkenler,
##   mahalle = özet zincir, ilçe = bölge özeti + seçili parselin tek satırı. VERİ AYNI.
## - "Nedenini gör" ReasonPanel'i açtırır (`reason_requested`); "İmar önerisi ver" imar akışını açtırır
##   (`zoning_requested`; belediye fiili, CAN-03: özel bina yerleştirme yok).
## - Renk tek başına anlam taşımaz (yön simgesi + metin); hover'a bağımlı bilgi yok (dokunmatik aynı).

signal zoning_requested(parcel_id: int)

const META_ROW := &"inspector_row"
const ROW_FACT := "fact"
const ROW_STEP := "step"
const ROW_METRIC := "metric"
const ROW_REACTION := "reaction"
const ROW_FACTOR := "factor"
const ROW_SELECTED := "selected"

var model: InspectorModel = null

var _host: InspectorHost = null


static func create(ctx: UiContext, facade: SimFacade, host: InspectorHost) -> InspectorPanel:
	var p := InspectorPanel.new()
	p._host = host
	p._setup_flow(ctx, facade)
	p.refresh()
	return p


func refresh() -> void:
	if _body == null or _host == null:
		return
	model = _host.build_model()
	refresh_if_changed(model.signature())


func _render() -> void:
	if _body == null:
		return
	if model == null:
		model = _host.build_model()
	var focus_role := _begin_render()
	state_view.show_normal()
	match model.state:
		InspectorModel.State.EMPTY:
			_body.add_child(_muted(UiText.t(&"inspector.empty_hint")))
		InspectorModel.State.MISSING:
			_body.add_child(UiFactory.label(UiText.t(&"inspector.missing", {"id": model.parcel_id}),
					UiTheme.V_LABEL_TITLE, true))
			_body.add_child(_muted(UiText.t(&"inspector.missing_hint")))
		_:
			_render_ready()
	_restore_focus(focus_role)


func _render_ready() -> void:
	var v := model.view
	_body.add_child(UiFactory.label(UiText.humanize(String(v.ref())), UiTheme.V_LABEL_HEADING, true))
	var band_key := StringName("inspector.band.%s" % _band_name())
	_body.add_child(_muted(UiText.t(band_key, {"code": String(v.region_code)})))
	match model.detail:
		InspectorModel.Detail.REGION:
			_add_region(true)
			_add_selected_line()
		InspectorModel.Detail.SUMMARY:
			_add_chain(false)
			_add_region(false)
		_:
			_add_facts()
			_add_chain(true)
			_add_region(false)
	_add_actions()


func _band_name() -> String:
	match model.detail:
		InspectorModel.Detail.REGION:
			return "district"
		InspectorModel.Detail.SUMMARY:
			return "neighborhood"
	return "street"


# --- Parsel gerçekleri (yalnız sokak bandı) ---

func _add_facts() -> void:
	var v := model.view
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(_named(_pair(UiText.t(&"inspector.zoning"), UiText.humanize(String(v.zone))), ROW_FACT))
	inner.add_child(_named(_pair(UiText.t(&"inspector.pending_zone"),
			UiText.humanize(String(v.pending_zone)) if v.pending_zone != &"" else UiText.t(&"inspector.none_pending")),
			ROW_FACT))
	inner.add_child(_named(_pair(UiText.t(&"inspector.area"),
			UiText.t(&"format.area_m2", {"value": UiText.number(v.area_m2)})), ROW_FACT))
	inner.add_child(_named(_pair(UiText.t(&"inspector.owner"), UiText.actor_name(v.owner)), ROW_FACT))
	# Sim arsa değerini 0 verdiyse değer henüz belirlenmemiştir; "0 ¤" yazmak parselin bedava olduğunu söylerdi.
	var land := UiText.money(v.land_value) if v.land_value > 0 else UiText.t(&"inspector.land_value.unset")
	inner.add_child(_named(_pair(UiText.t(&"inspector.land_value"), land), ROW_FACT))
	_body.add_child(parts[0])


# --- Zincir: imar -> karar (+gerekçe) -> yapı -> tepki ---

func _add_chain(with_factors: bool) -> void:
	var row := model.row()
	var v := model.view
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(_step(&"m2.step.zoning"))
	if v.pending_zone != &"":
		inner.add_child(UiFactory.label(UiText.t(&"m2.zoning.pending",
				{"zone": UiText.humanize(String(v.pending_zone))}), &"", true))
	else:
		inner.add_child(UiFactory.label(UiText.t(&"m2.zoning.effective",
				{"zone": UiText.humanize(String(v.zone))}), &"", true))
	inner.add_child(_step(&"m2.step.investor"))
	_add_decision(inner, row, with_factors)
	inner.add_child(_step(&"m2.step.stage"))
	_add_stage(inner, v)
	inner.add_child(_step(&"inspector.step.reaction"))
	_add_reactions(inner)
	_body.add_child(parts[0])


func _step(key: StringName) -> Label:
	var l := UiFactory.label(UiText.t(key), UiTheme.V_LABEL_MUTED, true)
	l.set_meta(META_ROW, ROW_STEP)
	return l


func _decision_line(row: M2ResultModel.ParcelRow) -> String:
	if row.recorded == M2ResultModel.Decision.NONE:
		return UiText.t(&"m2.investor.none")
	var date := UiText.tick_date(row.tick)
	return UiText.t(&"m2.investor.approved" if row.recorded == M2ResultModel.Decision.APPROVED
			else &"m2.investor.declined", {"date": date})


func _add_decision(inner: VBoxContainer, row: M2ResultModel.ParcelRow, with_factors: bool) -> void:
	if row.recorded == M2ResultModel.Decision.NONE:
		inner.add_child(UiFactory.label(_decision_line(row), UiTheme.V_LABEL_MUTED, true))
		return
	if row.recorded == M2ResultModel.Decision.APPROVED:
		inner.add_child(_direction_row(ReasonGlyph.Kind.UP, "ok", UiTheme.V_LABEL_OK, _decision_line(row)))
	else:
		inner.add_child(_direction_row(ReasonGlyph.Kind.DOWN, "danger", UiTheme.V_LABEL_DANGER, _decision_line(row)))
		var cause := UiText.t(StringName("m2.decline.%s" % row.cause))
		inner.add_child(UiFactory.label(UiText.t(&"m2.decline.cause", {"cause": cause}), &"", true))
	if model.reason_pruned or model.record == null:
		inner.add_child(_muted(UiText.t(&"m2.investor.pruned")))
		return
	if with_factors and not model.factors.is_empty():
		inner.add_child(_muted(UiText.t(&"inspector.factors")))
		for fr in model.factors:
			inner.add_child(_factor_row(fr))
	var rid := model.record.id
	var why := UiFactory.button(_ctx, UiText.t(&"m2.why"), true)
	_tag(why, "why_decision")
	why.pressed.connect(func() -> void: _request_reason(func(p: ReasonPanel) -> void: p.show_record(rid)))
	inner.add_child(why)


func _factor_row(fr: ReasonModel.Row) -> Control:
	var name_text := UiText.t(fr.name_key) if UiText.has(fr.name_key) else UiText.humanize(String(fr.name_key))
	if fr.is_estimate:
		name_text += " (%s)" % UiText.t(&"common.estimate")
	var row: Control
	if fr.direction == ReasonModel.DIR_FOR:
		row = _direction_row(ReasonGlyph.Kind.UP, "ok", UiTheme.V_LABEL_OK,
				"%s: %s" % [name_text, UiText.t(&"reason.direction.for")])
	else:
		row = _direction_row(ReasonGlyph.Kind.DOWN, "danger", UiTheme.V_LABEL_DANGER,
				"%s: %s" % [name_text, UiText.t(&"reason.direction.against")])
	row.set_meta(META_ROW, ROW_FACTOR)
	return row


func _add_stage(inner: VBoxContainer, v: ParcelView) -> void:
	var stage := UiText.t(M2ResultModel.stage_key(v.development))
	if v.development == ParcelView.DEVELOPMENT_VACANT or v.use == ParcelView.USE_NONE:
		inner.add_child(UiFactory.label("%s · %s" % [stage, UiText.t(&"m2.stage.none")], &"", true))
		return
	inner.add_child(UiFactory.label(UiText.t(&"m2.stage.line", {"stage": stage,
			"use": UiText.t(StringName("zoning.use.%s" % v.use)), "units": v.units}), &"", true))
	inner.add_child(_muted(UiText.t(&"m2.progress")))
	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var meter := MeterBar.create(_ctx, v.progress_pm)
	bar.add_child(meter)
	var pct := UiFactory.label(_pct_text(v.progress_pm))
	pct.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(pct)
	inner.add_child(bar)


func _pct_text(permille: int) -> String:
	return UiText.t(&"format.percent", {"value": UiText.number(permille / 10)})


func _add_reactions(inner: VBoxContainer) -> void:
	if model.linked_reactions.is_empty() and model.past_reactions.is_empty():
		inner.add_child(_muted(UiText.t(&"inspector.reactions.none")))
		return
	for g in model.linked_reactions:
		inner.add_child(_reaction_row(g))
	for e in model.past_reactions:
		var who := UiText.actor_name(e.actor) if e.actor != null and e.actor.is_valid() else ""
		var text := UiText.t(&"inspector.reactions.past", {"date": UiText.tick_date(e.tick),
				"text": UiText.event_text(e)})
		if not who.is_empty():
			text = "%s · %s" % [who, text]
		var label := UiFactory.label(text, UiTheme.V_LABEL_MUTED, true)
		label.set_meta(META_ROW, ROW_REACTION)
		inner.add_child(label)


func _reaction_row(g: GroupReactionView) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.set_meta(META_ROW, ROW_REACTION)
	var text := "%s · %s" % [UiText.actor_name(g.group), UiText.t(StringName("m2.reaction.%s" % g.reaction))]
	match g.reaction:
		GroupReactionView.REACTION_SUPPORT:
			box.add_child(_direction_row(ReasonGlyph.Kind.UP, "ok", UiTheme.V_LABEL_OK, text))
		GroupReactionView.REACTION_OPPOSE, GroupReactionView.REACTION_PROTEST:
			box.add_child(_direction_row(ReasonGlyph.Kind.DOWN, "danger", UiTheme.V_LABEL_DANGER, text))
		_:
			box.add_child(_direction_row(ReasonGlyph.Kind.FLAT, "text_muted", UiTheme.V_LABEL_MUTED, text))
	box.add_child(_muted(UiText.t(&"m2.political.intensity", {"value": _pct_text(g.intensity)})))
	if not g.reason_ids.is_empty():
		var ids := g.reason_ids
		var why := UiFactory.button(_ctx, UiText.t(&"m2.why.group"), false)
		_tag(why, "why_group_%d" % g.group.id)
		why.pressed.connect(func() -> void: _request_reason(func(p: ReasonPanel) -> void: p.show_reason_ids(ids)))
		box.add_child(why)
	return box


# --- Bölge sonucu ---

func _add_region(full: bool) -> void:
	var m2 := model.m2
	if not m2.outcome_available:
		_body.add_child(_section(&"m2.region.section"))
		_body.add_child(_muted(UiText.t(&"m2.outcome.unavailable")))
		_add_municipal_honest(_body)
		return
	var title := UiText.t(&"m2.region.title", {"code": String(m2.region_code)}) if m2.region_code != &"" \
			else UiText.t(&"m2.city.title")
	_body.add_child(UiFactory.label(title, UiTheme.V_LABEL_TITLE, true))
	_body.add_child(_muted(UiText.t(&"inspector.since_start")))
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	for r in m2.metrics:
		inner.add_child(_metric_pair(r))
	if full:
		inner.add_child(_named(_pair(UiText.t(&"m2.row.pipeline"), UiText.t(&"m2.row.pipeline_value",
				{"res": UiText.number(m2.pipeline_residential), "com": UiText.number(m2.pipeline_commercial)})),
				ROW_METRIC))
	_body.add_child(parts[0])
	if full:
		_body.add_child(UiFactory.label(UiText.t(&"m2.city.title"), UiTheme.V_LABEL_TITLE, true))
		var city := _card()
		var city_inner: VBoxContainer = city[1]
		for r in m2.counters:
			city_inner.add_child(_metric_pair(r))
		_add_municipal(city_inner)
		_body.add_child(city[0])


func _metric_pair(r: M2ResultModel.MetricRow) -> Control:
	var caption := UiText.t(StringName("m2.metric.%s" % r.key))
	return _named(_pair(caption, _metric_value(r)), ROW_METRIC)


func _metric_value(r: M2ResultModel.MetricRow) -> String:
	if r.key == &"housed_households":
		return UiText.t(&"m2.row.housed_value", {"housed": UiText.number(r.value), "total": UiText.number(r.total)})
	if r.key == &"rent_income":
		return M2ResultPanel.delta_money(r.delta) if r.delta_valid else UiText.money(r.value)
	return M2ResultPanel.delta_text(r.delta) if r.delta_valid else UiText.number(r.value)


func _add_municipal(inner: VBoxContainer) -> void:
	var m2 := model.m2
	if m2.municipal_available:
		inner.add_child(_named(_pair(UiText.t(&"m2.row.municipal"), UiText.money(m2.municipal_value)), ROW_METRIC))
		return
	_add_municipal_honest(inner)


func _add_municipal_honest(inner: Control) -> void:
	var m2 := model.m2
	var key := m2.municipal_reason_key if m2.municipal_reason_key != &"" \
			else EconomyOutcomeView.REASON_MUNICIPAL_REVENUE_NOT_BUILT
	inner.add_child(_named(_pair(UiText.t(&"m2.row.municipal"), UiText.t(&"state.not_built_short")), ROW_METRIC))
	if UiText.has(key):
		inner.add_child(_muted(UiText.t(key)))


## İlçe bandında seçili parselin tek satırı (ayrıntı için yakınlaşma ipucu).
func _add_selected_line() -> void:
	var v := model.view
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(_section(&"inspector.selected"))
	var stage := UiText.t(M2ResultModel.stage_key(v.development))
	var line := UiFactory.label("%s · %s · %s" % [UiText.humanize(String(v.ref())), stage,
			_decision_line(model.row())], &"", true)
	line.set_meta(META_ROW, ROW_SELECTED)
	inner.add_child(line)
	if model.is_declined():
		var cause := UiText.t(StringName("m2.decline.%s" % model.row().cause))
		inner.add_child(UiFactory.label(UiText.t(&"m2.decline.cause", {"cause": cause}), &"", true))
	inner.add_child(_muted(UiText.t(&"inspector.zoom_hint")))
	_body.add_child(parts[0])


func _add_actions() -> void:
	var zone := UiFactory.button(_ctx, UiText.t(&"inspector.action.zoning"), true)
	_tag(zone, "zoning")
	var pid := model.parcel_id
	zone.pressed.connect(func() -> void: zoning_requested.emit(pid))
	_body.add_child(zone)


func _named(c: Control, role: String) -> Control:
	c.set_meta(META_ROW, role)
	return c
