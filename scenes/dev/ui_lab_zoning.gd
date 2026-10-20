class_name UiLabZoning
extends VBoxContainer
## ui_lab MİNİ imar akışı (T-022'nin gerçek imar önerisi akışı bunun yerine geçer):
##   parsel seç -> arazi kullanımı seç -> `validate_command` (kuru koşu; gerekçeli ret ekranda) -> gönder ->
##   `submit_command` -> olay akışında sonuç (HUD bildirim şeridi) -> "Nedenini gör".
## Onay düğmesi `validate_command` sonucuna bağlıdır: ret anahtarı = devre dışı gerekçesi (ADR-0005 §9).
## CAN-03: yalnız imar KOŞULU önerilir; metin bunu söyler (`zoning.no_instant_building`).

signal submitted(result: CommandResult)

var last_validation: CommandResult = null
var last_submit: CommandResult = null
var chosen_use: StringName = &""

var _ctx: UiContext = null
var _facade: SimFacade = null
var _parcel_id: int = 0
var _target: Label = null
var _use_buttons: Dictionary = {}
var _verdict: Label = null
var _send: ActionButton = null
var _queued: Label = null


static func create(ctx: UiContext, facade: SimFacade, parcel_id: int) -> UiLabZoning:
	var z := UiLabZoning.new()
	z._ctx = ctx
	z._facade = facade
	z._parcel_id = parcel_id
	z.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	z._build()
	return z


func choose_use(use: StringName) -> void:
	chosen_use = use
	for key: StringName in _use_buttons:
		(_use_buttons[key] as Button).set_pressed_no_signal(key == use)
	_validate()


func send() -> void:
	if last_validation == null or last_validation.is_rejected():
		return
	last_submit = _facade.submit_command(_command())
	_queued.visible = not last_submit.is_rejected()
	_queued.text = UiText.t(&"zoning.queued") if not last_submit.is_rejected() else UiText.reject_reason(
		last_submit.reason_key, last_submit.args)
	submitted.emit(last_submit)


## Olay akışından bu önerinin sonucu (komut kimliği eşleşirse): kabul -> uygulandı, ret -> sim gerekçesiyle.
func handle_event(event: SimEvent) -> void:
	if last_submit == null or last_submit.command_id <= 0 or event.command_id != last_submit.command_id:
		return
	if event.kind == SimEvent.KIND_COMMAND_REJECTED:
		_queued.visible = true
		_queued.theme_type_variation = UiTheme.V_LABEL_DANGER
		_queued.text = "%s: %s" % [UiText.t(&"zoning.outcome.rejected"), UiText.reject_reason(
			event.message_key, event.args)]
	elif event.kind == SimEvent.KIND_COMMAND_APPLIED:
		_queued.visible = true
		_queued.text = UiText.t(&"zoning.outcome.applied")


func verdict_text() -> String:
	return _verdict.text


func queued_text() -> String:
	return _queued.text if _queued.visible else ""


func send_button() -> ActionButton:
	return _send


func use_button(use: StringName) -> Button:
	return _use_buttons.get(use) as Button


func _build() -> void:
	_target = UiFactory.label("", &"", true)
	add_child(_target)
	if _parcel_id <= 0:
		_target.text = UiText.t(&"zoning.pick_parcel")
		return
	_target.text = "%s: %s" % [UiText.t(&"zoning.target"), UiText.humanize(SimContract.parcel_ref(_parcel_id))]
	add_child(UiFactory.label(UiText.t(&"zoning.pick_use"), UiTheme.V_LABEL_MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", int(_ctx.spacing()))
	flow.add_theme_constant_override(&"v_separation", int(_ctx.spacing()))
	add_child(flow)
	for use in UiConfig.land_uses():
		var b := UiFactory.button(_ctx, UiText.t(use), true, true)
		b.pressed.connect(choose_use.bind(use))
		_use_buttons[use] = b
		flow.add_child(b)
	_verdict = UiFactory.label("", &"", true)
	add_child(_verdict)
	_send = ActionButton.create(_ctx, UiText.t(&"zoning.send"), true)
	_send.set_enabled(false, UiText.t(&"zoning.pick_use"))
	_send.pressed.connect(send)
	add_child(_send)
	_queued = UiFactory.label("", UiTheme.V_LABEL_MUTED, true)
	_queued.visible = false
	add_child(_queued)
	add_child(UiFactory.label(UiText.t(&"zoning.no_instant_building"), UiTheme.V_LABEL_MUTED, true))


func _command() -> SimCommand:
	return SimCommand.zoning_propose(PackedInt64Array([_parcel_id]), chosen_use)


func _validate() -> void:
	last_validation = _facade.validate_command(_command())
	if last_validation.is_rejected():
		var why := UiText.reject_reason(last_validation.reason_key, last_validation.args)
		_verdict.theme_type_variation = UiTheme.V_LABEL_DANGER
		_verdict.text = why
		_send.set_enabled(false, UiText.t(&"zoning.validate.rejected"))
	else:
		_verdict.theme_type_variation = &""
		_verdict.text = UiText.t(&"zoning.validate.ok")
		_send.set_enabled(true)
