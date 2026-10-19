class_name MayorHUD
extends CanvasLayer

signal parcel_requested(id: int)
signal camera_command(command: String)
signal weather_requested
signal save_requested
signal load_requested

const INK := Color("233b43")
const TEAL := Color("256b72")
var sim: CitySimulation
var clock: GameClock
var selected: int = 23
var current_tab: int = 0
var root := Control.new()
var cash_label: Label
var people_label: Label
var day_label: Label
var panel: PanelContainer
var title: Label
var detail: RichTextLabel
var forecast: RichTextLabel
var activity: RichTextLabel
var zones: OptionButton
var propose_button: Button
var policy_buttons: Array[Button] = []
var pages: Array[VBoxContainer] = []
var status: Label
var time_buttons: Array[Button] = []
var tabs: Array[Button] = []

static func money(value: int) -> String:
	var source := str(absi(value))
	var result := ""
	for i in range(source.length()):
		if i > 0 and (source.length() - i) % 3 == 0: result += "."
		result += source[i]
	return ("−" if value < 0 else "") + result + " ₺"

func style(color: Color, radius: int = 12, padding: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	return s

func _ready() -> void:
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	theme.set_color("default_color", "RichTextLabel", INK)
	for type in ["Button", "OptionButton"]:
		theme.set_color("font_color", type, INK)
		theme.set_color("font_hover_color", type, INK)
		theme.set_color("font_pressed_color", type, Color.WHITE)
		theme.set_stylebox("normal", type, style(Color("e6ebe6"), 9))
		theme.set_stylebox("hover", type, style(Color("d2e2dc"), 9))
		theme.set_stylebox("pressed", type, style(TEAL, 9))
		theme.set_stylebox("disabled", type, style(Color("ecece5"), 9))
		var focus_style := style(Color(0, 0, 0, 0), 9)
		focus_style.set_border_width_all(2)
		focus_style.border_color = TEAL
		theme.set_stylebox("focus", type, focus_style)
	theme.set_stylebox("panel", "PanelContainer", style(Color("f5f2e9"), 15, 18))
	theme.set_constant("separation", "VBoxContainer", 12)
	theme.set_constant("separation", "HBoxContainer", 12)
	root.theme = theme
	build_header()
	build_camera_controls()
	build_panel()
	build_dock()
	sim.changed.connect(refresh)
	refresh()

func label(parent: Node, text: String, size: int = 17) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l

func rich(parent: Node) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func button(parent: Node, text: String, callback: Callable, width: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	# 64 logical units remain >=44 screen units at the 1024-wide tablet fixture.
	b.custom_minimum_size = Vector2(maxi(width, 64), 64)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func build_header() -> void:
	var header := PanelContainer.new()
	root.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 18
	header.offset_right = -18
	header.offset_top = 16
	var row := HBoxContainer.new()
	header.add_child(row)
	var brand := VBoxContainer.new()
	brand.custom_minimum_size.x = 272
	brand.add_theme_constant_override("separation", 0)
	row.add_child(brand)
	label(brand, "Imaro: The Mayor", 24)
	label(brand, "Ilgın Belediyesi · Kıyı Mahallesi", 14)
	var finances := VBoxContainer.new()
	finances.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	finances.add_theme_constant_override("separation", 0)
	row.add_child(finances)
	cash_label = label(finances, "", 23)
	label(finances, "Belediye kasası", 13)
	var residents := VBoxContainer.new()
	residents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	residents.add_theme_constant_override("separation", 0)
	row.add_child(residents)
	people_label = label(residents, "", 22)
	label(residents, "Mahalle nüfusu", 13)
	day_label = label(row, "", 16)
	for speed in [0, 1, 4]:
		var b := button(row, "Ⅱ" if speed == 0 else str(speed) + "×", func(): set_speed(speed), 48)
		b.toggle_mode = true
		time_buttons.append(b)

func build_camera_controls() -> void:
	var controls := VBoxContainer.new()
	root.add_child(controls)
	controls.position = Vector2(20, 126)
	for item in [["+", "in", "Yakınlaş"], ["−", "out", "Uzaklaş"], ["↶", "left", "Sola döndür · Q"], ["↷", "right", "Sağa döndür · E"], ["⌂", "home", "Genel görünüm · Home"]]:
		var b := button(controls, item[0], func(): camera_command.emit(item[1]), 48)
		b.tooltip_text = item[2]
	button(controls, "Hava", func(): weather_requested.emit(), 48).tooltip_text = "Açık / bulutlu görünüm"

func build_panel() -> void:
	panel = PanelContainer.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -372
	panel.offset_right = -18
	panel.offset_top = 120
	panel.offset_bottom = -120
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	title = label(heading, "İmar", 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(heading, "×", func(): panel.hide(), 44)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	for i in range(4):
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(page)
		pages.append(page)
	detail = rich(pages[0])
	zones = OptionButton.new()
	zones.custom_minimum_size.y = 64
	for zone in ["housing", "mixed", "commerce", "green"]: zones.add_item(CityModel.ZONES[zone])
	zones.select(1)
	zones.item_selected.connect(func(_index: int): refresh())
	pages[0].add_child(zones)
	propose_button = button(pages[0], "Meclise sun · 1.000 ₺", propose)
	propose_button.add_theme_stylebox_override("normal", style(TEAL, 9))
	propose_button.add_theme_color_override("font_color", Color.WHITE)
	forecast = rich(pages[0])
	button(pages[0], "Seçili parsele yaklaş", func(): camera_command.emit("focus"))
	button(pages[0], "Eski atölyeyi incele · 20", func(): parcel_requested.emit(19))
	label(pages[1], "Mahalle için hizmetler", 21)
	var description := rich(pages[1])
	description.text = "Belediye hizmetleri yatırımın erişimini ve meclisteki desteği etkiler. Programların günlük gideri vardır."
	policy_buttons.append(button(pages[1], "", func(): show_status(sim.toggle_policy("mobility"))))
	policy_buttons.append(button(pages[1], "", func(): show_status(sim.toggle_policy("care"))))
	button(pages[1], "Oyunu kaydet", func(): save_requested.emit())
	button(pages[1], "Kaydı yükle", func(): load_requested.emit())
	rich(pages[2]).name = "Budget"
	rich(pages[3]).name = "Groups"
	activity = rich(pages[3])
	status = label(layout, "", 14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", TEAL)

func build_dock() -> void:
	var dock := PanelContainer.new()
	root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	dock.offset_left = 18
	dock.offset_top = -103
	dock.offset_bottom = -18
	var row := HBoxContainer.new()
	dock.add_child(row)
	for i in range(4):
		var b := button(row, ["İmar", "Belediye", "Bütçe", "Mahalle"][i], func(): open_tab(i), 116)
		b.toggle_mode = true
		tabs.append(b)
	var hint := label(root, "Sürükle: gezin   ·   Tekerlek / iki parmak: yakınlaş   ·   Q / E: döndür", 14)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 34
	hint.offset_top = -132
	hint.add_theme_color_override("font_color", Color("263f42"))

func set_speed(speed: int) -> void:
	clock.speed = speed
	refresh()

func open_tab(index: int) -> void:
	current_tab = index
	panel.show()
	refresh()

func select_parcel(id: int) -> void:
	selected = id
	open_tab(0)

func chosen_zone() -> String:
	return ["housing", "mixed", "commerce", "green"][zones.selected]

func propose() -> void:
	show_status(sim.propose(selected, chosen_zone()))

func show_status(message: String) -> void:
	status.text = message
	refresh()

func refresh() -> void:
	if not is_instance_valid(cash_label): return
	var total := sim.totals()
	cash_label.text = money(sim.municipality.cash)
	people_label.text = "%d kişi" % total.population
	day_label.text = "%d. gün\n%s" % [sim.day + 1, "Duraklatıldı" if clock.speed == 0 else "Zaman akıyor"]
	for i in range(3): time_buttons[i].set_pressed_no_signal(clock.speed == [0, 1, 4][i])
	for i in range(4):
		pages[i].visible = i == current_tab
		tabs[i].set_pressed_no_signal(i == current_tab and panel.visible)
	title.text = ["İmar", "Belediye", "Bütçe", "Mahalle"][current_tab]
	if selected >= 0:
		var p := sim.parcels[selected]
		var use_text: String = {"empty": "Boş arsa", "apartment": "Kullanımda", "construction": "Şantiye", "park": "Mahalle parkı", "service": "Mahalle evi"}.get(p.use, p.use)
		detail.text = "[b]PARSEL %02d · %s[/b]\n%s\n\nİmar: %s\nArazi: %s  ·  Erişim: %%%d\nKonut: %d  ·  Dolu: %d  ·  İşyeri: %d" % [p.id + 1, use_text, sim.owner_title(p), CityModel.ZONES[p.zone], money(p.land_value), roundi(sim.effective_access(p) * 100), p.homes, p.occupied, p.shops]
		propose_button.disabled = p.use != "empty" or sim.pending_for(p.id) or p.zone == chosen_zone() or sim.municipality.cash < 1000
		if sim.pending_for(p.id):
			forecast.text = "[b]Meclis gündeminde[/b]\nKarar 2 gün içinde görüşülür. Zamanı ilerletin; kabul edilirse yatırımcılar ayrı değerlendirme yapar."
		elif p.use == "construction":
			for d in sim.developments:
				if d.parcel_id == p.id:
					forecast.text = "[b]Özel yatırım sürüyor[/b]\n%s\n%d / %d gün\nYatırım: %s\n\nKonut ve vergi kapasitesi inşaat tamamlandığında değişecek." % [sim.investors[d.investor_id].title, sim.day - d.started_day, d.duration, money(d.cost)]
		elif p.use == "empty":
			var vote := sim.council_vote(p.id, chosen_zone())
			forecast.text = "[b]Meclis öngörüsü · %d/7 destek[/b]\n%s\n\n" % [vote.yes, "\n".join(vote.rows)]
			if chosen_zone() == "green":
				forecast.text += "Özel arazi açık alan olarak korunur. Bu karar park inşa etmez; mülkiyet değişmez."
			else:
				forecast.text += "[b]Yatırım fizibilitesi · tahmin[/b]\n"
				for investor in sim.investors:
					var result := sim.evaluate(p, investor, chosen_zone())
					forecast.text += "\n[b]%s[/b]\n%s\n" % [investor.title, result.reason]
					if result.cost > 0:
						forecast.text += "Arazi %s + yapım %s + temizlik %s\nBeklenen gelir %s\n" % [money(result.land), money(result.build), money(result.cleanup), money(result.revenue)]
				forecast.text += "\nSon değerlendirme: " + p.last_evaluation
		else:
			forecast.text = "Mevcut kullanım korunuyor. Yeni imar teklifi için boş bir özel parsel seçin."
	else:
		detail.text = "Bir parsel seçin."
		propose_button.disabled = true
		forecast.text = ""
	policy_buttons[0].text = "Ulaşım desteğini durdur" if sim.municipality.mobility else "Ulaşım · 30.000 ₺ + 450 ₺/gün"
	policy_buttons[1].text = "Bakım programını durdur" if sim.municipality.care else "Bakım · 18.000 ₺ + 250 ₺/gün"
	var flow := sim.forecast_budget()
	var budget: RichTextLabel = pages[2].get_node("Budget")
	budget.text = "[b]Belediye kasası[/b]\n%s\n\n[b]Günlük bütçe · mevcut kapasite[/b]\nGelir: %s\nHizmet gideri: %s\nNet: %s\n\n%d konut · %d dolu\n%d işyeri\n\nGelir: 1.400 ₺ pay + dolu konut başına 6 ₺ + işyeri başına 90 ₺.\nGider: 2.100 ₺ temel hizmet + kişi başına 1 ₺ + açık programlar.\n\n[b]Son işlemler[/b]\n" % [money(sim.municipality.cash), money(flow.income), money(flow.expense), money(flow.income - flow.expense), total.homes, total.occupied, total.shops]
	for entry in sim.municipality.ledger.slice(maxi(0, sim.municipality.ledger.size() - 6)):
		budget.text += "%d. gün · %s\n%s\n\n" % [entry.day + 1, money(entry.amount), entry.reason]
	var group_text: RichTextLabel = pages[3].get_node("Groups")
	group_text.text = ""
	for group in sim.groups:
		group_text.text += "[b]%s · destek %%%d[/b]\n%s\n\n" % [group.title, group.support, group.reason]
	activity.text = "[b]Mahalle günlüğü[/b]\n"
	for event in sim.events.slice(maxi(0, sim.events.size() - 5)):
		activity.text += "\n%d. gün · [b]%s[/b]\n%s\n" % [event.day + 1, event.title, event.detail]
