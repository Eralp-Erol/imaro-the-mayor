class_name UiFactory
extends RefCounted
## Bileşen üretim yardımcıları: ham boyut/renk yerine `UiContext` kullanır; metinler çağıranda `UiText` ile
## çevrilmiş gelir.


## Etiketli düğme. `primary`: sık fiil (≥ target_primary; dokunmatikte 56). Simge-tek düğme YOK: metin
## zorunludur.
static func button(ctx: UiContext, text: String, primary: bool = false, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = false
	var side := ctx.target_primary() if primary else ctx.target_min()
	b.custom_minimum_size = Vector2(side, side)
	return b


static func label(text: String, variation: StringName = &"", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Bir düğmenin/kontrolün gerçek (yerleşim sonrası) boyutu ya da en az isteği; hedef denetimi için.
static func hit_size(c: Control) -> Vector2:
	return Vector2(maxf(c.size.x, c.get_combined_minimum_size().x), maxf(c.size.y, c.get_combined_minimum_size().y))
