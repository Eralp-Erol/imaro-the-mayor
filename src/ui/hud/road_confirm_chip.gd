class_name RoadConfirmChip
extends Button
## Yol çiziminde yolun BİTİŞ ucuna bağlı büyük onay işareti (kullanıcı denemesi: "Onayla yalnız sağ paneldeki
## küçük kutuda, çok zor anladım"). İkinci tıklamadan sonra (Adım 3/3, yol yapılabilirse) bitiş ucunun yanında belirir:
## "Onaylamak için Enter ya da buraya tıkla · Esc iptal". Tıklama = onay (`confirm_requested`); yeni bir yere tıklamak
## bitişi değiştirir (araç davranışı). Yalnız UI: komutu çağıran (`RoadDrawController`) araca iletir. Birincil düğme
## stili (`UiFactory.emphasize`, ui_tokens renkleri); dokunmatik hedef >= 44 pt (`UiContext.target_primary`).

signal confirm_requested

const OFFSET := Vector2(14.0, -14.0)
const MIN_HEIGHT_DESKTOP := 48.0
const MAX_WIDTH := 360.0

var _touch: bool = false
var _demolition: bool = false


static func create(ctx: UiContext) -> RoadConfirmChip:
	var chip := RoadConfirmChip.new()
	chip._touch = ctx != null and ctx.is_touch()
	chip.visible = false
	chip.z_index = 25
	chip.focus_mode = Control.FOCUS_NONE   # Enter dünya girdisinden gelir; odak çalmaz
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chip.text = UiText.t(&"road.chip_touch" if chip._touch else &"road.chip")
	chip.tooltip_text = chip.text
	var min_h := MIN_HEIGHT_DESKTOP
	if ctx != null:
		min_h = maxf(min_h, ctx.target_primary())
		UiFactory.emphasize(ctx, chip, min_h)
	chip.custom_minimum_size = Vector2(MAX_WIDTH if not chip._touch else 260.0, min_h)
	chip.pressed.connect(chip.confirm_requested.emit)
	return chip


## T-042b · Yıkım içeren yolda işaretin metni açıkça "Yıkımı onaylamak için ..." der (kazara onay olmasın).
func set_demolition(on: bool) -> void:
	if on == _demolition:
		return
	_demolition = on
	var key := &"road.chip_demolish" if on else &"road.chip"
	if _touch:
		key = &"road.chip_demolish_touch" if on else &"road.chip_touch"
	text = UiText.t(key)
	tooltip_text = text


## Bitiş ucunun ekran konumuna oturur (sağ-üst), `area` (HUD'un boş harita dikdörtgeni) içinde tutulur.
func place_at(end_screen: Vector2, area: Rect2) -> void:
	var sz := get_combined_minimum_size()
	var pos := end_screen + Vector2(OFFSET.x, OFFSET.y - sz.y)
	if area.has_area():
		# Sağa sığmazsa bitişin soluna al.
		if pos.x + sz.x > area.end.x:
			pos.x = end_screen.x - OFFSET.x - sz.x
		pos.x = clampf(pos.x, area.position.x, maxf(area.position.x, area.end.x - sz.x))
		pos.y = clampf(pos.y, area.position.y, maxf(area.position.y, area.end.y - sz.y))
	position = pos
	size = sz
