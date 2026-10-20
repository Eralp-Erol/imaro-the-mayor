class_name AgendaBadge
extends Button
## Gündem rozeti (L1; modal DEĞİL): bekleyen öğe sayısı + en yakın süre; tıklayınca L2 Gündem paneli
## (T-020/T-022).
## Veri kaynağı `AgendaItemView` (sözleşme v1.1 TEKNİK isteği) henüz yoktur: veri verilmedikçe rozet
## GİZLİDİR (sahte sayı
## yok). `set_data` yalnız gerçek (ya da MOCK işaretli) veriyle çağrılır; `mock` true ise metne MOCK eklenir.

var _ctx: UiContext = null


static func create(ctx: UiContext) -> AgendaBadge:
	var b := AgendaBadge.new()
	b._ctx = ctx
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(ctx.target_min(), ctx.target_min())
	b.visible = false
	return b


## `count` <= 0 ise gizlenir. `days_left` en yakın son tarihe kalan gün (sim'den).
func set_data(count: int, days_left: int, is_mock: bool) -> void:
	visible = count > 0
	if count <= 0:
		return
	var text := "%s: %d — %s" % [UiText.t(&"agenda.title"), count, UiText.t(&"format.days", {"n": days_left})]
	if is_mock:
		text += " (%s)" % UiText.t(&"app.mock_badge")
	self.text = text
	tooltip_text = UiText.t(&"hud.agenda_badge", {"n": count, "days": days_left})
