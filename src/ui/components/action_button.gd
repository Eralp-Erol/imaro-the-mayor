class_name ActionButton
extends VBoxContainer
## Eylem düğmesi + devre dışı GEREKÇESİ (ux-states-a11y §2 "Devre dışı"): düğme devre dışıysa nedeni
## yanında/altında
## yazar (yalnız soluk renk değil). Ölü düğme yoktur: `set_enabled(false, "")` gerekçesiz çağrılırsa
## gerekçe satırı
## `state.disabled_reason` + bilinmiyor metni gösterir (sessiz ölü düğme önlenir).

signal pressed

var button: Button = null
var _reason: Label = null


static func create(ctx: UiContext, text: String, primary: bool = true) -> ActionButton:
	var a := ActionButton.new()
	a.button = UiFactory.button(ctx, text, primary)
	a.button.pressed.connect(a._on_pressed)
	a.add_child(a.button)
	a._reason = UiFactory.label("", UiTheme.V_LABEL_MUTED, true)
	a._reason.visible = false
	a.add_child(a._reason)
	return a


func set_text(text: String) -> void:
	button.text = text


## `reason` devre dışıyken zorunludur (boşsa `common.unknown` ile dürüstçe belirtilir).
func set_enabled(enabled: bool, reason: String = "") -> void:
	button.disabled = not enabled
	if enabled:
		_reason.visible = false
		_reason.text = ""
		return
	var why := reason if not reason.is_empty() else UiText.t(&"common.unknown")
	_reason.text = UiText.t(&"state.disabled_reason", {"reason": why})
	_reason.visible = true


func is_enabled() -> bool:
	return not button.disabled


func reason_text() -> String:
	return _reason.text if _reason.visible else ""


func _on_pressed() -> void:
	pressed.emit()
