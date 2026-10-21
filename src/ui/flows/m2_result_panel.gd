class_name M2ResultPanel
extends FlowPanel
## "Döngü sonucu" paneli (T-040, M2): imar önerisi -> yatırımcı kararı (kodlu neden) -> aşama/ilerleme -> bölge
## ekonomik fark -> siyasi tepki. Tüm sayılar `M2ResultModel` (yani `SimFacade`) okumasıdır; sabit sayı, ölü düğme yok.
## - Karar `ParcelView.decision*`dan okunur (günlük dönse de doğru); "Nedenini gör" yalnız `decision_reason_id>0` iken
##   görünür, 0 ise dürüst "gerekçe kaydı budandı" notu. Öneri öncesi karar ayrı etiketlenir (B-001).
## - "Nedenini gör" `reason_requested` ile ReasonPanel'i açtırır (SIM-12).
## - Belediye geliri sim'de kurulu değilse dürüst "Henüz kurulmadı" satırı (neden anahtarı sim'den).
## - Mock/ekonomisiz facade: ekonomik bölüm "ölçülmüyor" der; parsel ve siyasi bölümler eldeki veriyle çizilir.
## - Renk tek başına anlam taşımaz: yön simgesi + metin. Hover'a bağımlı bilgi yok (dokunmatik aynı).

## Satır rolleri (`META_ROW` meta anahtarı; test/erişilebilirlik).
const META_ROW := &"m2_row"
const ROW_STEP := "step"
const ROW_METRIC := "metric"
const ROW_REACTION := "reaction"

var model: M2ResultModel = null

var _results: M2Results = null


static func create(ctx: UiContext, facade: SimFacade, results: M2Results) -> M2ResultPanel:
	var p := M2ResultPanel.new()
	p._results = results
	p._setup_flow(ctx, facade)
	p.refresh()
	return p


func refresh() -> void:
	if _body == null or _results == null:
		return
	model = _results.build_model()
	refresh_if_changed(model.signature())


func _render() -> void:
	if _body == null:
		return
	if model == null:
		model = _results.build_model()
	var focus_role := _begin_render()
	state_view.show_normal()
	_add_parcel_section()
	_add_outcome_section()
	_add_political_section()
	_restore_focus(focus_role)


# --- Parsel ---

func _add_parcel_section() -> void:
	if model.primary == null:
		_body.add_child(_section(&"m2.parcel.section"))
		_body.add_child(_muted(UiText.t(&"m2.parcel.none")))
		return
	var row := model.primary
	var v := row.view
	_body.add_child(UiFactory.label(UiText.humanize(String(v.ref())), UiTheme.V_LABEL_HEADING, true))
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(_step_label(&"m2.step.zoning"))
	if v.pending_zone != &"":
		inner.add_child(UiFactory.label(UiText.t(&"m2.zoning.pending", {"zone": UiText.humanize(String(v.pending_zone))}),
				&"", true))
	else:
		inner.add_child(UiFactory.label(UiText.t(&"m2.zoning.effective", {"zone": UiText.humanize(String(v.zone))}),
				&"", true))
	inner.add_child(_step_label(&"m2.step.investor"))
	_add_decision(inner, row)
	inner.add_child(_step_label(&"m2.step.stage"))
	_add_stage(inner, v)
	_body.add_child(parts[0])
	if model.parcels.size() > 1:
		_add_others()


func _step_label(key: StringName) -> Label:
	var l := UiFactory.label(UiText.t(key), UiTheme.V_LABEL_MUTED, true)
	l.set_meta(META_ROW, ROW_STEP)
	return l


func _add_decision(inner: VBoxContainer, row: M2ResultModel.ParcelRow) -> void:
	# Öneri öncesi karar AYRI etiketlenir; yatırımcı öneriyi henüz değerlendirmedi.
	if row.before_proposal:
		inner.add_child(UiFactory.label(UiText.t(&"m2.investor.prior"), UiTheme.V_LABEL_MUTED, true))
		_add_outcome_lines(inner, row, true)
		inner.add_child(UiFactory.label(UiText.t(&"m2.investor.waiting"), &"", true))
		return
	if row.decision == M2ResultModel.Decision.NONE:
		inner.add_child(UiFactory.label(UiText.t(&"m2.investor.none"), UiTheme.V_LABEL_MUTED, true))
		return
	_add_outcome_lines(inner, row, false)


## Kayıtlı kararın satırları + (gerekçe kaydı varsa) "Nedenini gör" ya da dürüst "budandı" notu.
func _add_outcome_lines(inner: VBoxContainer, row: M2ResultModel.ParcelRow, prior: bool) -> void:
	var date := UiText.tick_date(row.tick)
	if row.recorded == M2ResultModel.Decision.APPROVED:
		inner.add_child(_direction_row(ReasonGlyph.Kind.UP, "ok", UiTheme.V_LABEL_OK,
				UiText.t(&"m2.investor.approved", {"date": date})))
	else:
		inner.add_child(_direction_row(ReasonGlyph.Kind.DOWN, "danger", UiTheme.V_LABEL_DANGER,
				UiText.t(&"m2.investor.declined", {"date": date})))
		var cause := UiText.t(StringName("m2.decline.%s" % row.cause))
		inner.add_child(UiFactory.label(UiText.t(&"m2.decline.cause", {"cause": cause}), &"", true))
	if row.reason_id <= 0:
		inner.add_child(_muted(UiText.t(&"m2.investor.pruned")))
		return
	var why := UiFactory.button(_ctx, UiText.t(&"m2.why"), true)
	_tag(why, "why_prior" if prior else "why_decision")
	var rid := row.reason_id
	why.pressed.connect(func() -> void: _request_reason(func(p: ReasonPanel) -> void: p.show_record(rid)))
	inner.add_child(why)


func _add_stage(inner: VBoxContainer, v: ParcelView) -> void:
	var stage := UiText.t(M2ResultModel.stage_key(v.development))
	if v.development == ParcelView.DEVELOPMENT_VACANT or v.use == ParcelView.USE_NONE:
		inner.add_child(UiFactory.label("%s · %s" % [stage, UiText.t(&"m2.stage.none")], &"", true))
		return
	var use_key := StringName("zoning.use.%s" % v.use)
	inner.add_child(UiFactory.label(UiText.t(&"m2.stage.line", {"stage": stage, "use": UiText.t(use_key),
			"units": v.units}), &"", true))
	inner.add_child(_muted(UiText.t(&"m2.progress")))
	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(MeterBar.create(_ctx, v.progress_pm))
	var pct := UiFactory.label(UiText.t(&"format.percent", {"value": UiText.number(v.progress_pm / 10)}))
	pct.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(pct)
	inner.add_child(bar)


func _add_others() -> void:
	var c := model.counts_decided()
	_body.add_child(_muted(UiText.t(&"m2.others", {"n": model.parcels.size(), "approved": c["approved"],
			"declined": c["declined"], "waiting": c["waiting"]})))
	if model.parcels_capped:
		_body.add_child(_muted(UiText.t(&"m2.others.capped", {"n": M2ResultModel.MAX_DETAIL_PARCELS})))


# --- Ölçülen sonuç ---

func _add_outcome_section() -> void:
	if not model.outcome_available:
		_body.add_child(_section(&"m2.region.section"))
		var reason := model.outcome.unavailable_reason_key if model.outcome != null else &"m2.outcome.unavailable"
		_body.add_child(_muted(UiText.t(&"m2.outcome.unavailable")))
		if UiText.has(reason):
			_body.add_child(_muted(UiText.t(reason)))
		var lone := _card()
		_add_municipal(lone[1])
		_body.add_child(lone[0])
		return
	var title := UiText.t(&"m2.region.title", {"code": String(model.region_code)}) \
			if model.region_code != &"" else UiText.t(&"m2.city.title")
	_body.add_child(UiFactory.label(title, UiTheme.V_LABEL_HEADING, true))
	var base_text := UiText.t(&"m2.baseline.at", {"date": UiText.tick_date(model.baseline_tick)}) \
			if model.baseline_valid else UiText.t(&"m2.baseline.start")
	_body.add_child(_muted(base_text))
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	for r in model.metrics:
		inner.add_child(_metric_pair(r))
	inner.add_child(_named(_pair(UiText.t(&"m2.row.pipeline"), UiText.t(&"m2.row.pipeline_value",
			{"res": UiText.number(model.pipeline_residential), "com": UiText.number(model.pipeline_commercial)})),
			ROW_METRIC))
	_body.add_child(parts[0])
	if model.region_code != &"":
		_body.add_child(UiFactory.label(UiText.t(&"m2.city.title"), UiTheme.V_LABEL_HEADING, true))
	var city := _card()
	var city_inner: VBoxContainer = city[1]
	for r in model.counters:
		city_inner.add_child(_metric_pair(r))
	city_inner.add_child(_muted(UiText.t(&"m2.row.rent_note")))
	_add_municipal(city_inner)
	_body.add_child(city[0])


func _add_municipal(inner: VBoxContainer) -> void:
	if model.municipal_available:
		inner.add_child(_named(_pair(UiText.t(&"m2.row.municipal"), UiText.money(model.municipal_value)), ROW_METRIC))
	else:
		var key := model.municipal_reason_key if model.municipal_reason_key != &"" \
				else EconomyOutcomeView.REASON_MUNICIPAL_REVENUE_NOT_BUILT
		inner.add_child(_named(_pair(UiText.t(&"m2.row.municipal"), UiText.t(&"state.not_built_short")), ROW_METRIC))
		inner.add_child(_muted(UiText.t(key)))


func _metric_pair(r: M2ResultModel.MetricRow) -> Control:
	var caption := UiText.t(StringName("m2.metric.%s" % r.key))
	var value := ""
	if r.key == &"housed_households":
		value = UiText.t(&"m2.row.housed_value", {"housed": UiText.number(r.value), "total": UiText.number(r.total)})
		if r.delta_valid:
			value += " (%s)" % delta_text(r.delta)
	elif r.key == &"rent_income":
		value = delta_money(r.delta) if r.delta_valid else UiText.money(r.value)
	else:
		value = delta_text(r.delta) if r.delta_valid else UiText.number(r.value)
	return _named(_pair(caption, value), ROW_METRIC)


## İşaretli tamsayı: +3, 0, −2.
static func delta_text(value: int) -> String:
	if value > 0:
		return UiText.t(&"format.delta_plus", {"value": UiText.number(value)})
	return UiText.number(value)


static func delta_money(value: int) -> String:
	if value > 0:
		return UiText.t(&"format.delta_plus", {"value": UiText.money(value)})
	return UiText.money(value)


func _named(c: Control, role: String) -> Control:
	c.set_meta(META_ROW, role)
	return c


# --- Siyasi ---

func _add_political_section() -> void:
	_body.add_child(_section(&"m2.political.section"))
	if model.reactions.is_empty():
		_body.add_child(_muted(UiText.t(&"m2.political.none")))
	for g in model.reactions:
		_body.add_child(_reaction_card(g))
	if model.reactions_hidden > 0:
		_body.add_child(_muted(UiText.t(&"m2.political.more", {"n": model.reactions_hidden})))
	if model.council_built:
		_body.add_child(UiFactory.label(UiText.t(&"m2.council.line", {"open": model.council_open,
				"done": model.council_done}), &"", true))


func _reaction_card(g: GroupReactionView) -> Control:
	var parts := _card()
	parts[0].set_meta(META_ROW, ROW_REACTION)
	var inner: VBoxContainer = parts[1]
	inner.add_child(UiFactory.label(UiText.actor_name(g.group), UiTheme.V_LABEL_TITLE, true))
	var text := UiText.t(StringName("m2.reaction.%s" % g.reaction))
	match g.reaction:
		GroupReactionView.REACTION_SUPPORT:
			inner.add_child(_direction_row(ReasonGlyph.Kind.UP, "ok", UiTheme.V_LABEL_OK, text))
		GroupReactionView.REACTION_OPPOSE, GroupReactionView.REACTION_PROTEST:
			inner.add_child(_direction_row(ReasonGlyph.Kind.DOWN, "danger", UiTheme.V_LABEL_DANGER, text))
		_:
			inner.add_child(_direction_row(ReasonGlyph.Kind.FLAT, "text_muted", UiTheme.V_LABEL_MUTED, text))
	var bar := HBoxContainer.new()
	bar.add_child(MeterBar.create(_ctx, g.intensity))
	var inten := UiFactory.label(UiText.t(&"m2.political.intensity",
			{"value": UiText.t(&"format.percent", {"value": UiText.number(g.intensity / 10)})}))
	inten.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(inten)
	inner.add_child(bar)
	inner.add_child(UiFactory.label(UiText.t(&"m2.political.stance", {"value": UiText.fixed(g.stance, true)}),
			UiTheme.V_LABEL_MUTED, true))
	if not g.cause_refs.is_empty():
		var refs := PackedStringArray()
		for ref in g.cause_refs.slice(0, 3):
			refs.append(UiText.humanize(ref))
		inner.add_child(UiFactory.label(UiText.t(&"m2.political.cause", {"refs": ", ".join(refs)}),
				UiTheme.V_LABEL_MUTED, true))
	if not g.reason_ids.is_empty():
		var ids := g.reason_ids
		var why := UiFactory.button(_ctx, UiText.t(&"m2.why.group"), false)
		_tag(why, "why_group_%d" % g.group.id)
		why.pressed.connect(func() -> void: _request_reason(func(p: ReasonPanel) -> void: p.show_reason_ids(ids)))
		inner.add_child(why)
	return parts[0]
