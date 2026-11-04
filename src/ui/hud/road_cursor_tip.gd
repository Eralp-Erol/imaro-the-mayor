class_name RoadCursorTip
extends PanelContainer
## Yol çiziminde imleç yanındaki kısa durum etiketi (T-042 adım 3): geçerliyse sim'in kapasite önizlemesi, geçersizse
## Türkçe ret nedeni. Metin çağıranda `UiText` ile üretilir (burada sayı/neden uydurulmaz). Fareyi kapmaz
## (`MOUSE_FILTER_IGNORE`). Masaüstünde imleci izler; dokunmatikte parmağın altında kalmaması için verilen sabit
## dikdörtgenin üst-ortasına oturur (`place_at_top`). Renk durumu yalnız renk değil: geçersizde "Geçersiz" simgesi/metin
## ayrıca verilir (ux-states-a11y §1).

const CURSOR_OFFSET := Vector2(18.0, 20.0)
const MAX_WIDTH := 340.0
## Kartın dolu HUD kartlarından uzak kalacağı en küçük boşluk (>= 8 pt aralık kuralı).
const GAP := 8.0
## Bu uzunluğa dek metin tek satırdır (ekran: ~ MAX_WIDTH'e sığar).
const SHORT_CHARS := 36
const MODE_TOP := &"top"
const MODE_NEAR := &"near"

var _label: Label = null
var _step_label: Label = null
var _valid: bool = true
var _hud: HudRoot = null
var _mode: StringName = &""
var _cursor: Vector2 = Vector2.ZERO
var _bounds: Vector2 = Vector2.ZERO


static func create() -> RoadCursorTip:
	var tip := RoadCursorTip.new()
	tip.theme_type_variation = UiTheme.V_HUD_BAR
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip.z_index = 20
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(box)
	# Adım yönergesi her adımda imleç yanında ("1/3 ...", "2/3 ...", "3/3 ..."); altında karar/ret metni.
	tip._step_label = UiFactory.label("", UiTheme.V_LABEL_TITLE, true)
	tip._step_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip._step_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	tip._step_label.visible = false
	box.add_child(tip._step_label)
	tip._label = UiFactory.label("", UiTheme.V_LABEL_OK, true)
	tip._label.custom_minimum_size = Vector2(MAX_WIDTH, 0.0)
	tip._label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tip._label)
	return tip


## Tek yerleşim mantığı (B-019): HUD'un yüzen kartları (bildirim satırları, hız ipucu) değişince, ya da düzen değişince
## kart son yerleştirme kipiyle (imleç yanı / üst-orta) yeniden yerleşir. Çağıran yalnız imleç/hedef değişince
## yerleştirir.
func follow_hud(hud: HudRoot) -> void:
	_hud = hud
	if not hud.floaters_changed.is_connected(_reflow):
		hud.floaters_changed.connect(_reflow)
		hud.layout_changed.connect(_reflow)


func _reflow() -> void:
	if _hud == null or not visible or _mode == &"":
		return
	var obstacles := _hud.occupied_rects()
	if _mode == MODE_TOP:
		place_at_top(_hud.free_map_rect(), obstacles)
	else:
		place_near(_cursor, _bounds, _hud.free_map_rect(), obstacles)


func text() -> String:
	return _label.text if _label != null else ""


## Adım yönergesi satırı ("1/3 · ...", "2/3 · ...", "3/3 · ..."); yoksa boş.
func step_text() -> String:
	return _step_label.text if _step_label != null else ""


func is_valid_state() -> bool:
	return _valid


func show_text(message: String, valid: bool, step_line: String = "") -> void:
	_valid = valid
	_label.text = message
	_label.visible = not message.is_empty()
	_step_label.text = step_line
	_step_label.visible = not step_line.is_empty()
	# Kısa metin kutuyu doldurmaz (sarma kapalı, içeriğe göre genişlik); uzun ret nedeni MAX_WIDTH'te sarılır.
	var short := message.length() <= SHORT_CHARS
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF if short else TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(0.0 if short else MAX_WIDTH, 0.0)
	_label.theme_type_variation = UiTheme.V_LABEL_OK if valid else UiTheme.V_LABEL_DANGER
	visible = not message.is_empty() or not step_line.is_empty()
	reset_size()


func hide_tip() -> void:
	visible = false


## İmleç yanı: ekran dışına taşarsa içeri kaydırılır. `area` (boş değilse): HUD'un boş harita dikdörtgeni; etiket
## araç çubuğu/panel/yardım alanlarına binmesin diye bu dikdörtgenin içinde tutulur. `obstacles`: dolu HUD kartları
## (bildirim satırları, hız ipucu); kart bunların üstüne binmez (B-014).
func place_near(cursor: Vector2, bounds: Vector2, area: Rect2 = Rect2(), obstacles: Array[Rect2] = []) -> void:
	_mode = MODE_NEAR
	_cursor = cursor
	_bounds = bounds
	var sz := get_combined_minimum_size()
	var pos := cursor + CURSOR_OFFSET
	pos.x = clampf(pos.x, 0.0, maxf(0.0, bounds.x - sz.x))
	if pos.y + sz.y > bounds.y:
		pos.y = cursor.y - CURSOR_OFFSET.y - sz.y
	if area.has_area():
		pos.x = clampf(pos.x, area.position.x, maxf(area.position.x, area.end.x - sz.x))
		pos.y = clampf(pos.y, area.position.y, maxf(area.position.y, area.end.y - sz.y))
	position = _clear_spot(pos, sz, area, obstacles, cursor)
	size = sz


## Sabit yer: verilen dikdörtgenin üst-ortası (dokunmatik); `obstacles` doluysa boş bir yere kayar.
func place_at_top(area: Rect2, obstacles: Array[Rect2] = []) -> void:
	_mode = MODE_TOP
	var sz := get_combined_minimum_size()
	var pos := Vector2(area.position.x + maxf(0.0, (area.size.x - sz.x) * 0.5), area.position.y + 8.0)
	position = _clear_spot(pos, sz, area, obstacles, area.get_center())
	size = sz


## `preferred` engellerle (aralarında GAP) çakışmıyorsa o; aksi halde engellerin çevresinden ve alanın köşelerinden
## türetilen adaylar içinde tercih edilene EN YAKIN boş yer. Hiç yer yoksa tercih edilen (kart yine de görünür).
static func _clear_spot(preferred: Vector2, sz: Vector2, area: Rect2, obstacles: Array[Rect2],
		anchor: Vector2) -> Vector2:
	if obstacles.is_empty() or _is_clear(Rect2(preferred, sz), area, obstacles):
		return preferred
	var candidates: Array[Vector2] = []
	for o in obstacles:
		candidates.append(Vector2(preferred.x, o.end.y + GAP))
		candidates.append(Vector2(preferred.x, o.position.y - GAP - sz.y))
		candidates.append(Vector2(o.end.x + GAP, preferred.y))
		candidates.append(Vector2(o.position.x - GAP - sz.x, preferred.y))
		candidates.append(Vector2(o.end.x + GAP, o.position.y))
		candidates.append(Vector2(o.position.x, o.end.y + GAP))
	if area.has_area():
		for x in [area.position.x + GAP, area.end.x - GAP - sz.x, preferred.x]:
			for y in [area.position.y + GAP, area.end.y - GAP - sz.y, preferred.y]:
				candidates.append(Vector2(x, y))
	var best := preferred
	var best_d := INF
	for c in candidates:
		if not _is_clear(Rect2(c, sz), area, obstacles):
			continue
		var d := (c + sz * 0.5).distance_to(anchor)
		if d < best_d:
			best_d = d
			best = c
	return best


static func _is_clear(rect: Rect2, area: Rect2, obstacles: Array[Rect2]) -> bool:
	if area.has_area() and not area.grow(0.01).encloses(rect):
		return false
	for o in obstacles:
		if rect.intersects(o.grow(GAP - 0.01)):
			return false
	return true
