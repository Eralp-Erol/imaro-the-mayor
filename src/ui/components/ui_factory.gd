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


## Birincil vurgu: tek ekranın ana fiili (ör. "Onayla") dolu vurgu renginde (`ui_tokens` accent / text_on_accent) ve
## yüksekliği en az `min_height` (dokunmatikte >= 44 olmak üzere çağıran verir). Devre dışıyken tema stilini korur.
static func emphasize(ctx: UiContext, b: Button, min_height: float = 0.0) -> void:
	var accent := ctx.tokens.color("accent")
	var on_accent := ctx.tokens.color("text_on_accent")
	var pad_h := int(roundf(ctx.px(16.0)))
	var pad_v := int(roundf(ctx.px(10.0)))
	var states := {"normal": accent, "hover": accent.lightened(0.18), "pressed": accent.darkened(0.15),
			"focus": accent}
	for state: String in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[state]
		sb.set_corner_radius_all(int(roundf(ctx.px(6.0))))
		sb.content_margin_left = pad_h
		sb.content_margin_right = pad_h
		sb.content_margin_top = pad_v
		sb.content_margin_bottom = pad_v
		if state == "focus":
			sb.set_border_width_all(maxi(2, int(roundf(ctx.px(2.0)))))
			sb.border_color = ctx.tokens.color("focus")
		b.add_theme_stylebox_override(state, sb)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(color_name, on_accent)
	b.add_theme_font_size_override("font_size", ctx.font_title())
	if min_height > 0.0:
		b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, min_height)


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
