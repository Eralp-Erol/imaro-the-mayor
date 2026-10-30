class_name RoadDrawPanel
extends FlowPanel
## "Yol çiz" paneli (T-042 adım 3; CAN-04, D-008): `RoadDrawTool` durumunun görünümü. Masaüstü ve dokunmatik AYNI
## bileşenler (hedefler `UiContext`ten, hover'a bağlı bilgi yok). Sayılar (uzunluk, bölge, kapasite birimi) sim'in kuru
## koşusundan gelir (`CommandResult.args`); ret nedeni sim'in anahtarıdır (`public_work.reject.*`). Maliyet:
## bütçe kuruluysa "N birim" (sim), değilse "henüz kurulmadı" (Q-003 AÇIK; para simgesi yok).
## Metro/çok uzak bantta çizim kilitlidir: "Yakınlaşın".
## Bu panel komut göndermez; düğmeler araç fiillerini çağırır (`RoadDrawTool.confirm/undo_last/cancel`), araç yalnız
## `SimFacade.submit_command` kullanır.

const CONFIRM_MIN_HEIGHT := 56.0
const CONFIRM_MIN_WIDTH := 200.0
const PLAN_HINT_DAYS := 10
## İpucu taramasında bölge başına en çok bakılan parsel (sınırlı iş; bulunamazsa ipucu GÖSTERİLMEZ).
const PLAN_HINT_SCAN := 600

var tool: RoadDrawTool = null

var _confirm_button: Button = null
var _cancel_button: Button = null
var _undo_button: Button = null
## İpucu önbelleği: (son yol komutu, gün/PLAN_HINT_DAYS) -> bölgede plansız parsel var mı (ilk bulunanda durur).
var _hint_key: String = ""
var _hint_value: bool = false


static func create(ctx: UiContext, facade: SimFacade, draw_tool: RoadDrawTool) -> RoadDrawPanel:
	var p := RoadDrawPanel.new()
	p.tool = draw_tool
	p._setup_flow(ctx, facade)
	p.refresh()
	return p


func confirm_button() -> Button:
	return _confirm_button


func cancel_button() -> Button:
	return _cancel_button


func undo_button() -> Button:
	return _undo_button


## Tick/olay başına değil, ARAÇ durumu değişince yeniden çizer (imleç ret/önizlemeyi değiştirmedikçe düğüm kurmaz).
func refresh() -> void:
	refresh_if_changed(_signature_of())


func _signature_of() -> String:
	var parts: Array[String] = [str(tool.step), str(tool.band_active), str(_plan_hint_needed()), str(tool.is_valid()),
			str(tool.message),
			str(tool.message_args), str(tool.has_undoable_road()), str(_facade.speed() == SimFacade.SPEED_PAUSED),
			str(_undo_refund())]
	if tool.verdict != null:
		parts.append(String(tool.verdict.reason_key))
		parts.append(str(tool.verdict.args))
	return "|".join(parts)


func _render() -> void:
	if _body == null or tool == null:
		return
	var focus_role := _begin_render()
	_confirm_button = null
	_cancel_button = null
	_undo_button = null
	if not tool.band_active:
		_body.add_child(UiFactory.label(UiText.t(&"road.zoom_in"), UiTheme.V_LABEL_DANGER, true))
		_add_undo_row()
		_restore_focus(focus_role)
		return
	_body.add_child(_muted(UiText.t(&"road.step_line", {"n": _step_number(), "total": 3})))
	# Adım 3/3 (yol yapılabilir): tek satır yönerge + büyük Onayla EN ÜSTTE (kullanıcı denemesi: onayı bulamadı).
	var review_confirmable := tool.step == RoadDrawTool.Step.REVIEW and tool.can_confirm()
	if review_confirmable:
		var hint := UiFactory.label(UiText.t(&"road.confirm_hint_touch" if _ctx.is_touch() else &"road.confirm_hint"),
				UiTheme.V_LABEL_HEADING, true)
		hint.add_theme_color_override("font_color", _ctx.tokens.color("ok"))
		_tag(hint, "road_confirm_hint")
		_body.add_child(hint)
		_add_buttons()
	_body.add_child(UiFactory.label(UiText.t(_step_key()), &"", true))
	if tool.step == RoadDrawTool.Step.SENDING and _facade.speed() == SimFacade.SPEED_PAUSED:
		_body.add_child(UiFactory.label(UiText.t(&"road.step.sending_paused"), UiTheme.V_LABEL_DANGER, true))
	_add_message()
	if tool.step == RoadDrawTool.Step.PICK_A and _plan_hint_needed():
		var plan_hint := UiFactory.label(UiText.t(&"plan.hint.after_road"), UiTheme.V_LABEL_HEADING, true)
		plan_hint.add_theme_color_override("font_color", _ctx.tokens.color("ok"))
		_tag(plan_hint, "plan_hint")
		_body.add_child(plan_hint)
		if _ctx.is_touch():
			_body.add_child(_muted(UiText.t(&"plan.hint.touch")))
	if tool.step == RoadDrawTool.Step.PICK_B or tool.step == RoadDrawTool.Step.REVIEW \
			or tool.step == RoadDrawTool.Step.SENDING:
		_add_preview_card()
	if not review_confirmable:
		_add_buttons()
	_body.add_child(_muted(UiText.t(&"road.no_building")))
	if not _ctx.is_touch():
		_body.add_child(_muted(UiText.t(&"road.keys_help")))
	_restore_focus(focus_role)


## Yol çizildikten sonra ipucu: YALNIZ son yolun değdiği bölgede sim `plan_state` gerçekten `unplanned`/`plan_rejected`
## parsel varsa (plan durumu yoksa/mock ise ya da hepsi planlıysa ipucu yok). Sonuç önbelleklenir (yol, 10 gün).
func _plan_hint_needed() -> bool:
	var works := _facade.public_works()
	if works.is_empty():
		return false
	var last := works[works.size() - 1]
	var key := "%d|%d" % [last.command_id, _facade.current_tick() / PLAN_HINT_DAYS]
	if key == _hint_key:
		return _hint_value
	_hint_key = key
	_hint_value = false
	for code: String in last.region_units.keys():
		var ids := _facade.parcel_ids(StringName(code))
		for i in mini(ids.size(), PLAN_HINT_SCAN):
			if PlanStateText.needs_plan(_facade.plan_state(ids[i])):
				_hint_value = true
				return true
	return false


func _step_number() -> int:
	match tool.step:
		RoadDrawTool.Step.PICK_B:
			return 2
		RoadDrawTool.Step.REVIEW, RoadDrawTool.Step.SENDING:
			return 3
	return 1


func _step_key() -> StringName:
	match tool.step:
		RoadDrawTool.Step.PICK_B:
			return &"road.step.pick_b"
		RoadDrawTool.Step.REVIEW:
			return &"road.step.review"
		RoadDrawTool.Step.SENDING:
			return &"road.step.sending"
	return &"road.step.pick_a"


func _add_message() -> void:
	if tool.message == RoadDrawTool.MSG_NONE:
		return
	match tool.message:
		RoadDrawTool.MSG_FAILED:
			var reason := UiText.reject_reason(StringName(tool.message_args.get("reason_key", "")),
					tool.message_args.get("args", {}))
			_body.add_child(UiFactory.label(UiText.t(&"road.step.failed", {"reason": reason}),
					UiTheme.V_LABEL_DANGER, true))
		RoadDrawTool.MSG_START_NOT_ON_ROAD:
			_body.add_child(UiFactory.label(UiText.t(tool.message), UiTheme.V_LABEL_DANGER, true))
		_:
			_body.add_child(UiFactory.label(UiText.t(tool.message), UiTheme.V_LABEL_OK, true))


func _add_preview_card() -> void:
	var parts := _card()
	var card: PanelContainer = parts[0]
	var inner: VBoxContainer = parts[1]
	if tool.verdict == null:
		inner.add_child(_muted(UiText.t(&"road.step.pick_b")))
		_body.add_child(card)
		return
	if tool.is_valid():
		var args := tool.preview_args()
		# Ana vurgu: karar (başlık boyunda, ok rengi); sayılar ikincil (T-042 sanat düzeltmesi).
		var verdict_label := UiFactory.label(UiText.t(&"road.valid"), UiTheme.V_LABEL_HEADING, true)
		verdict_label.add_theme_color_override("font_color", _ctx.tokens.color("ok"))
		inner.add_child(verdict_label)
		inner.add_child(UiFactory.label(UiText.t(&"road.length", {"length": UiText.number(int(args.get("length_m", 0)))}),
				&"", true))
		inner.add_child(UiFactory.label(UiText.t(&"road.capacity", {"units": int(args.get("units_total", 0))}),
				&"", true))
		var regions: Dictionary = args.get("regions", {})
		var codes: Array = regions.keys()
		codes.sort()
		if codes.size() > 1:   # tek bölgede satır toplamı tekrarlar
			for code: String in codes:
				inner.add_child(_muted(UiText.t(&"road.capacity_region", {"region": code, "units": int(regions[code])})))
		inner.add_child(_muted(UiText.t(&"road.class_line", {"class": UiText.t(&"road.class.local")})))
		inner.add_child(_muted(cost_line(args)))
	else:
		var reason := UiText.reject_reason(tool.verdict.reason_key, tool.verdict.args)
		inner.add_child(UiFactory.label(UiText.t(&"road.invalid", {"reason": reason}), UiTheme.V_LABEL_DANGER, true))
	_body.add_child(card)


func _add_buttons() -> void:
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_button = UiFactory.button(_ctx, UiText.t(&"road.confirm"), true)
	# Birincil vurgu + büyük hedef (dokunmatikte >= 44 pt zaten target_primary tabanından gelir).
	UiFactory.emphasize(_ctx, _confirm_button, maxf(CONFIRM_MIN_HEIGHT, _ctx.target_primary() * 1.2))
	_confirm_button.custom_minimum_size.x = maxf(_confirm_button.custom_minimum_size.x, _ctx.px(CONFIRM_MIN_WIDTH))
	_tag(_confirm_button, "road_confirm")
	_confirm_button.disabled = not tool.can_confirm()
	_confirm_button.pressed.connect(func() -> void:
		tool.confirm()
		refresh())
	row.add_child(_confirm_button)
	_cancel_button = UiFactory.button(_ctx, UiText.t(&"road.cancel"), false)
	_tag(_cancel_button, "road_cancel")
	_cancel_button.disabled = tool.step == RoadDrawTool.Step.PICK_A or tool.step == RoadDrawTool.Step.SENDING
	_cancel_button.pressed.connect(func() -> void:
		tool.cancel()
		refresh())
	row.add_child(_cancel_button)
	_body.add_child(row)
	_add_undo_row()


## "Maliyet: N birim" (bütçe kuruluysa, sim `cost_available`); yoksa sim'in verdiği gerekçe ("henüz kurulmadı").
## Birim para birimi değildir (Q-003 AÇIK): simge yok.
static func cost_line(args: Dictionary) -> String:
	if bool(args.get("cost_available", false)):
		return UiText.t(&"road.cost_units", {"units": UiText.number(int(args.get("cost", 0)))})
	return UiText.t(&"road.cost_line", {"cost": UiText.t(StringName(
			args.get("cost_reason_key", "public_work.cost.not_built")))})


## Son yolu geri almanın iadesi (sim kuru koşusu); bütçe yoksa ya da geri alınacak yol yoksa -1.
func _undo_refund() -> int:
	if tool == null or not tool.has_undoable_road():
		return -1
	var probe := _facade.validate_command(SimCommand.public_work_undo_last())
	if probe.is_rejected() or not bool(probe.args.get("refund_available", false)):
		return -1
	return int(probe.args.get("refund", 0))


func _add_undo_row() -> void:
	# Ölü düğme yok: geri alınacak yol yoksa düğme hiç görünmez.
	if not tool.has_undoable_road():
		return
	_undo_button = UiFactory.button(_ctx, UiText.t(&"road.undo_last"), false)
	_tag(_undo_button, "road_undo")
	_undo_button.disabled = tool.step == RoadDrawTool.Step.SENDING
	_undo_button.pressed.connect(func() -> void:
		tool.undo_last()
		refresh())
	_body.add_child(_undo_button)
	var refund := _undo_refund()
	if refund >= 0:
		_body.add_child(_muted(UiText.t(&"road.refund_line", {"units": UiText.number(refund)})))
