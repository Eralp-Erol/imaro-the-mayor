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
const ROW_HINT := "hint"

var model: M2ResultModel = null

var _results: M2Results = null
var _structure: String = ""
## Değeri her yenilemede güncellenen düğümler (yeniden kurma yok): her biri model'den metni/çubuğu yeniden okur.
var _dyn: Array[Callable] = []


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
	var structure := model.structure_signature()
	var sig := structure + "#" + model.values_signature()
	if sig == _signature:
		return
	if structure == _structure and not _dyn.is_empty():
		# Yalnız değerler değişti: düğümler yeniden kullanılır (odak/kaydırma kaybı ve sil-yarat maliyeti yok).
		_signature = sig
		for update in _dyn:
			update.call()
		return
	_structure = structure
	refresh_if_changed(sig)


func _render() -> void:
	if _body == null:
		return
	if model == null:
		model = _results.build_model()
	var focus_role := _begin_render()
	_dyn = []
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
	_add_infra_hint()
	if model.parcels.size() > 1:
		_add_others()


## Altyapı nedeniyle vazgeçen parsel varsa düz dille ne yapılacağı (yol çiz). Yalnız sim ret kodundan; yoksa satır yok.
func _add_infra_hint() -> void:
	var n := model.infra_declined_count()
	if n <= 0:
		return
	var key := &"m2.hint.infrastructure" if n == 1 else &"m2.hint.infrastructure_n"
	var l := _muted(UiText.t(key, {"n": n}))
	l.set_meta(META_ROW, ROW_HINT)
	_body.add_child(l)


func _step_label(key: StringName) -> Label:
	var l := UiFactory.label(UiText.t(key), UiTheme.V_LABEL_MUTED, true)
	l.set_meta(META_ROW, ROW_STEP)
	return l


func _add_decision(inner: VBoxContainer, row: M2ResultModel.ParcelRow) -> void:
	# Öneri öncesi karar AYRI etiketlenir; yatırımcı öneriyi henüz değerlendirmedi.
	if row.before_proposal:
		inner.add_child(UiFactory.label(UiText.t(&"m2.investor.prior"), UiTheme.V_LABEL_MUTED, true))
		_add_outcome_lines(inner, row, true)
		# Yatırım almış (aşama planned+) parsel yeniden değerlendirilmez: "bekliyor" demek yanıltıcı olur.
		var already := row.recorded == M2ResultModel.Decision.APPROVED \
				and v_development(row) != ParcelView.DEVELOPMENT_VACANT
		inner.add_child(UiFactory.label(UiText.t(&"m2.investor.already" if already else &"m2.investor.waiting"),
				&"", true))
		return
	if row.decision == M2ResultModel.Decision.NONE:
		inner.add_child(UiFactory.label(UiText.t(&"m2.investor.none"), UiTheme.V_LABEL_MUTED, true))
		return
	_add_outcome_lines(inner, row, false)


## Kayıtlı kararın satırları + (gerekçe kaydı varsa) "Nedenini gör" ya da dürüst "budandı" notu.
func v_development(row: M2ResultModel.ParcelRow) -> StringName:
	return row.view.development


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
	var meter := MeterBar.create(_ctx, v.progress_pm)
	bar.add_child(meter)
	var pct := UiFactory.label(_pct_text(v.progress_pm))
	pct.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(pct)
	inner.add_child(bar)
	_dyn.append(func() -> void:
		var pm := model.primary.view.progress_pm
		_set_meter(meter, pm)
		pct.text = _pct_text(pm))


func _pct_text(permille: int) -> String:
	return UiText.t(&"format.percent", {"value": UiText.number(permille / 10)})


func _set_meter(meter: MeterBar, permille: int) -> void:
	meter.permille = clampi(permille, 0, 1000)
	meter.queue_redraw()


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
	var pipe := _pair(UiText.t(&"m2.row.pipeline"), _pipeline_text())
	inner.add_child(_named(pipe, ROW_METRIC))
	_bind_value(pipe, _pipeline_text)
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


func _pipeline_text() -> String:
	return UiText.t(&"m2.row.pipeline_value",
			{"res": UiText.number(model.pipeline_residential), "com": UiText.number(model.pipeline_commercial)})


## Satırın sağ değer etiketini her yenilemede `text_fn` ile günceller.
func _bind_value(row: Control, text_fn: Callable) -> void:
	var val := row.get_child(1) as Label
	_dyn.append(func() -> void: val.text = text_fn.call())


func _add_municipal(inner: VBoxContainer) -> void:
	if model.municipal_available:
		var row := _pair(UiText.t(&"m2.row.municipal"), UiText.money(model.municipal_value))
		inner.add_child(_named(row, ROW_METRIC))
		_bind_value(row, func() -> String: return UiText.money(model.municipal_value))
	else:
		var key := model.municipal_reason_key if model.municipal_reason_key != &"" \
				else EconomyOutcomeView.REASON_MUNICIPAL_REVENUE_NOT_BUILT
		inner.add_child(_named(_pair(UiText.t(&"m2.row.municipal"), UiText.t(&"state.not_built_short")), ROW_METRIC))
		inner.add_child(_muted(UiText.t(key)))


func _metric_pair(r: M2ResultModel.MetricRow) -> Control:
	var caption := UiText.t(StringName("m2.metric.%s" % r.key))
	var key := r.key
	var row := _pair(caption, _metric_value(r))
	_bind_value(row, func() -> String: return _metric_value(model.metric(key)))
	return _named(row, ROW_METRIC)


func _metric_value(r: M2ResultModel.MetricRow) -> String:
	if r.key == &"housed_households":
		var value := UiText.t(&"m2.row.housed_value", {"housed": UiText.number(r.value),
				"total": UiText.number(r.total)})
		if r.delta_valid:
			value += " (%s)" % delta_text(r.delta)
		return value
	if r.key == &"rent_income":
		return rent_text(r)
	return delta_text(r.delta) if r.delta_valid else UiText.number(r.value)


## İşaretli tamsayı: +3, 0, −2.
static func delta_text(value: int) -> String:
	if value > 0:
		return UiText.t(&"format.delta_plus", {"value": UiText.number(value)})
	return UiText.number(value)


## Kira geliri satırı: sim henüz kira üretmediyse ("0 ¤") yer tutucu para simgesi yazılmaz (para birimi AÇIK, Q-003).
static func rent_text(r: M2ResultModel.MetricRow) -> String:
	if r.value == 0 and (not r.delta_valid or r.delta == 0):
		return UiText.t(&"m2.row.none_yet")
	return delta_money(r.delta) if r.delta_valid else UiText.money(r.value)


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
	for i in model.reactions.size():
		_body.add_child(_reaction_card(model.reactions[i], i))
	if model.reactions_hidden > 0:
		_body.add_child(_muted(UiText.t(&"m2.political.more", {"n": model.reactions_hidden})))
	if model.council_built:
		var council := UiFactory.label(_council_text(), &"", true)
		_body.add_child(council)
		_dyn.append(func() -> void: council.text = _council_text())


func _intensity_text(intensity: int) -> String:
	return UiText.t(&"m2.political.intensity", {"value": _pct_text(intensity)})


func _stance_text(stance: int) -> String:
	return UiText.t(&"m2.political.stance", {"value": UiText.fixed(stance, true)})


func _council_text() -> String:
	return UiText.t(&"m2.council.line", {"open": model.council_open, "done": model.council_done})


func _reaction_card(g: GroupReactionView, index: int) -> Control:
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
	var meter := MeterBar.create(_ctx, g.intensity)
	bar.add_child(meter)
	var inten := UiFactory.label(_intensity_text(g.intensity))
	inten.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(inten)
	inner.add_child(bar)
	var stance := UiFactory.label(_stance_text(g.stance), UiTheme.V_LABEL_MUTED, true)
	inner.add_child(stance)
	_dyn.append(func() -> void:
		var cur := model.reactions[index]
		_set_meter(meter, cur.intensity)
		inten.text = _intensity_text(cur.intensity)
		stance.text = _stance_text(cur.stance))
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
