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
## İpucu taraması KARE DİLİMLİDİR (`pump_hint`): bir karede en çok bu kadar (µs) + bir parsel. Ölçüm: tek seferlik 600
## parsellik tarama yol onayından sonraki ilk karede ~45 ms tutuyordu (HUD yoklaması -> panel imzası).
const PLAN_HINT_BUDGET_US := 2000

var tool: RoadDrawTool = null

var _confirm_button: Button = null
var _cancel_button: Button = null
var _undo_button: Button = null
var _accept_button: Button = null
var _back_button: Button = null
var _undo_yes_button: Button = null
var _undo_keep_button: Button = null
var _demolish_button: Button = null
var _demolish_yes_button: Button = null
var _demolish_keep_button: Button = null
## T-042b · Yıkımlı yolu geri alma ikinci adımda onaylanır (binalar geri gelir, halk tepkisi gelmez).
var _undo_pending: bool = false
## D-014 §1 · Yolu yıkma ek onay adımı: hedef yol komut kimliği (NO_ID = beklemiyor). Yıkım geri alınamaz.
var _demolish_target: int = SimContract.NO_ID
## İpucu önbelleği: (son yol komutu, gün/PLAN_HINT_DAYS) -> bölgede plansız parsel var mı (ilk bulunanda durur).
var _hint_key: String = ""
var _hint_value: bool = false
var _hint_scan: PlanHintScan = null
## B-012 · Son çizimde sim bir komutu "dünya hazırlanıyor" (`busy`) diye reddetti: bu durum sim OLAYI ile değil,
## görünümün işi bitirmesiyle kalkar; denetleyici bu bayrak açıkken paneli kısa aralıkla yeniden doğrulatır.
var _awaiting_world: bool = false


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


## T-042b · "Kamulaştırarak geç" (sim teklifi), onaydan vazgeçme ve yıkımlı yolu geri alma onayı düğmeleri (yoksa null).
func accept_button() -> Button:
	return _accept_button


func back_button() -> Button:
	return _back_button


func undo_confirm_button() -> Button:
	return _undo_yes_button


func undo_keep_button() -> Button:
	return _undo_keep_button


func undo_pending() -> bool:
	return _undo_pending


## D-014 §1 · "Son yolu yık", yıkım onayı ve vazgeç düğmeleri (yoksa null).
func demolish_button() -> Button:
	return _demolish_button


func demolish_confirm_button() -> Button:
	return _demolish_yes_button


func demolish_keep_button() -> Button:
	return _demolish_keep_button


func demolish_pending() -> bool:
	return _demolish_target != SimContract.NO_ID


## Tick/olay başına değil, ARAÇ durumu değişince yeniden çizer (imleç ret/önizlemeyi değiştirmedikçe düğüm kurmaz).
func refresh() -> void:
	refresh_if_changed(_signature_of())


## Panel şu an sim'in "dünya hazırlanıyor" reddini gösteriyor mu (bkz. `_awaiting_world`).
func awaiting_world() -> bool:
	return _awaiting_world


func _signature_of() -> String:
	var parts: Array[String] = [str(tool.step), str(tool.band_active), str(_plan_hint_needed()), str(tool.is_valid()),
			str(tool.message),
			str(tool.message_args), str(tool.has_undoable_road()), str(_facade.speed() == SimFacade.SPEED_PAUSED),
			str(_undo_refund()), str(tool.expropriate), str(_undo_pending), _demolish_signature(),
			str(_resettlement_policy())]
	if tool.verdict != null:
		parts.append(String(tool.verdict.reason_key))
		parts.append(str(tool.verdict.args))
	return "|".join(parts)


func _render() -> void:
	if _body == null or tool == null:
		return
	var focus_role := _begin_render()
	_awaiting_world = false
	_confirm_button = null
	_cancel_button = null
	_undo_button = null
	_accept_button = null
	_back_button = null
	_undo_yes_button = null
	_undo_keep_button = null
	_demolish_button = null
	_demolish_yes_button = null
	_demolish_keep_button = null
	if not tool.has_undoable_road():
		_undo_pending = false
	var standing := tool.last_road()
	if standing == null or standing.command_id != _demolish_target:
		_demolish_target = SimContract.NO_ID   # hedef yol artık yok/değişti: onay bekleme
	# B-019 · Yıkım onayı panelin EN ÜSTÜNDE (Onayla düğmesiyle aynı ilke): dokunmatikte kart panelin altında kalıp
	# "Evet, yık / Vazgeç" kaydırmadan görünmüyordu. Onay beklerken diğer eylemler (geri al/yık) onayın altında kalır.
	if _demolish_target != SimContract.NO_ID and standing != null:
		_add_demolish_confirm(standing)
		if _demolish_target != SimContract.NO_ID:
			_scroll_to_top.call_deferred()
	if not tool.band_active:
		_body.add_child(UiFactory.label(UiText.t(&"road.zoom_in"), UiTheme.V_LABEL_DANGER, true))
		_add_undo_row()
		_restore_focus(focus_role)
		return
	_body.add_child(_muted(UiText.t(&"road.step_line", {"n": _step_number(), "total": 3})))
	# Adım 3/3 (yol yapılabilir): tek satır yönerge + büyük Onayla EN ÜSTTE (kullanıcı denemesi: onayı bulamadı).
	var review_confirmable := tool.step == RoadDrawTool.Step.REVIEW and tool.can_confirm()
	var review_offer := tool.step == RoadDrawTool.Step.REVIEW and not tool.offer().is_empty()
	if review_confirmable:
		var hint_key := &"road.confirm_hint_touch" if _ctx.is_touch() else &"road.confirm_hint"
		if tool.demolishes():
			hint_key = &"expropriation.confirm_hint_touch" if _ctx.is_touch() else &"expropriation.confirm_hint"
		var hint := UiFactory.label(UiText.t(hint_key), UiTheme.V_LABEL_HEADING, true)
		hint.add_theme_color_override("font_color", _ctx.tokens.color("ok"))
		_tag(hint, "road_confirm_hint")
		_body.add_child(hint)
		_add_buttons()
	elif review_offer:   # T-042b: teklif kabul düğmesi de en üstte (kart altta okunur)
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
	if not review_confirmable and not review_offer:
		_add_buttons()
	_body.add_child(_muted(UiText.t(&"road.no_building")))
	if not _ctx.is_touch():
		_body.add_child(_muted(UiText.t(&"road.keys_help")))
	_restore_focus(focus_role)


## Yol çizildikten sonra ipucu: YALNIZ son yolun değdiği bölgede sim `plan_state` gerçekten `unplanned`/`plan_rejected`
## parsel varsa (plan durumu yoksa/mock ise ya da hepsi planlıysa ipucu yok). Sonuç önbelleklenir (yol, 10 gün).
## Önbellek anahtarı değişince tarama KARE DİLİMLERİNDE yapılır (`PlanHintScan`, `pump_hint`); bitene kadar
## ipucu görünmez,
## biten sonuç eski tek seferlik taramayla AYNIDIR (aynı sıra, aynı üst sınır).
func _plan_hint_needed() -> bool:
	var works := _facade.public_works()
	if works.is_empty():
		_hint_scan = null
		return false
	var last := works[works.size() - 1]
	var key := "%d|%d" % [last.command_id, _facade.current_tick() / PLAN_HINT_DAYS]
	if key == _hint_key:
		return _hint_value
	_hint_key = key
	_hint_value = false
	var facade := _facade
	# `parcel_ids` yalnız değişmez parsel kaynağını okur (ListParcelSource salt okunur): işçi iş parçacığında güvenli.
	_hint_scan = PlanHintScan.create(last.region_units.keys(),
			func(code: Variant) -> PackedInt64Array: return facade.parcel_ids(StringName(code)),
			func(id: int) -> bool: return PlanStateText.needs_plan(facade.plan_state(id)), PLAN_HINT_SCAN)
	_hint_scan.start()
	return false


## Dilimli ipucu taraması (her kare, araç açıkken). Sonuç değişirse paneli tazeler. true = tarama sürüyor.
func pump_hint(budget_us: int = PLAN_HINT_BUDGET_US) -> bool:
	if _hint_scan == null:
		return false
	var finished := _hint_scan.step(budget_us)
	if not finished:
		return true
	var found := _hint_scan.found
	_hint_scan = null
	if found:
		_hint_value = true
		refresh()
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
		var expropriating := ExpropriationText.has_impact(args)
		var verdict_label := UiFactory.label(UiText.t(&"expropriation.valid_title" if expropriating else &"road.valid"),
				UiTheme.V_LABEL_HEADING, true)
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
		if expropriating:
			_add_expropriation_block(inner, args, true)
		elif tool.expropriate and ExpropriationText.is_empty_strip(args):
			inner.add_child(_muted(UiText.t(&"expropriation.empty_valid")))
	elif not tool.offer().is_empty() and ExpropriationText.is_empty_strip(tool.offer()):
		inner.add_child(UiFactory.label(UiText.t(&"expropriation.empty_title"), UiTheme.V_LABEL_HEADING, true))
		inner.add_child(UiFactory.label(UiText.t(&"expropriation.empty_body"), &"", true))
	elif not tool.offer().is_empty():
		inner.add_child(UiFactory.label(UiText.t(&"expropriation.offer_title"), UiTheme.V_LABEL_DANGER, true))
		_add_expropriation_block(inner, tool.offer(), false)
	else:
		var reason := UiText.reject_reason(tool.verdict.reason_key, tool.verdict.args)
		inner.add_child(UiFactory.label(UiText.t(&"road.invalid", {"reason": reason}), UiTheme.V_LABEL_DANGER, true))
	_body.add_child(card)


## T-042b · Kamulaştırma bloğu: yalnız sim args'ından düz Türkçe sayılar + "Bedel: henüz kurulmadı". `accepted`: teklif
## kabul edilmiş, onay bekleniyor (geri alınabilirlik notu görünür); değilse teklif ("Kamulaştırarak geç").
func _add_expropriation_block(inner: VBoxContainer, args: Dictionary, accepted: bool) -> void:
	if not accepted:
		inner.add_child(_muted(UiText.t(&"expropriation.offer_intro")))
	var impact := UiFactory.label(ExpropriationText.impact_line(args), UiTheme.V_LABEL_HEADING, true)
	if ExpropriationText.demolishes(args):
		impact.add_theme_color_override("font_color", _ctx.tokens.color("danger"))
	_tag(impact, "expropriation_impact")
	inner.add_child(impact)
	inner.add_child(UiFactory.label(ExpropriationText.cost_line(), &"", true))
	for line in ExpropriationText.detail_lines(args):
		inner.add_child(_muted(line))
	var nearby := ExpropriationText.nearby_line(args)
	if nearby != "":
		inner.add_child(_muted(nearby))
	_add_resettlement_rows(inner, args)
	inner.add_child(_muted(UiText.t(&"expropriation.react_note")))
	if accepted:
		# TODO(B-013 / Q-030): metin "başka bir yol yapana kadar" vaat ediyor; sim pencereyi ilk haftalık taramada
		# kapatabiliyor. Karar gelene dek metin DEĞİŞTİRİLMEDİ; kural B kalırsa düzeltilecek (production/bugs/B-013.md).
		inner.add_child(_muted(UiText.t(&"expropriation.undo_note")))


## T-065 · Yeniden iskân satırları (sim args'ından): ev ayrılan hane, ev olmayan hane (yol yine yapılır), gösterge
## bedel. Politika dünyada var ve KAPALIysa tek satır "kapalı, ev ayrılmaz"; politika yoksa hiçbir şey eklenmez.
func _add_resettlement_rows(inner: VBoxContainer, args: Dictionary) -> void:
	for row in ExpropriationText.resettlement_rows(args):
		var variation: StringName = &""
		match String(row["tone"]):
			"ok":
				variation = UiTheme.V_LABEL_OK
			"danger":
				variation = UiTheme.V_LABEL_DANGER
			"muted":
				variation = UiTheme.V_LABEL_MUTED
		var label := UiFactory.label(String(row["text"]), variation, true)
		_tag(label, "resettlement_row")
		inner.add_child(label)
	if _resettlement_policy() == 0 and ExpropriationText.resettlement_off_needed(args, false):
		var off := _muted(UiText.t(&"resettlement.preview.off"))
		_tag(off, "resettlement_off")
		inner.add_child(off)


## Sim'in yeniden iskân politikası: 1 açık, 0 kapalı, -1 dünyada yok (not gösterilmez).
func _resettlement_policy() -> int:
	for v in _facade.policies():
		if v.policy_id == PolicyView.ID_RESETTLEMENT:
			return 1 if v.enabled else 0
	return -1


func _add_buttons() -> void:
	var row := _button_row()
	var offer := tool.offer()
	if not offer.is_empty() and tool.step == RoadDrawTool.Step.REVIEW:
		# 1. adım: sim'in kamulaştırma teklifini kabul et (sayılar kartta); 2. adım yıkım onayıdır.
		var empty_strip := ExpropriationText.is_empty_strip(offer)
		_accept_button = UiFactory.button(_ctx, UiText.t(
				&"expropriation.empty_accept" if empty_strip else &"expropriation.accept"), true)
		UiFactory.emphasize(_ctx, _accept_button, maxf(CONFIRM_MIN_HEIGHT, _ctx.target_primary() * 1.2))
		_tag(_accept_button, "road_expropriate")
		_accept_button.pressed.connect(func() -> void:
			tool.accept_offer()
			refresh())
		row.add_child(_accept_button)
	if tool.expropriate and tool.step == RoadDrawTool.Step.REVIEW \
			and not ExpropriationText.is_empty_strip(tool.preview_args()):
		_back_button = UiFactory.button(_ctx, UiText.t(&"expropriation.back"), false)
		_tag(_back_button, "road_expropriate_back")
		_back_button.pressed.connect(func() -> void:
			tool.withdraw_offer()
			refresh())
		row.add_child(_back_button)
	if _accept_button == null:   # teklif varken Onayla yerine tek birincil eylem: "Kamulaştırarak geç"
		_confirm_button = UiFactory.button(_ctx, UiText.t(
				&"expropriation.confirm" if tool.demolishes() else &"road.confirm"), true)
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


## Geri al + yık satırı (D-014 §1). Ölü düğme yok: yol yoksa hiçbiri görünmez; geri alma kapandıysa sim'in nedeni
## yazılır; yıkım sim önizlemesi reddederse düğme yerine ret nedeni yazılır.
func _add_undo_row() -> void:
	var last := tool.last_road()
	if last == null:
		return
	if _demolish_target != SimContract.NO_ID:
		return   # onay kartı panelin üstünde çizildi (`_render`)
	if tool.has_undoable_road():
		_add_undo_controls(last)
	else:
		var closed := _facade.validate_command(SimCommand.public_work_undo_last())
		if closed.is_rejected():
			_body.add_child(_muted(UiText.t(&"road.undo_closed",
					{"reason": UiText.reject_reason(closed.reason_key, closed.args)})))
	_add_demolish_controls(last)


static func _is_busy_reason(reason_key: StringName) -> bool:
	return reason_key == StringName(RoadDraftCheck.key_of(RoadDraftCheck.REASON_BUSY))


func _demolish_signature() -> String:
	var last := tool.last_road() if tool != null else null
	if last == null:
		return "-"
	var probe := _facade.validate_command(SimCommand.public_work_demolish(last.command_id))
	return "%d|%d|%s|%d" % [last.command_id, int(probe.args.get("cost", -1)), String(probe.reason_key), _demolish_target]


func _add_undo_controls(last: PublicWorkView) -> void:
	if _undo_pending and last != null and last.expropriated:
		_add_undo_confirm(last)
		return
	_undo_button = UiFactory.button(_ctx, UiText.t(&"road.undo_last"), false)
	_tag(_undo_button, "road_undo")
	_undo_button.disabled = tool.step == RoadDrawTool.Step.SENDING
	_undo_button.pressed.connect(func() -> void:
		if last != null and last.expropriated:   # T-042b: yıkımlı yol ikinci adımda onaylanır
			_undo_pending = true
		else:
			tool.undo_last()
		refresh())
	_body.add_child(_undo_button)
	var refund := _undo_refund()
	if refund >= 0:
		_body.add_child(_muted(UiText.t(&"road.refund_line", {"units": UiText.number(refund)})))


## T-042b · Yıkımlı yolu geri alma onayı (D-011): binalar geri gelir, halkın tepkisi geri GELMEZ. Geri gelecek sayılar
## sim'in önizlemesi (`restored_*`) ya da yolun sim kaydıdır; iade satırı (bütçe) varsa ayrıca gösterilir.
func _add_undo_confirm(last: PublicWorkView) -> void:
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(UiFactory.label(UiText.t(&"expropriation.undo_title"), UiTheme.V_LABEL_HEADING, true))
	var warning := UiFactory.label(UiText.t(&"expropriation.undo_warning"), UiTheme.V_LABEL_DANGER, true)
	_tag(warning, "expropriation_undo_warning")
	inner.add_child(warning)
	var probe := _facade.validate_command(SimCommand.public_work_undo_last())
	var restore := ExpropriationText.restore_args(probe.args, last)
	if not restore.is_empty():
		inner.add_child(UiFactory.label(UiText.t(&"expropriation.undo_restores", restore), &"", true))
	if last.resettlement_applied and last.rehoused_households > 0:   # T-065: taşınan haneler (hedefte kalan kadarı) döner
		inner.add_child(_muted(UiText.t(&"resettlement.undo_returns", {"count": last.rehoused_households})))
	var refund := _undo_refund()
	if refund >= 0:
		inner.add_child(_muted(UiText.t(&"road.refund_line", {"units": UiText.number(refund)})))
	var row := _button_row()
	_undo_yes_button = UiFactory.button(_ctx, UiText.t(&"expropriation.undo_confirm"), true)
	_tag(_undo_yes_button, "road_undo_confirm")
	_undo_yes_button.pressed.connect(func() -> void:
		_undo_pending = false
		tool.undo_last()
		refresh())
	row.add_child(_undo_yes_button)
	_undo_keep_button = UiFactory.button(_ctx, UiText.t(&"expropriation.undo_keep"), false)
	_tag(_undo_keep_button, "road_undo_keep")
	_undo_keep_button.pressed.connect(func() -> void:
		_undo_pending = false
		refresh())
	row.add_child(_undo_keep_button)
	inner.add_child(row)
	_body.add_child(parts[0])


## D-014 §1 · Yolu yık: her zaman bulunur (geri alma penceresi kapansa da), maliyeti görünür. Yalnız en son duran yol
## hedeflenir (sim önizlemesi `public_work.demolish`). Sim yıkımı reddediyorsa düğme yok, neden yazılır.
func _add_demolish_controls(last: PublicWorkView) -> void:
	var probe := _facade.validate_command(SimCommand.public_work_demolish(last.command_id))
	if probe.is_rejected():
		_awaiting_world = _awaiting_world or _is_busy_reason(probe.reason_key)
		_body.add_child(_muted(UiText.t(&"road.demolish_blocked",
				{"reason": UiText.reject_reason(probe.reason_key, probe.args)})))
		return
	_demolish_button = UiFactory.button(_ctx, UiText.t(&"road.demolish_last"), false)
	_tag(_demolish_button, "road_demolish")
	_demolish_button.disabled = tool.step == RoadDrawTool.Step.SENDING
	_demolish_button.pressed.connect(func() -> void:
		_demolish_target = last.command_id
		refresh())
	_body.add_child(_demolish_button)
	_body.add_child(_muted(_demolish_cost_text(probe.args)))


## "Yıkım maliyeti: N birim" (sim `cost_available`) ya da "henüz kurulmadı"; birim para birimi değildir (Q-003).
static func _demolish_cost_text(args: Dictionary) -> String:
	if bool(args.get("cost_available", false)):
		return UiText.t(&"road.demolish_cost_units", {"units": UiText.number(int(args.get("cost", 0)))})
	return UiText.t(&"road.demolish_cost_unset")


## Ek onay adımı: yıkım geri alınamaz; alınan parsel/bina dönmez, tepki kalır (sim önizlemesi `restores_nothing`).
func _add_demolish_confirm(last: PublicWorkView) -> void:
	var probe := _facade.validate_command(SimCommand.public_work_demolish(last.command_id))
	if probe.is_rejected():   # onay beklerken durum değişti: bekleme biter, ret nedeni satırı çizilir
		_demolish_target = SimContract.NO_ID
		_add_demolish_controls(last)
		return
	var args := probe.args
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(UiFactory.label(UiText.t(&"road.demolish_title"), UiTheme.V_LABEL_HEADING, true))
	inner.add_child(UiFactory.label(UiText.t(&"road.demolish_effect", {
			"length": UiText.number(int(args.get("length_m", 0))), "units": int(args.get("units_total", 0))}), &"", true))
	var taken := int(args.get("taken_parcels", 0))
	var warning_text := UiText.t(&"road.demolish_warning")
	if bool(args.get("expropriated", false)) and taken > 0:
		warning_text = UiText.t(&"road.demolish_warning_taken", {"parcels": taken})
	var warning := UiFactory.label(warning_text, UiTheme.V_LABEL_DANGER, true)
	_tag(warning, "road_demolish_warning")
	inner.add_child(warning)
	inner.add_child(_muted(_demolish_cost_text(args)))
	var row := _button_row()
	_demolish_yes_button = UiFactory.button(_ctx, UiText.t(&"road.demolish_confirm"), true)
	_tag(_demolish_yes_button, "road_demolish_confirm")
	_demolish_yes_button.pressed.connect(func() -> void:
		_demolish_target = SimContract.NO_ID
		tool.demolish_road(last.command_id)
		refresh())
	row.add_child(_demolish_yes_button)
	_demolish_keep_button = UiFactory.button(_ctx, UiText.t(&"road.demolish_keep"), false)
	_tag(_demolish_keep_button, "road_demolish_keep")
	_demolish_keep_button.pressed.connect(func() -> void:
		_demolish_target = SimContract.NO_ID
		refresh())
	row.add_child(_demolish_keep_button)
	inner.add_child(row)
	_body.add_child(parts[0])


## Onay kartı ilk görünür satır olsun: panelin kaydırma kabı varsa en üste alınır (kart kaydırmadan görünür).
func _scroll_to_top() -> void:
	var n: Node = get_parent()
	while n != null:
		var sc := n as ScrollContainer
		if sc != null:
			sc.scroll_vertical = 0
			return
		n = n.get_parent()
