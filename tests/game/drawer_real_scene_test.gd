extends GdUnitTestSuite
## Bağımsız QA (D-021 iPad çekmecesi) · GERÇEK `playable.tscn` (gerçek SimFacade, gerçek Ismeral dünyası + T0),
## dokunmatik profil (`PlatformProfile.set_current` = touch). Önceki kanıt yalnız ui_lab/MOCK facade + birim
## testleriydi. Burada:
## yol çizimi çekmecesi + kamulaştırma onayı açıkken harita dokunuşu (gerçek
## `InputEventScreenTouch`), çekmecenin haritayı
## örtme payı, gündem/sonuç/politika/imar/meclis(+bütçe) çekmeceleri gerçek akışta, B-081 şerit satırı.
## `Viewport.push_input` sentetiktir: gerçek parmak/iPad DEĞİL; düğmeler fare tıklamasıyla basılır (Godot dokunmayı
## fareye ## çevirdiği için). Pencereli kareler: `tools/godot/drawer_real_probe.gd` (`artifacts/qa/drawer-gercek/`).
##
## AÇIK HATALAR bu dosyada KARAKTERİZASYON testiyle sabitlenir (`test_B12x_open_defect_...`): hata DÜZELTİLİNCE o test
## kırılır ve iddiası ters çevrilmelidir (kayıt: production/bugs/B-120..B-12x.md). Ürün kodu bu görevde değişmedi.
## Sahne kurulumu ~1 dk (başsız); sahne paylaşılır, testler yol akışı sonrası durumu kullanır (`_ensure_flow`).

const Support := preload("res://tests/game/expropriation_game_support.gd")
const SCENE := "res://scenes/game/playable.tscn"
const LANDSCAPE := Vector2i(1024, 768)
const PORTRAIT := Vector2i(768, 1024)
## Çekmece YARI iken harita boşluğu pencere alanının en az bu oranı (D-021 testleriyle aynı eşik; gerçekte ~%29-32).
const MIN_FREE_FRAC := 0.24
const MAX_TRUST_DAYS := 40

var _scene: Node = null
var _flow_done: bool = false
var _cand: Dictionary = {}


func before() -> void:
	UiText.reset()
	UiText.report_missing = false
	PlatformProfile.set_current(PlatformProfile.from_tags(PackedStringArray(), {"input_profile": &"touch"}))


func after() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	PlatformProfile.reset_current()
	UiText.reset()


# --- yardımcılar -----------------------------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _settle() -> void:
	var frames := 0
	while frames < 900:
		await get_tree().process_frame
		frames += 1
		if frames > 3 and not _scene._pr.follow.busy() and not _scene._pr.sync.world_busy():
			break


func _hud() -> HudRoot:
	return _scene._hud


func _facade() -> SimFacadeImpl:
	return _scene._facade as SimFacadeImpl


func _screen(world_xz: Vector2) -> Vector2:
	return Support.screen_of(_scene, world_xz)


func _push(e: InputEvent) -> void:
	get_viewport().push_input(e)


## Gerçek dokunuş (parmak): ScreenTouch basma + bırakma.
func _tap(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.pressed = pressed
		e.position = pos
		_push(e)
		await get_tree().process_frame


## Düğmeler: Godot dokunmayı fare tıklamasına çevirir; test fare olayıyla basar.
func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		_push(e)
		await get_tree().process_frame


func _touch_drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = from
	_push(down)
	await get_tree().process_frame
	for k in 6:
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = from.lerp(to, float(k + 1) / 6.0)
		d.relative = (to - from) / 6.0
		_push(d)
		await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = to
	_push(up)
	await get_tree().process_frame


func _set_window(size: Vector2i) -> void:
	get_window().size = size
	await _frames(6)


func _free_frac(hud: HudRoot, win: Vector2) -> float:
	return hud.free_map_rect().get_area() / (win.x * win.y)


## Odağı, `mid` serbest harita dikdörtgeninin ortasına düşecek biçimde kaydırır (oyuncunun kaydırması).
func _recenter_in_free_map(mid: Vector2) -> void:
	var cam: CameraRig = _scene._camera
	var want := _hud().free_map_rect().get_center()
	for _it in 3:
		var st := cam.target_state()
		var s0 := _screen(mid)
		st.focus_x += 20.0
		cam.apply_state(st, true)
		await _frames(1)
		var sx := (_screen(mid) - s0) / 20.0
		st.focus_x -= 20.0
		st.focus_z += 20.0
		cam.apply_state(st, true)
		await _frames(1)
		var sz := (_screen(mid) - s0) / 20.0
		st.focus_z -= 20.0
		cam.apply_state(st, true)
		await _frames(1)
		var d := want - s0
		var det := sx.x * sz.y - sz.x * sx.y
		if absf(det) < 0.0001:
			return
		st = cam.target_state()
		st.focus_x += (d.x * sz.y - sz.x * d.y) / det
		st.focus_z += (sx.x * d.y - d.x * sx.y) / det
		cam.apply_state(st, true)
		await _frames(3)


func _button(text: String) -> Button:
	return Support.find_button(_hud(), text)


## Düğme çekmece panelinin içinde (kaydırma altında/dışında değil) ve pencerede mi.
func _reachable(btn: Button, win: Vector2) -> bool:
	if btn == null or not btn.is_visible_in_tree():
		return false
	var r := btn.get_global_rect()
	return _hud().panel.get_global_rect().grow(1.0).encloses(r) and Rect2(Vector2.ZERO, win).encloses(r)


func _scroll_of(node: Node) -> ScrollContainer:
	if node is ScrollContainer and (node as ScrollContainer).is_visible_in_tree():
		return node
	for c in node.get_children():
		var s := _scroll_of(c)
		if s != null:
			return s
	return null


func _ensure_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		return
	await _set_window(LANDSCAPE)
	_scene = (load(SCENE) as PackedScene).instantiate()
	add_child(_scene)
	await _frames(3)
	var f := _facade()
	assert_object(f).is_not_null()
	f.set_speed(SimFacade.SPEED_PAUSED)
	f.advance(2)   # ilk tick ekonomi durumunu kurar
	await _frames(20)
	_cand = Support.find_candidate(_scene, f)
	assert_bool(_cand.is_empty()).override_failure_message("aday yol bulunamadı").is_false()


## Yol çiz -> iki dokunuş -> Kamulaştırarak geç -> Yıkımı onayla -> tick (ortak durum; iddialar akış testinde).
func _ensure_flow() -> void:
	await _ensure_scene()
	if _flow_done:
		return
	_flow_done = true
	var hud := _hud()
	var a: Vector2 = _cand["a"]
	var b: Vector2 = _cand["b"]
	var cam: CameraRig = _scene._camera
	var st := cam.target_state()
	st.focus_x = (a.x + b.x) * 0.5
	st.focus_z = (a.y + b.y) * 0.5
	st.distance = 230.0
	cam.apply_state(st, true)
	await _frames(6)
	var btn := hud.toolbar.tool_button(ModeToolbar.TOOL_ROAD_DRAW)
	assert_object(btn).override_failure_message("gerçek sahnede 'Yol çiz' düğmesi yok").is_not_null()
	await _click(btn.get_global_rect().get_center())
	await _frames(6)
	await _recenter_in_free_map((a + b) * 0.5)
	var tool: RoadDrawTool = _scene._pr.ctrl.tool
	await _tap(_screen(a))
	await _tap(_screen(b))
	await _frames(4)
	await _click(_button(UiText.t(&"expropriation.accept")).get_global_rect().get_center())
	await _frames(4)
	await _click(_button(UiText.t(&"expropriation.confirm")).get_global_rect().get_center())
	_facade().advance(1)
	await _settle()
	assert_int(tool.step).is_equal(RoadDrawTool.Step.PICK_A)


# --- 1) yol çizimi çekmecesi + kamulaştırma onayı açıkken harita dokunuşu (gerçek sahne) -----------------------

func test_road_drawer_and_expropriation_card_keep_map_taps_working_on_the_real_scene() -> void:
	await _ensure_scene()
	_flow_done = true
	var hud := _hud()
	var win := Vector2(get_window().size)
	var ctrl: RoadDrawController = _scene._pr.ctrl
	var tool: RoadDrawTool = ctrl.tool
	var f := _facade()
	var a: Vector2 = _cand["a"]
	var b: Vector2 = _cand["b"]
	assert_bool(hud.ctx.is_touch()).override_failure_message("gerçek sahne dokunmatik profilde değil").is_true()
	var cam: CameraRig = _scene._camera
	var st := cam.target_state()
	st.focus_x = (a.x + b.x) * 0.5
	st.focus_z = (a.y + b.y) * 0.5
	st.distance = 230.0
	cam.apply_state(st, true)
	await _frames(6)
	var selected_before: int = _scene._selected_parcel_id

	# araç çubuğundaki gerçek düğme -> çekmece
	var btn := hud.toolbar.tool_button(ModeToolbar.TOOL_ROAD_DRAW)
	assert_object(btn).override_failure_message("gerçek sahnede 'Yol çiz' düğmesi yok").is_not_null()
	assert_float(btn.get_global_rect().size.y).is_greater_equal(44.0)
	await _click(btn.get_global_rect().get_center())
	await _frames(6)
	assert_bool(ctrl.is_active()).is_true()
	assert_bool(hud.is_drawer_active()).override_failure_message("yol paneli çekmece değil").is_true()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.HALF)
	assert_float(_free_frac(hud, win)).override_failure_message(
			"çekmece YARI haritanın fazlasını örtüyor: boşluk %.2f" % _free_frac(hud, win)).is_greater(MIN_FREE_FRAC)
	assert_float(hud.free_map_rect().size.x).is_equal(win.x)   # şehir yandan örtülmez
	await _recenter_in_free_map((a + b) * 0.5)
	var sa := _screen(a)
	var sb := _screen(b)
	assert_bool(hud.free_map_rect().has_point(sa)).override_failure_message("A harita boşluğunda değil").is_true()
	assert_bool(hud.free_map_rect().has_point(sb)).override_failure_message("B harita boşluğunda değil").is_true()

	# gerçek dokunuşlar: A, B -> inceleme + kamulaştırma teklifi
	await _tap(sa)
	assert_int(tool.step).is_equal(RoadDrawTool.Step.PICK_B)
	await _tap(sb)
	await _frames(4)
	assert_int(tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	assert_bool(tool.offer().is_empty()).override_failure_message("kamulaştırma teklifi yok").is_false()
	assert_int(_scene._selected_parcel_id).override_failure_message("araç açıkken parsel seçilmemeli") \
			.is_equal(selected_before)
	var accept := _button(UiText.t(&"expropriation.accept"))
	assert_bool(_reachable(accept, win)).override_failure_message(
			"'Kamulaştırarak geç' YARI çekmecede kaydırmasız erişilemiyor").is_true()
	assert_float(accept.get_global_rect().size.y).is_greater_equal(44.0)

	# harita dokunuşu çekmece AÇIKKEN çalışır: bitiş kayar (olumlu)
	var end_before := tool.end
	var b2 := b + (b - a).normalized().orthogonal() * 12.0
	await _tap(_screen(b2))
	await _frames(3)
	assert_float(tool.end.distance_to(end_before)).override_failure_message(
			"çekmece açıkken harita dokunuşu bitişi taşımadı").is_greater(0.5)
	assert_int(tool.step).is_equal(RoadDrawTool.Step.REVIEW)

	# çekmece GÖVDESİNE dokunuş/sürükleme dünyaya sızmaz (olumsuz)
	var end_mid := tool.end
	var focus_before := cam.target_state()
	var panel_c := hud.panel.get_global_rect().get_center()
	await _tap(panel_c)
	await _touch_drag(panel_c, panel_c + Vector2(-120.0, -40.0))
	await _frames(3)
	assert_float(tool.end.distance_to(end_mid)).override_failure_message("çekmece dokunuşu dünyaya sızdı").is_less(0.01)
	assert_int(tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	assert_float(Vector2(cam.target_state().focus_x - focus_before.focus_x,
			cam.target_state().focus_z - focus_before.focus_z).length()) \
			.override_failure_message("çekmece üstünde sürükleme kamerayı kaydırdı").is_less(0.01)

	# bitişi geri al, kamulaştırmayı kabul et -> onay kartı
	await _tap(sb)
	await _frames(3)
	assert_int(tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	accept = _button(UiText.t(&"expropriation.accept"))
	await _click(accept.get_global_rect().get_center())
	await _frames(6)
	assert_bool(tool.expropriate and tool.demolishes()).is_true()
	assert_int(f.public_works().size()).override_failure_message("onaydan önce komut gönderildi").is_equal(0)
	var confirm := _button(UiText.t(&"expropriation.confirm"))
	assert_bool(_reachable(confirm, win)).override_failure_message(
			"'Yıkımı onayla' YARI çekmecede kaydırmasız erişilemiyor").is_true()
	assert_float(confirm.get_global_rect().size.y).is_greater_equal(44.0)

	# B-121 KARAKTERİZASYON: onay kartında imleç ipucu ile onay işareti (chip) üst üste biniyor
	assert_bool(ctrl.tip.visible and ctrl.chip.visible).override_failure_message("ipucu/işaret görünür olmalı").is_true()
	var tip_rect := Rect2(ctrl.tip.position, ctrl.tip.size)
	assert_bool(tip_rect.intersects(ctrl.chip.get_global_rect())).override_failure_message(
			"B-121 DÜZELTİLMİŞ GÖRÜNÜYOR: bu karakterizasyon iddiasını ters çevirin (tip %s chip %s)" % [
			str(tip_rect), str(ctrl.chip.get_global_rect())]).is_true()

	# onay kartı açıkken harita dokunuşu bitişi taşır ve kabulü SIFIRLAR (yeni teklif, yeniden kabul)
	await _tap(_screen(b2))
	await _frames(4)
	assert_bool(tool.expropriate).override_failure_message("bitiş değişti ama kamulaştırma kabulü sürüyor").is_false()
	await _tap(sb)
	await _frames(3)
	accept = _button(UiText.t(&"expropriation.accept"))
	assert_object(accept).is_not_null()
	await _click(accept.get_global_rect().get_center())
	await _frames(4)
	confirm = _button(UiText.t(&"expropriation.confirm"))
	assert_object(confirm).is_not_null()
	await _click(confirm.get_global_rect().get_center())
	assert_int(tool.step).is_equal(RoadDrawTool.Step.SENDING)
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(1)
	await _settle()
	assert_int(tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	assert_bool(hud.is_drawer_active()).is_true()
	assert_float(_free_frac(hud, win)).is_greater(MIN_FREE_FRAC)


# --- 4) B-081 şerit satırı: yıkımdan sonra gerçek sim'de ----------------------------------------------------

func test_trust_notice_after_demolition_is_real_but_hidden_by_the_strip_b120_and_wraps_cleanly_alone() -> void:
	await _ensure_flow()
	var hud := _hud()
	var f := _facade()
	var strip: NotificationStrip = hud.strip
	var members := 0
	for day in MAX_TRUST_DAYS:
		hud.refresh()
		members = CouncilTrustNotice.affected_members(f)
		if members > 0:
			break
		f.advance(1)
		await _frames(2)
	# Sim gerçeği: yıkım meclis üyelerinin güvenini düşürdü ve neden kaydı var (B-081 sim tarafı).
	assert_int(members).override_failure_message("yıkımdan sonra güven kesintisi kaydı yok").is_greater(0)
	assert_str(strip.trust_text()).is_equal(UiText.t(&"strip.council_trust_drop", {"n": members}))
	assert_str(strip.trust_text()).contains("Meclis güveni düştü: yıkım kararı")
	var trust_row := strip.get("_trust_row") as Control
	assert_object(trust_row).override_failure_message("satır düğümü kurulmamış").is_not_null()
	await _frames(4)
	# B-120 KARAKTERİZASYON: şerit diğer satırlarla doluyken (yol yapıldı, tepki bekleniyor, plansız parsel...) güven
	# satırı en düşük öncelikte olduğundan GİZLENİR; oyuncu B-081 gerekçesini hiç görmez.
	var others := 0
	for row in strip.get_children():
		if row != trust_row and (row as Control).visible:
			others += 1
	assert_int(others).override_failure_message("kurulum: şeritte başka satır yok").is_greater(0)
	assert_bool(trust_row.visible).override_failure_message(
			"B-120 DÜZELTİLMİŞ GÖRÜNÜYOR: bu karakterizasyon iddiasını ters çevirin").is_false()

	# Tek başına (şerit temizlenince) satır görünür, <= 3 satıra sarar ve çekmece açıkken de sığar (iki yönde).
	for size: Vector2i in [LANDSCAPE, PORTRAIT]:
		await _set_window(size)
		strip.clear()
		await _frames(4)
		var row := strip.get("_trust_row") as Control
		assert_bool(row != null and row.visible).override_failure_message("tek başına satır görünmüyor").is_true()
		var label := row.get_child(0) as Label
		assert_int(label.get_line_count()) \
				.override_failure_message("dar ekranda %d satıra sarıyor" % label.get_line_count()).is_less_equal(3)
		assert_float(row.get_global_rect().end.x).is_less_equal(float(size.x))
		(_scene._pr.ctrl as RoadDrawController).activate()   # çekmece YARI açık: şerit alanı küçülür
		await _frames(6)
		row = strip.get("_trust_row") as Control
		assert_bool(row.visible).override_failure_message("çekmece açıkken tek başına satır sığmıyor").is_true()
		assert_float(row.get_global_rect().end.y).is_less_equal(hud.panel.get_global_rect().position.y + 0.5)
		(_scene._pr.ctrl as RoadDrawController).deactivate()
		await _frames(4)
	await _set_window(LANDSCAPE)


# --- 2) gündem / sonuç / politika / imar / meclis çekmeceleri gerçek akışta -------------------------------------------

func _assert_drawer_ok(tag: String, win: Vector2) -> void:
	var hud := _hud()
	assert_bool(hud.is_drawer_active()).override_failure_message("%s: çekmece değil" % tag).is_true()
	assert_int(hud.drawer_state).override_failure_message("%s: YARI açılmadı" % tag).is_equal(DrawerModel.State.HALF)
	var pr := hud.panel.get_global_rect()
	assert_bool(Rect2(Vector2.ZERO, win).encloses(pr)) \
			.override_failure_message("%s: pencere dışı %s" % [tag, str(pr)]).is_true()
	assert_float(pr.end.y).override_failure_message("%s: araç çubuğunu örtüyor" % tag) \
			.is_less_equal(hud.toolbar.get_global_rect().position.y + 1.0)
	assert_float(_free_frac(hud, win)).override_failure_message(
			"%s: harita boşluğu %.2f" % [tag, _free_frac(hud, win)]).is_greater(MIN_FREE_FRAC)
	assert_float(hud.free_map_rect().end.y).is_less_equal(pr.position.y + 0.5)
	for state in [DrawerModel.State.CLOSED, DrawerModel.State.FULL, DrawerModel.State.HALF]:
		hud.set_drawer_state(state)
		await _frames(3)
		assert_bool(Rect2(Vector2.ZERO, win).encloses(hud.panel.get_global_rect())).override_failure_message(
				"%s: durum %d pencere dışı" % [tag, state]).is_true()
	assert_float(hud.free_map_rect().size.y).is_greater(win.y * MIN_FREE_FRAC)


func _open_agenda_and_check(win: Vector2) -> void:
	var hud := _hud()
	assert_bool(hud.top_bar.agenda.visible).override_failure_message("gündem rozeti görünmüyor").is_true()
	hud.agenda_requested.emit()
	await _frames(8)
	assert_str(String(hud.panel_id())).is_equal("agenda")
	await _assert_drawer_ok("gündem", win)
	# Birincil eylem ("Bu yanıtı ver") YARI'da kaydırma altında: kaydırınca erişilir (olumlu erişilebilirlik).
	var answer_text := UiText.t(&"agenda.choose")
	var scroll := _scroll_of(hud.panel)
	assert_object(scroll).override_failure_message("gündem paneli kaydırılabilir değil").is_not_null()
	var found: Button = null
	for pos in 12:
		for c in _all_buttons(hud.panel):
			if c.text == answer_text and _reachable(c, win):
				found = c
		if found != null:
			break
		scroll.scroll_vertical += 120
		await _frames(2)
	assert_object(found).override_failure_message("'%s' kaydırarak bile erişilemiyor" % answer_text).is_not_null()
	assert_float(found.get_global_rect().size.y).is_greater_equal(44.0)
	scroll.scroll_vertical = 0


func _all_buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	if n is Button and (n as Button).is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_buttons(c))
	return out


func test_agenda_results_policy_zoning_and_council_drawers_on_the_real_scene_landscape() -> void:
	await _ensure_flow()
	await _set_window(LANDSCAPE)
	var hud := _hud()
	var win := Vector2(get_window().size)
	await _open_agenda_and_check(win)
	# Sonuç paneli (gerçek araç düğmesi)
	hud.toolbar.select_mode(ModeToolbar.MODE_PLAN)
	await _frames(2)
	var results := hud.toolbar.tool_button(ModeToolbar.TOOL_RESULTS)
	assert_object(results).override_failure_message("gerçek sahnede 'Döngü sonucu' düğmesi yok").is_not_null()
	await _click(results.get_global_rect().get_center())
	await _frames(8)
	assert_str(String(hud.panel_id())).is_equal("m2_results")
	await _assert_drawer_ok("sonuç", win)
	# Politikalar (Yönetim modunda)
	hud.toolbar.select_mode(ModeToolbar.MODE_MANAGE)
	await _frames(2)
	var policy := hud.toolbar.tool_button(ModeToolbar.TOOL_POLICY)
	assert_object(policy).is_not_null()
	await _click(policy.get_global_rect().get_center())
	await _frames(8)
	assert_str(String(hud.panel_id())).is_equal("policy")
	await _assert_drawer_ok("politika", win)
	assert_bool(_reachable(_button(UiText.t(&"policy.resettlement.turn_on")), win)).override_failure_message(
			"'Yeniden iskânı aç' YARI çekmecede erişilemiyor").is_true()
	# Programatik: meclis ve bütçe (gerçek sahnede araç çubuğunda kayıtlı DEĞİL, bkz. B-124)
	_scene._decisions.open_council()
	await _frames(8)
	assert_str(String(hud.panel_id())).is_equal("council")
	await _assert_drawer_ok("meclis (programatik)", win)
	_scene._decisions.open_budget()
	await _frames(8)
	assert_str(String(hud.panel_id())).is_equal("budget")
	await _assert_drawer_ok("bütçe (programatik)", win)
	hud.close_panel_hard()
	await _frames(3)


func _mouse_drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	_push(down)
	var pos := from
	for _i in 12:
		var m := InputEventMouseMotion.new()
		var step := (to - from) / 12.0
		pos += step
		m.position = pos
		m.global_position = pos
		m.relative = step
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		_push(m)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	_push(up)
	await get_tree().process_frame


func test_grip_drag_and_arrow_buttons_move_the_real_drawer_and_closed_state_returns_the_map() -> void:
	await _ensure_flow()
	await _set_window(LANDSCAPE)
	var hud := _hud()
	var win := Vector2(get_window().size)
	var net: WorldNetwork = _scene._net
	hud.close_panel_hard()
	await _frames(3)
	hud.agenda_requested.emit()
	await _frames(8)
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.HALF)
	# parmakla tutamaç sürükleme (Godot dokunmayı fareye çevirir) -> TAM
	var grip := hud.panel.grip.get_global_rect().get_center()
	await _mouse_drag(grip, grip + Vector2(0.0, -480.0))
	await _frames(4)
	assert_int(hud.drawer_state).override_failure_message("tutamaç sürükleme TAM'a götürmedi") \
			.is_equal(DrawerModel.State.FULL)
	assert_float(hud.free_map_rect().size.y).is_less(win.y * 0.2)
	# gerçek ok düğmeleri: TAM -> YARI -> KAPALI
	var down := _button(UiText.t(&"panel.drawer_down"))
	assert_bool(_reachable(down, win)).override_failure_message("'Aşağı it' düğmesi erişilemiyor").is_true()
	assert_float(down.get_global_rect().size.y).is_greater_equal(44.0)
	await _click(down.get_global_rect().get_center())
	await _frames(4)
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.HALF)
	await _click(_button(UiText.t(&"panel.drawer_down")).get_global_rect().get_center())
	await _frames(4)
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.CLOSED)
	assert_float(hud.free_map_rect().size.y).override_failure_message("KAPALI çekmece haritayı geri vermiyor") \
			.is_greater(win.y * 0.55)
	# KAPALI çekmecede harita dokunuşu parsel seçer (gerçek dokunuş)
	var cam: CameraRig = _scene._camera
	var focus := cam.focus_xz()
	var best := -1
	var best_d := INF
	for pid: int in net.parcels:
		var c: Vector2 = net.parcels[pid].centroid
		var sc := _screen(c)
		var d := c.distance_to(focus)
		if d < best_d and net.parcel_id_at(c.x, c.y) == pid and hud.free_map_rect().grow(-30.0).has_point(sc):
			best_d = d
			best = pid
	assert_int(best).override_failure_message("serbest haritada seçilecek parsel yok").is_greater(0)
	var c0: Vector2 = net.parcels[best].centroid
	await _tap(_screen(c0))
	await _frames(4)
	assert_int(_scene._selected_parcel_id).override_failure_message(
			"KAPALI çekmece açıkken harita dokunuşu parsel seçmedi").is_equal(best)
	hud.close_panel_hard()
	await _frames(3)


func test_b124_open_gap_real_scene_does_not_register_council_budget_agenda_tools() -> void:
	await _ensure_scene()
	var hud := _hud()
	hud.toolbar.select_mode(ModeToolbar.MODE_MANAGE)
	await _frames(2)
	# KARAKTERİZASYON: DecisionPanels.attach(..., with_manage_tools=false) -> meclis/bütçe/gündem araçları yok; oyuncu
	# meclis çekmecesine yalnız gündem rozetinden ve gerekçe bağlantılarından dolaylı ulaşır.
	for tid in [ModeToolbar.TOOL_COUNCIL, ModeToolbar.TOOL_BUDGET, ModeToolbar.TOOL_AGENDA]:
		assert_object(hud.toolbar.tool_button(tid)).override_failure_message(
				"B-124 DÜZELTİLMİŞ GÖRÜNÜYOR (%s kayıtlı): bu karakterizasyonu ters çevirin" % String(tid)).is_null()
	assert_object(hud.toolbar.tool_button(ModeToolbar.TOOL_POLICY)).is_not_null()


func test_zoning_drawer_big_plan_goes_to_the_council_with_real_touch_taps() -> void:
	await _ensure_flow()
	await _set_window(LANDSCAPE)
	var hud := _hud()
	var win := Vector2(get_window().size)
	var f := _facade()
	var net: WorldNetwork = _scene._net
	var a: Vector2 = _cand["a"]
	var b: Vector2 = _cand["b"]
	hud.close_panel_hard()
	await _frames(3)
	hud.toolbar.select_mode(ModeToolbar.MODE_PLAN)
	await _frames(2)
	var zone := hud.toolbar.tool_button(ModeToolbar.TOOL_ZONE)
	assert_object(zone).is_not_null()
	await _click(zone.get_global_rect().get_center())
	await _frames(6)
	assert_str(String(hud.panel_id())).is_equal("zoning")
	await _assert_drawer_ok("imar", win)
	await _recenter_in_free_map((a + b) * 0.5)
	# serbest haritadaki parsellere gerçek dokunuş (>= 10: büyük plan meclise gider)
	var mid := (a + b) * 0.5
	var picks: Array[Vector3] = []
	for pid: int in net.parcels:
		var c: Vector2 = net.parcels[pid].centroid
		if net.parcel_id_at(c.x, c.y) != pid or c.distance_to(mid) > 160.0:
			continue
		var sc := _screen(c)
		if hud.free_map_rect().grow(-20.0).has_point(sc):
			picks.append(Vector3(c.distance_to(mid), sc.x, sc.y))
	picks.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.x < q.x)
	assert_int(picks.size()).override_failure_message("serbest haritada yeterli parsel yok").is_greater_equal(12)
	for i in 12:
		await _tap(Vector2(picks[i].y, picks[i].z))
		await _frames(2)
	var model: ZoningFlowModel = _scene._decisions.zoning
	assert_int(model.parcel_ids.size()).override_failure_message(
			"dokunuşla eklenen parsel sayısı %d" % model.parcel_ids.size()).is_greater_equal(10)
	var use := _button("Konut")
	assert_bool(_reachable(use, win)).is_true()
	await _click(use.get_global_rect().get_center())
	await _frames(4)
	assert_bool(model.council_required()).override_failure_message("büyük plan meclis yoluna girmedi").is_true()
	var submit := _button(UiText.t(&"zoning.submit"))
	assert_bool(_reachable(submit, win)).override_failure_message("'Meclise sun' YARI çekmecede erişilemiyor").is_true()
	assert_float(submit.get_global_rect().size.y).is_greater_equal(44.0)
	var votes_before := hud.snapshot().council.votes.size()
	await _click(submit.get_global_rect().get_center())
	await _frames(6)
	var voted := false
	for day in 40:
		f.advance(1)
		await _frames(1)
		hud.refresh()
		if hud.snapshot().council.votes.size() > votes_before:
			voted = true
			break
	assert_bool(voted).override_failure_message("meclis oylaması açılmadı/sonuçlanmadı").is_true()
	# Plan gönderildikten SONRA "Döngü sonucu" aracı sonuç çekmecesini açmalı.
	var trace: Array[String] = []
	hud.tool_selected.connect(func(t: StringName) -> void: trace.append("tool:%s" % String(t)))
	hud.panel_closed.connect(func(id: StringName) -> void: trace.append("closed:%s" % String(id)))
	hud.toolbar.select_mode(ModeToolbar.MODE_PLAN)
	await _frames(2)
	var results := hud.toolbar.tool_button(ModeToolbar.TOOL_RESULTS)
	assert_object(results).is_not_null()
	await _click(results.get_global_rect().get_center())
	await _frames(8)
	assert_str(String(hud.panel_id())).override_failure_message(
			"'Döngü sonucu' plan gönderildikten sonra sonuç panelini açmadı (panel=%s, olaylar=%s)" % [
			String(hud.panel_id()), str(trace)]).is_equal("m2_results")
	hud.close_panel_hard()
