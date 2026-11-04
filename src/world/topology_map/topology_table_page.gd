class_name TopologyTablePage
extends Control
## Kanon karşılığı özet tablosu + kullanıcıya karar soruları sayfası (T-028 ölçüt 4). Metinler `TopologyTexts`'ten
## (sayılar modelden). Karar vermez, yalnız sunar: cevaplar koordinatör tarafından production/QUESTIONS.md Q-015'e
## işlenir. Damga her sayfada. Tasarım uzayı 2000x2000 px.

const DESIGN := 2000.0
const MARGIN := 30.0
const CHIP_W := 118.0
const ITEM_W := 560.0
const REQ_W := 190.0
const STATUS_COLORS := {
	"KANONİK": Color(0.10, 0.45, 0.20), "OY": Color(0.12, 0.35, 0.75), "ÇM": Color(0.78, 0.50, 0.05),
	"ÇIKARIM": Color(0.80, 0.22, 0.10), "AÇIK": Color(0.45, 0.25, 0.60), "TEKNİK": Color(0.40, 0.42, 0.48),
}

var model: TopologyModel = null

var _rows: Array[Dictionary] = []
var _questions: Array[Dictionary] = []


func setup(p_model: TopologyModel) -> void:
	model = p_model
	_rows = TopologyTexts.provenance(model)
	_questions = TopologyTexts.questions(model)
	queue_redraw()


## Sayfadaki metin öğeleri (test için): {"kind": &"stamp"|&"row"|&"question", "text": String}.
func labels() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"kind": &"stamp", "text": TopologyModel.STAMP}]
	for r in _rows:
		out.append({"kind": &"row", "text": "%s %s" % [r["status"], r["item"]]})
	for q in _questions:
		out.append({"kind": &"question", "text": "%s %s" % [q["id"], q["title"]]})
	return out


func _draw() -> void:
	if model == null:
		return
	var k := minf(size.x, size.y) / DESIGN
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	draw_rect(Rect2(Vector2.ZERO, Vector2(DESIGN, DESIGN)), TopologyStyle.PAPER)
	TopologyStyle.text(self, Vector2(MARGIN, 14), "%s — kanon karşılığı ve karar soruları" % TopologyTexts.TITLE, 40)
	draw_rect(Rect2(MARGIN, 70, 1500, 54), TopologyStyle.STAMP_FILL)
	draw_rect(Rect2(MARGIN, 70, 1500, 54), TopologyStyle.STAMP_INK, false, 3.0)
	TopologyStyle.text(self, Vector2(46, 78), TopologyModel.STAMP, 32, TopologyStyle.STAMP_INK)
	TopologyStyle.text(self, Vector2(MARGIN, 134), TopologyTexts.TRACE_NOTE, 22, TopologyStyle.INK_SOFT)
	var y := _draw_rows(170.0)
	_draw_questions(y + 14.0)


func _draw_rows(top: float) -> float:
	var y := top
	TopologyStyle.text(self, Vector2(MARGIN, y), "Hangi öğe kanon, hangisi çalışma modeli / çıkarım?", 26)
	y += 38.0
	var detail_w := DESIGN - 2.0 * MARGIN - CHIP_W - ITEM_W - REQ_W - 140.0
	for r in _rows:
		var item_h := TopologyStyle.paragraph(self, Vector2.ZERO, r["item"], ITEM_W, 23, TopologyStyle.INK, false)
		var detail_h := TopologyStyle.paragraph(self, Vector2.ZERO, r["detail"], detail_w, 21, TopologyStyle.INK, false)
		var h := maxf(maxf(item_h, detail_h), 28.0) + 12.0
		draw_rect(Rect2(MARGIN, y, DESIGN - 2.0 * MARGIN, h), Color(1, 1, 1, 0.8))
		draw_rect(Rect2(MARGIN, y, DESIGN - 2.0 * MARGIN, h), Color(0.8, 0.8, 0.78), false, 1.0)
		_chips(Vector2(MARGIN + 8.0, y + 6.0), String(r["status"]))
		var x := MARGIN + CHIP_W + 80.0
		TopologyStyle.paragraph(self, Vector2(x, y + 6.0), r["item"], ITEM_W, 23, TopologyStyle.INK)
		TopologyStyle.paragraph(self, Vector2(x + ITEM_W + 12.0, y + 6.0), r["detail"], detail_w, 21, TopologyStyle.INK_SOFT)
		TopologyStyle.text(self, Vector2(DESIGN - MARGIN - REQ_W, y + 6.0), r["req"], 18, TopologyStyle.INK_SOFT)
		y += h + 3.0
	return y


func _chips(pos: Vector2, status: String) -> void:
	var x := pos.x
	for st in status.split("/"):
		var col: Color = STATUS_COLORS.get(st, Color.GRAY)
		var w := TopologyStyle.text_size(st, 17).x + 14.0
		draw_rect(Rect2(x, pos.y, w, 24.0), col)
		TopologyStyle.text(self, Vector2(x + 7.0, pos.y + 2.0), st, 17, Color.WHITE)
		x += w + 6.0


func _draw_questions(top: float) -> void:
	var heading := "Kullanıcıya karar soruları (Q-015 alt maddeleri) — karar verilmedi, yalnız sunuluyor"
	TopologyStyle.text(self, Vector2(MARGIN, top), heading, 26)
	var y0 := top + 40.0
	var col_w := (DESIGN - 2.0 * MARGIN - 20.0) * 0.5
	var heights := PackedFloat32Array([0.0, 0.0])
	for i in _questions.size():
		var col := i % 2
		var q: Dictionary = _questions[i]
		var x := MARGIN + col * (col_w + 20.0)
		var y := y0 + heights[col]
		var body := "%s\n%s\nEtkisi: %s" % [q["current"], "\n".join(q["options"]), q["affects"]]
		var h := 40.0 + TopologyStyle.paragraph(self, Vector2.ZERO, body, col_w - 24.0, 22, TopologyStyle.INK, false) + 14.0
		TopologyStyle.panel(self, Rect2(x, y, col_w, h), Color(1.0, 0.99, 0.94), TopologyStyle.INK_SOFT, 1.5)
		TopologyStyle.text(self, Vector2(x + 12.0, y + 6.0), "%s · %s" % [q["id"], q["title"]], 28, TopologyStyle.STAMP_INK)
		TopologyStyle.paragraph(self, Vector2(x + 12.0, y + 42.0), body, col_w - 24.0, 22)
		heights[col] += h + 10.0
