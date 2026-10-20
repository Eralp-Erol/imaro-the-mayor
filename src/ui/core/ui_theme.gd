class_name UiTheme
extends RefCounted
## Notr tema (T-019): `UiContext` + `UiTokens` → Godot `Theme`. Görsel kimlik KANON DEĞİL (Q-011); belirteç
## dosyası
## değişince tema değişir. Odak halkası her zaman görünür (ux-states-a11y §1); durum yalnız renkle verilmez
## (seçili düğme dolgu + çerçeve kalınlığı + metin rengi değişir).

const V_HUD_BAR := &"HudBar"
const V_PANEL_CARD := &"PanelCard"
const V_MOCK_CHIP := &"MockChip"
const V_MOCK_BANNER := &"MockBanner"
const V_LABEL_MUTED := &"LabelMuted"
const V_LABEL_TITLE := &"LabelTitle"
const V_LABEL_HEADING := &"LabelHeading"
const V_LABEL_DANGER := &"LabelDanger"
const V_LABEL_ON_MOCK := &"LabelOnMock"
const V_LABEL_OK := &"LabelOk"
const V_PANEL_ALERT := &"PanelAlert"
## "Tahmin" işareti: dolgusuz, vurgu çerçeveli çip (mock rengi DEĞİL; mock sarıdır, tahmin çerçevelidir).
const V_ESTIMATE_CHIP := &"EstimateChip"
## Kart: panel içinde gruplanmış bilgi bloğu (oylama, kalem, öğe).
const V_INFO_CARD := &"InfoCard"


static func build(ctx: UiContext) -> Theme:
	var t := Theme.new()
	var tk := ctx.tokens
	t.default_font_size = ctx.font_body()
	_build_button(t, ctx)
	_build_labels(t, ctx)
	var pad := int(ctx.spacing())
	t.set_type_variation(V_HUD_BAR, &"PanelContainer")
	t.set_stylebox(&"panel", V_HUD_BAR, _flat(tk.color("hud_bg"), Color.TRANSPARENT, 0, 0, pad, pad / 2))
	t.set_type_variation(V_PANEL_CARD, &"PanelContainer")
	t.set_stylebox(&"panel", V_PANEL_CARD,
		_flat(tk.color("panel_bg"), tk.color("border"), 1, int(tk.size("radius")), pad, pad))
	# Veri hatası kutusu: renk tek başına değil, kalın çerçeve + simge + metin (ux-states-a11y §1).
	t.set_type_variation(V_PANEL_ALERT, &"PanelContainer")
	t.set_stylebox(&"panel", V_PANEL_ALERT,
		_flat(tk.color("panel_bg_alt"), tk.color("danger"), 3, int(tk.size("radius")), pad, pad))
	t.set_type_variation(V_ESTIMATE_CHIP, &"PanelContainer")
	var chip := _flat(Color.TRANSPARENT, tk.color("accent"), 2, 4, pad / 2, 1)
	chip.draw_center = false
	t.set_stylebox(&"panel", V_ESTIMATE_CHIP, chip)
	t.set_type_variation(V_INFO_CARD, &"PanelContainer")
	t.set_stylebox(&"panel", V_INFO_CARD,
		_flat(tk.color("panel_bg_alt"), tk.color("border"), 1, int(tk.size("radius")), pad, pad))
	t.set_type_variation(V_MOCK_CHIP, &"PanelContainer")
	t.set_stylebox(&"panel", V_MOCK_CHIP, _flat(tk.color("mock"), Color.TRANSPARENT, 0, 4, pad / 2, 1))
	t.set_type_variation(V_MOCK_BANNER, &"PanelContainer")
	t.set_stylebox(&"panel", V_MOCK_BANNER, _flat(tk.color("mock"), Color.TRANSPARENT, 0, 0, pad, 2))
	t.set_stylebox(&"panel", &"PanelContainer", _flat(tk.color("panel_bg_alt"), Color.TRANSPARENT, 0, 4, pad, pad / 2))
	t.set_constant(&"separation", &"VBoxContainer", int(ctx.spacing() / 2.0))
	t.set_constant(&"separation", &"HBoxContainer", int(ctx.spacing()))
	return t


static func _build_button(t: Theme, ctx: UiContext) -> void:
	var tk := ctx.tokens
	var pad_h := int(ctx.spacing() * 1.5)
	var pad_v := int(ctx.spacing())
	var radius := int(tk.size("radius"))
	var border := tk.color("border")
	t.set_stylebox(&"normal", &"Button", _flat(tk.color("button_bg"), border, 1, radius, pad_h, pad_v))
	t.set_stylebox(&"hover", &"Button", _flat(tk.color("button_hover"), border, 1, radius, pad_h, pad_v))
	t.set_stylebox(&"pressed", &"Button", _flat(tk.color("button_pressed"), tk.color("text"), 2, radius, pad_h, pad_v))
	t.set_stylebox(&"hover_pressed", &"Button",
		_flat(tk.color("button_pressed"), tk.color("text"), 2, radius, pad_h, pad_v))
	t.set_stylebox(&"disabled", &"Button",
		_flat(tk.color("button_disabled"), tk.color("button_bg"), 1, radius, pad_h, pad_v))
	var focus := _flat(Color.TRANSPARENT, tk.color("focus"), int(tk.size("focus_width")) + 1, radius, pad_h, pad_v)
	focus.draw_center = false
	t.set_stylebox(&"focus", &"Button", focus)
	t.set_color(&"font_color", &"Button", tk.color("text"))
	t.set_color(&"font_hover_color", &"Button", tk.color("text"))
	t.set_color(&"font_focus_color", &"Button", tk.color("text"))
	t.set_color(&"font_pressed_color", &"Button", tk.color("text_on_accent"))
	t.set_color(&"font_hover_pressed_color", &"Button", tk.color("text_on_accent"))
	t.set_color(&"font_disabled_color", &"Button", tk.color("text_disabled"))
	t.set_font_size(&"font_size", &"Button", ctx.font_body())


static func _build_labels(t: Theme, ctx: UiContext) -> void:
	var tk := ctx.tokens
	t.set_color(&"font_color", &"Label", tk.color("text"))
	t.set_font_size(&"font_size", &"Label", ctx.font_body())
	_label_variation(t, V_LABEL_MUTED, tk.color("text_muted"), ctx.font_small())
	_label_variation(t, V_LABEL_TITLE, tk.color("text"), ctx.font_title())
	_label_variation(t, V_LABEL_HEADING, tk.color("text"), ctx.font_heading())
	_label_variation(t, V_LABEL_DANGER, tk.color("danger"), ctx.font_body())
	_label_variation(t, V_LABEL_ON_MOCK, tk.color("text_on_accent"), ctx.font_small())
	_label_variation(t, V_LABEL_OK, tk.color("ok"), ctx.font_body())


static func _label_variation(t: Theme, variation: StringName, color: Color, font_size: int) -> void:
	t.set_type_variation(variation, &"Label")
	t.set_color(&"font_color", variation, color)
	t.set_font_size(&"font_size", variation, font_size)


static func _flat(bg: Color, border: Color, border_w: int, radius: int, margin_h: int, margin_v: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb
