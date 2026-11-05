class_name DrawerGrip
extends Control
## Çekmece tutamacı: ortada kısa yatay çubuk (sürüklenebilir olduğunu gösterir). Etkileşimi `PanelShell` işler.

var _color: Color = Color.WHITE


func _ready() -> void:
	_color = UiTokens.load_default().color("text_muted")


func _draw() -> void:
	var w := minf(size.x * 0.2, 96.0)
	var h := maxf(4.0, minf(size.y * 0.2, 8.0))
	draw_rect(Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h), _color)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
