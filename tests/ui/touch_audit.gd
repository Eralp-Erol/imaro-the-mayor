class_name TouchAudit
extends RefCounted
## tests/ui ortak yardımcı (test paketi değildir): bir panel ağacının GERÇEK yerleşim ölçümü.
## Dokunmatik denetimi:
## dar yuvada yatay taşma, kesilen düğme/etiket, hedef boyutu. Ölçüler `Control` boyutlarından/asgari
## boyutlarından gelir (başsız yerleşim); gerçek parmak/cihaz denemesi DEĞİLDİR.

## Panel yuvasının (kaydırma kabı) iç genişliği `avail` iken ihlallerin listesi (boş = temiz).
static func violations(root: Control, avail: float, min_target: float) -> PackedStringArray:
	var out := PackedStringArray()
	var need := root.get_combined_minimum_size().x
	if need > avail + 0.5:
		out.append("panel asgari genişliği %.0f > yuva %.0f" % [need, avail])
	_walk(root, root, avail, min_target, out)
	return out


static func _walk(node: Node, root: Control, avail: float, min_target: float, out: PackedStringArray) -> void:
	for child in node.get_children():
		var c := child as Control
		if c != null and not c.visible:
			continue
		if c != null:
			_check(c, root, avail, min_target, out)
		_walk(child, root, avail, min_target, out)


static func _check(c: Control, root: Control, avail: float, min_target: float, out: PackedStringArray) -> void:
	var rect := Rect2(c.get_global_rect().position - root.get_global_rect().position, c.size)
	if rect.size.x > 0.0 and rect.end.x > avail + 1.0:
		out.append("%s taştı: sağ kenar %.0f > %.0f" % [_name(c), rect.end.x, avail])
	var mn := c.get_combined_minimum_size()
	if c is Button:
		var b := c as Button
		var hit := UiFactory.hit_size(b)
		if minf(hit.x, hit.y) < min_target:
			out.append("düğme '%s' hedefi %s < %.0f" % [b.text, hit, min_target])
		if b.size.x + 1.0 < mn.x or b.size.y + 1.0 < mn.y:
			out.append("düğme '%s' kesik: boyut %s < asgari %s" % [b.text, b.size, mn])
	elif c is Label:
		var l := c as Label
		if not l.text.is_empty() and (l.size.y + 1.0 < mn.y or l.size.x + 1.0 < mn.x and
				l.autowrap_mode == TextServer.AUTOWRAP_OFF):
			out.append("etiket '%s' kesik: boyut %s < asgari %s" % [l.text, l.size, mn])


static func _name(c: Control) -> String:
	if c is Label:
		return "etiket '%s'" % (c as Label).text
	if c is Button:
		return "düğme '%s'" % (c as Button).text
	return c.get_class()


## Görünür düğmeler arasındaki en küçük boşluk (px); çakışma varsa negatif. Yan yana yanlış dokunmayı ölçer.
static func min_button_gap(root: Control) -> float:
	var rects: Array[Rect2] = []
	_button_rects(root, rects)
	var best := INF
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a := rects[i]
			var b := rects[j]
			var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
			var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
			var overlap := a.intersects(b)
			best = minf(best, -1.0 if overlap else maxf(dx, dy))
	return best


static func _button_rects(node: Node, out: Array[Rect2]) -> void:
	for child in node.get_children():
		var c := child as Control
		if c != null and not c.visible:
			continue
		if child is Button:
			out.append((child as Button).get_global_rect())
		_button_rects(child, out)
