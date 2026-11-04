extends SceneTree
## ui_lab düzen denetimi (T-019 ölçüt 5): ui_lab'ı pencereli açar, demo adımını uygular, sonra GERÇEK
## düğüm
## dikdörtgenlerinden ölçer: en küçük hedef, hedef altı sayısı, taşma, kırpılan metin, HUD kapladığı
## alan, harita merkezi görünürlüğü.
## Kullanım: tools/godot.sh --path . --resolution 1366x1024 --script res://scenes/dev/ui_lab_audit.gd -- \
##   --imaro-input-profile=touch --ui-lab-demo=zoning --ui-lab-safe=24,0,20,0
## Çıktı stdout'a `AUDIT ...` satırları olarak yazılır (dev aracı; oyun UI'ı değil).

const SAMPLES := 60


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var lab: Node = (load("res://scenes/dev/ui_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	for i in 12:
		await process_frame
	var hud: HudRoot = lab.hud
	var win := Vector2(root.size)
	var touch := hud.ctx.is_touch()
	var min_target := 44.0 if touch else 32.0
	var smallest := 1.0e9
	var smallest_text := ""
	var under := PackedStringArray()
	var outside := PackedStringArray()
	var clipped := PackedStringArray()
	var count := 0
	for b in _controls(hud, Button):
		var r := b.get_global_rect()
		count += 1
		var side := minf(r.size.x, r.size.y)
		if side < smallest:
			smallest = side
			smallest_text = b.text.replace("\n", " / ")
		if side + 0.01 < min_target:
			under.append("%s=%.0fx%.0f" % [b.text.replace("\n", " / "), r.size.x, r.size.y])
		if not Rect2(Vector2.ZERO, win).grow(1.0).encloses(r):
			outside.append("%s %s" % [b.text, r])
		if r.size.x + 1.0 < b.get_minimum_size().x:
			clipped.append("button '%s' %.0f<%.0f" % [b.text, r.size.x, b.get_minimum_size().x])
	for l in _controls(hud, Label):
		var lab_c := l as Label
		var r := lab_c.get_global_rect()
		if not Rect2(Vector2.ZERO, win).grow(1.0).encloses(r):
			outside.append("label '%s' %s" % [lab_c.text.left(30), r])
		if lab_c.autowrap_mode == TextServer.AUTOWRAP_OFF and r.size.x + 1.0 < lab_c.get_minimum_size().x:
			clipped.append("label '%s' %.0f<%.0f" % [lab_c.text.left(30), r.size.x, lab_c.get_minimum_size().x])
	var covered: Array[Rect2] = []
	for c: Control in [hud.top_bar, hud.toolbar]:
		covered.append(c.get_global_rect())
	if hud.banner.visible:
		covered.append(hud.banner.get_global_rect())
	if hud.is_panel_open():
		covered.append(hud.panel.get_global_rect())
	var center := Rect2(win * 0.25, win * 0.5)
	var visible := 0
	for ix in SAMPLES:
		for iy in SAMPLES:
			var p := center.position + Vector2((ix + 0.5) / SAMPLES * center.size.x, (iy + 0.5) / SAMPLES * center.size.y)
			var hit := false
			for r in covered:
				if r.has_point(p):
					hit = true
			if not hit:
				visible += 1
	var hud_area := 0.0
	for r in covered:
		hud_area += r.size.x * r.size.y
	print("AUDIT window=%s profile=%s scale=%.2f safe=%s" % [
		win, hud.ctx.profile_name, hud.ctx.ui_scale, hud.ctx.safe_insets])
	print("AUDIT buttons=%d smallest_side=%.1f ('%s') min_required=%.0f under=%d" % [
		count, smallest, smallest_text, min_target, under.size()])
	for u in under:
		print("AUDIT   under: ", u)
	print("AUDIT outside_window=%d clipped=%d" % [outside.size(), clipped.size()])
	for o in outside:
		print("AUDIT   outside: ", o)
	for c in clipped:
		print("AUDIT   clipped: ", c)
	print("AUDIT hud_area_fraction=%.3f center_visible=%.3f panel_open=%s" % [hud_area / (win.x * win.y),
		float(visible) / float(SAMPLES * SAMPLES), hud.is_panel_open()])
	if hud.is_panel_open():
		var pr := hud.panel.get_global_rect()
		print("AUDIT panel=%s width_frac=%.3f height_frac=%.3f" % [pr, pr.size.x / win.x, pr.size.y / win.y])
	quit()


func _controls(node: Node, type: Variant) -> Array[Control]:
	var out: Array[Control] = []
	for child in node.get_children():
		if is_instance_of(child, type) and (child as Control).is_visible_in_tree():
			out.append(child)
		out.append_array(_controls(child, type))
	return out
