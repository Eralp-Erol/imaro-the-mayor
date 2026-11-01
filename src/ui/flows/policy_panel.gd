class_name PolicyPanel
extends FlowPanel
## Politikalar paneli (T-065 Aşama 1, D-016 §1; CAN-03 belediye fiili, SIM-12): belediyenin KALICI politikalarını
## aç/kapa. Şimdilik tek politika: "Yeniden iskân" (kamulaştırmada ev ayırma). Okuduğu sim alanları:
## `SimFacade.policies()` -> `PolicyView.policy_id/enabled/changed_by_command`. Eylem: `SimCommand.policy_set`.
## - Açıkken ve kapalıyken ne olacağı düz Türkçe iki ayrı cümleyle yazılır; seçim kalıcıdır (not).
## - Komut sonraki tick sınırında uygulanır: istek gönderilince durum DEĞİŞMEZ, "istek gönderildi" yazar ve düğme
##   kilitlenir (iyimser değişim yok); durum sim'de değişince panel yansıtır. Ret (hemen ya da tick sınırında) sim'in
##   nedeniyle yazılır.
## - Dünya hiç politika sunmuyorsa "henüz kurulmadı" durumu görünür, düğme yoktur (ölü düğme yok).
## `memo`: panel yeniden kurulsa da (profil/yön değişimi) bekleyen istek ve ret kalsın diye sahibin tuttuğu sözlük.

const KEY_PENDING := "pending"
const KEY_REFUSED := "refused"
## Kuyruğa girmiş isteğin bekleme payı: bu kadar tick sonra hâlâ değişmediyse bekleyen kaydı bırakılır.
const PENDING_TICKS := 3

var _memo: Dictionary = {}
var _toggle: Button = null
var _state_label: Label = null


static func create(ctx: UiContext, facade: SimFacade, memo: Dictionary = {}) -> PolicyPanel:
	var p := PolicyPanel.new()
	p._memo = memo
	p._setup_flow(ctx, facade)
	p._render()
	return p


func toggle_button() -> Button:
	return _toggle


## Durum değerinin metni ("Açık"/"Kapalı"); politika yoksa boş.
func status_text() -> String:
	return _state_label.text if _state_label != null else ""


func signature_now() -> String:
	var parts: Array[String] = []
	for v in _facade.policies():
		parts.append("%s/%s/%d" % [v.policy_id, v.enabled, v.changed_by_command])
	var lapsed := false   # bekleme payı dolduysa imza değişsin ki bekleyen kayıt bırakılsın
	for id: Variant in _pending():
		lapsed = lapsed or _facade.current_tick() > int(_pending()[id]["tick"]) + PENDING_TICKS
	return "%s|%s|%s|%s" % ["|".join(parts), var_to_str(_pending()), var_to_str(_refused()), lapsed]


func refresh() -> void:
	refresh_if_changed(signature_now())


## Tick sınırında reddedilen istek (`command.rejected`): nedeni panelde görünür.
func handle_event(event: SimEvent) -> void:
	if event.kind != SimEvent.KIND_COMMAND_REJECTED:
		return
	var pending := _pending()
	for id: Variant in pending.keys():
		if int(pending[id]["command_id"]) == event.command_id:
			_refused()[id] = PolicyText.refusal_reason(event.args)
			pending.erase(id)
			_render()
			return


func _pending() -> Dictionary:
	if not _memo.has(KEY_PENDING):
		_memo[KEY_PENDING] = {}
	return _memo[KEY_PENDING]


func _refused() -> Dictionary:
	if not _memo.has(KEY_REFUSED):
		_memo[KEY_REFUSED] = {}
	return _memo[KEY_REFUSED]


func _render() -> void:
	if _body == null:
		return
	var focus_role := _begin_render()
	_toggle = null
	_state_label = null
	var rows: Array[PolicyView] = []
	for v in _facade.policies():
		if v.policy_id == PolicyView.ID_RESETTLEMENT:   # yalnız metni olan politikalar (uydurma satır yok)
			rows.append(v)
	_prune(rows)
	_signature = signature_now()
	if rows.is_empty():
		state_view.show_not_built(&"policy.not_built")
		return
	state_view.show_normal()
	for v in rows:
		_body.add_child(_resettlement_card(v))
	_restore_focus(focus_role)


## Bekleyen istek sim'e yansıdıysa ya da payı dolduysa silinir; ret yalnız hâlâ listelenen politika için kalır.
func _prune(rows: Array[PolicyView]) -> void:
	var tick := _facade.current_tick()
	var pending := _pending()
	for v in rows:
		if pending.has(v.policy_id):
			var p: Dictionary = pending[v.policy_id]
			if v.enabled == bool(p["enabled"]) or v.changed_by_command == int(p["command_id"]) \
					or tick > int(p["tick"]) + PENDING_TICKS:
				pending.erase(v.policy_id)


func _resettlement_card(v: PolicyView) -> Control:
	var parts := _card()
	var inner: VBoxContainer = parts[1]
	inner.add_child(UiFactory.label(PolicyText.policy_name(v.policy_id), UiTheme.V_LABEL_TITLE, true))
	var state_row := HBoxContainer.new()
	state_row.add_child(UiFactory.label("%s:" % UiText.t(&"policy.state_caption"), UiTheme.V_LABEL_MUTED))
	_state_label = UiFactory.label(PolicyText.state_text(v.enabled),
			UiTheme.V_LABEL_OK if v.enabled else UiTheme.V_LABEL_MUTED)
	_tag(_state_label, "policy_state")
	state_row.add_child(_state_label)
	inner.add_child(state_row)
	# Eylem ve geri bildirimi ÜSTTE (alt sayfa/dar yan panelde kaydırmadan görünsün); açıklamalar altta.
	var waiting := _pending().has(v.policy_id)
	_toggle = UiFactory.button(_ctx, UiText.t(
			&"policy.resettlement.turn_off" if v.enabled else &"policy.resettlement.turn_on"), true)
	_toggle.disabled = waiting
	_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag(_toggle, "policy_toggle")
	var target := not v.enabled
	var id := v.policy_id
	_toggle.pressed.connect(func() -> void: request(id, target))
	inner.add_child(_toggle)
	if waiting:
		inner.add_child(UiFactory.label(UiText.t(&"policy.pending"), &"", true))
	elif _refused().has(v.policy_id):
		inner.add_child(UiFactory.label(UiText.t(&"policy.refused", {"reason": _refused()[v.policy_id]}),
				UiTheme.V_LABEL_DANGER, true))
	inner.add_child(UiFactory.label(UiText.t(&"policy.resettlement.what"), &"", true))
	inner.add_child(UiFactory.label(UiText.t(&"policy.resettlement.when_on"), &"", true))
	inner.add_child(UiFactory.label(UiText.t(&"policy.resettlement.when_off"), &"", true))
	inner.add_child(_muted(UiText.t(&"policy.permanent_note")))
	return parts[0]


## Politikayı aç/kapa isteği (tek yol `submit_command`). Ret hemen gösterilir; kabulde sim'in uygulamasını bekler.
func request(policy_id: StringName, enabled: bool) -> CommandResult:
	if _pending().has(policy_id):
		return null
	var result := _facade.submit_command(SimCommand.policy_set(policy_id, enabled))
	if result.is_rejected():
		_refused()[policy_id] = PolicyText.refusal_reason(result.args)
	else:
		_refused().erase(policy_id)
		_pending()[policy_id] = {"command_id": result.command_id, "tick": _facade.current_tick(), "enabled": enabled}
	_render()
	return result
