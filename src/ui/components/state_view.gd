class_name StateView
extends VBoxContainer
## Veri-bağımlı yüzeyler için durum bileşeni (ux-states-a11y §2): normal | yükleme | boş | hata |
## kurulmamış | devre dışı.
## Normal durumda `set_content` ile verilen içerik görünür; diğer durumlarda içerik gizlenir ve TEK cümlelik
## dürüst
## metin gösterilir. Yükleme, `loading_delay_s`'den kısa beklemede görünmez (titreme önleme, 300 ms).
## MOCK durumu bileşen değil bayraktır: üst yüzey (`MockBadge`/`MockBanner`) gösterir.

signal retry_requested

enum State { NORMAL, LOADING, EMPTY, ERROR, NOT_BUILT, DISABLED }

var loading_delay_s: float = 0.3

var _state: State = State.NORMAL
var _holder: VBoxContainer = null
var _title: Label = null
var _detail: Label = null
var _retry: Button = null
var _loading_elapsed: float = 0.0
var _loading_text: String = ""


static func create(ctx: UiContext) -> StateView:
	var v := StateView.new()
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v._holder = VBoxContainer.new()
	v._holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(v._holder)
	v._title = UiFactory.label("", UiTheme.V_LABEL_TITLE, true)
	v._detail = UiFactory.label("", UiTheme.V_LABEL_MUTED, true)
	v._retry = UiFactory.button(ctx, UiText.t(&"common.retry"), true)
	v._retry.pressed.connect(v.retry_requested.emit)
	v.add_child(v._title)
	v.add_child(v._detail)
	v.add_child(v._retry)
	v.show_normal()
	return v


func set_content(content: Control) -> void:
	for child in _holder.get_children():
		_holder.remove_child(child)
		child.queue_free()
	_holder.add_child(content)


func state() -> State:
	return _state


func show_normal() -> void:
	_state = State.NORMAL
	_apply("", "", false, true)


## `percent` < 0: ilerleme bilinmiyor, yüzde gösterilmez.
func show_loading(percent: int = -1) -> void:
	_state = State.LOADING
	_loading_elapsed = 0.0
	_loading_text = UiText.t(&"state.loading") if percent < 0 else UiText.t(&"state.loading_progress",
		{"percent": UiText.t(&"format.percent", {"value": percent})})
	_apply("", "", false, false)
	if loading_delay_s <= 0.0:
		_apply(_loading_text, "", false, false)


func show_empty(key: StringName = &"state.empty.generic", args: Dictionary = {}) -> void:
	_state = State.EMPTY
	_apply(UiText.t(key, args), "", false, false)


## `detail`: sim gerekçesi/ne yapılabilir (boşsa genel metin). Kurtarılabilir hatada yeniden dene düğmesi.
func show_error(detail: String = "", retryable: bool = true) -> void:
	_state = State.ERROR
	_apply(UiText.t(&"state.error.generic"), detail, retryable, false)
	_title.theme_type_variation = UiTheme.V_LABEL_DANGER


func show_not_built(key: StringName = &"state.not_built") -> void:
	_state = State.NOT_BUILT
	_apply(UiText.t(key), "", false, false)


func show_disabled(reason: String) -> void:
	_state = State.DISABLED
	var why := reason if not reason.is_empty() else UiText.t(&"common.unknown")
	_apply(UiText.t(&"state.disabled_reason", {"reason": why}), "", false, false)


## Şu an ekranda görünen durum metni (test/erişilebilirlik).
func visible_text() -> String:
	var parts := PackedStringArray()
	for l: Label in [_title, _detail]:
		if l.visible and not l.text.is_empty():
			parts.append(l.text)
	return " ".join(parts)


func retry_visible() -> bool:
	return _retry.visible


func content_visible() -> bool:
	return _holder.visible


func _process(delta: float) -> void:
	if _state != State.LOADING or _title.visible:
		return
	_loading_elapsed += delta
	if _loading_elapsed >= loading_delay_s:
		_apply(_loading_text, "", false, false)


func _apply(title: String, detail: String, retry: bool, content: bool) -> void:
	_holder.visible = content
	_title.theme_type_variation = UiTheme.V_LABEL_TITLE
	_title.text = title
	_title.visible = not title.is_empty()
	_detail.text = detail
	_detail.visible = not detail.is_empty()
	_retry.visible = retry
	set_process(_state == State.LOADING)
