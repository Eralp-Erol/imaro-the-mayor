class_name RoadCursorTip
extends PanelContainer
## Yol çiziminde imleç yanındaki kısa durum etiketi (T-042 adım 3): geçerliyse sim'in kapasite önizlemesi, geçersizse
## Türkçe ret nedeni. Metin çağıranda `UiText` ile üretilir (burada sayı/neden uydurulmaz). Fareyi kapmaz
## (`MOUSE_FILTER_IGNORE`). Masaüstünde imleci izler; dokunmatikte parmağın altında kalmaması için verilen sabit
## dikdörtgenin üst-ortasına oturur (`place_at_top`). Renk durumu yalnız renk değil: geçersizde "Geçersiz" simgesi/metin
## ayrıca verilir (ux-states-a11y §1).

const CURSOR_OFFSET := Vector2(18.0, 20.0)
const MAX_WIDTH := 340.0
## Bu uzunluğa dek metin tek satırdır (ekran: ~ MAX_WIDTH'e sığar).
const SHORT_CHARS := 36

var _label: Label = null
var _valid: bool = true


static func create() -> RoadCursorTip:
	var tip := RoadCursorTip.new()
	tip.theme_type_variation = UiTheme.V_HUD_BAR
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip.z_index = 20
	tip._label = UiFactory.label("", UiTheme.V_LABEL_OK, true)
	tip._label.custom_minimum_size = Vector2(MAX_WIDTH, 0.0)
	tip._label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(tip._label)
	return tip


func text() -> String:
	return _label.text if _label != null else ""


func is_valid_state() -> bool:
	return _valid


func show_text(message: String, valid: bool) -> void:
	_valid = valid
	_label.text = message
	# Kısa metin kutuyu doldurmaz (sarma kapalı, içeriğe göre genişlik); uzun ret nedeni MAX_WIDTH'te sarılır.
	var short := message.length() <= SHORT_CHARS
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF if short else TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(0.0 if short else MAX_WIDTH, 0.0)
	_label.theme_type_variation = UiTheme.V_LABEL_OK if valid else UiTheme.V_LABEL_DANGER
	visible = not message.is_empty()
	reset_size()


func hide_tip() -> void:
	visible = false


## İmleç yanı: ekran dışına taşarsa içeri kaydırılır.
func place_near(cursor: Vector2, bounds: Vector2) -> void:
	var sz := get_combined_minimum_size()
	var pos := cursor + CURSOR_OFFSET
	pos.x = clampf(pos.x, 0.0, maxf(0.0, bounds.x - sz.x))
	if pos.y + sz.y > bounds.y:
		pos.y = cursor.y - CURSOR_OFFSET.y - sz.y
	position = pos
	size = sz


## Sabit yer: verilen dikdörtgenin üst-ortası (dokunmatik).
func place_at_top(area: Rect2) -> void:
	var sz := get_combined_minimum_size()
	position = Vector2(area.position.x + maxf(0.0, (area.size.x - sz.x) * 0.5), area.position.y + 8.0)
	size = sz
