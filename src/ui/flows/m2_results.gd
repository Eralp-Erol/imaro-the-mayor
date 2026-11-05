class_name M2Results
extends RefCounted
## "Döngü sonucu" sahibi (T-040, M2): sonuç panelini (`M2ResultPanel`) ve nedensellik panelini (`ReasonPanel`)
## `HudRoot.open_panel` ile açar; takip edilen imar önerisi parsellerini ve karşılaştırma başlangıcını tutar.
## UI yalnız `SimFacade` tipine bağlıdır (mock <-> gerçek sim: kod değişmez).
##
## Ana sahne tek satır: `var results := M2Results.attach(hud, facade, decisions)`.
## - Araç çubuğu: İmar modunda "Döngü sonucu" aracı (yalnız bu sahip kaydedince görünür; ölü düğme yok).
## - Takip: `track_parcels(ids)` imar önerisi verilince çağrılır (ana sahne ya da `DecisionPanels` akışı: gönderilmiş,
##   reddedilmemiş öneri otomatik izlenir). Karşılaştırma başlangıcı o anki `economy_outcome()`dır (ekonomi henüz
##   kurulmadıysa null: birikimli sayaçlar simülasyon başından beri okunur, hane farkı gösterilmez).
## - Başka panel açık değilse yeni öneri sonuç panelini kendiliğinden açar; açık bir panel (örn. imar akışı) ÇALINMAZ.
## - Nedensellik: bu sahip olay şeridi "Neden?" isteğini ve karar akışlarının `reason_wanted` isteğini de ReasonPanel'e
##   bağlar (gezinti durumu profil değişince korunur).

const PANEL_ID := &"m2_results"
const PANEL_REASON := &"reason"
## Panel açıkken tick'te yenileme üst sınırı (duvar saati, ms): sim günü başına ağır yeniden hesap yok (T-040 smoke).
## Süre dolunca TEK bir kuyruklu yenileme son durumu gösterir (duraklatılmış sim'de bayat veri kalmaz). 0 = sınırsız.
static var default_interval_msec: int = 250

var hud: HudRoot = null
var facade: SimFacade = null
var decisions: DecisionPanels = null
var tracked: PackedInt64Array = PackedInt64Array()
var baseline: EconomyOutcomeView = null
var baseline_tick: int = -1
## İmar önerisinin verildiği tick (öneri öncesi yatırımcı kararını ayırmak için).
var proposed_tick: int = -1

var _panel: M2ResultPanel = null
var _last_refresh_msec: int = -1000000
var _flush_pending: bool = false
var _reason_panel: ReasonPanel = null
var _reason_nav: Array = []
var _reason_initial: Callable = Callable()


static func attach(hud_in: HudRoot, facade_in: SimFacade, decisions_in: DecisionPanels = null) -> M2Results:
	var r := M2Results.new()
	r.hud = hud_in
	r.facade = facade_in
	r.decisions = decisions_in
	hud_in.register_tool(ModeToolbar.MODE_PLAN, ModeToolbar.TOOL_RESULTS)
	hud_in.tool_selected.connect(r._on_tool_selected)
	hud_in.refreshed.connect(r._on_refreshed)
	hud_in.panel_closed.connect(r._on_panel_closed)
	hud_in.reason_requested.connect(r._on_event_reason)
	if decisions_in != null:
		decisions_in.reason_wanted.connect(r.open_reason)
	return r


## Facade değişti (geliştirme sahnesi): takip ve başlangıç sıfırlanır.
func rebind(facade_in: SimFacade) -> void:
	facade = facade_in
	tracked = PackedInt64Array()
	baseline = null
	baseline_tick = -1
	proposed_tick = -1


# --- Açma / takip ---

func open() -> void:
	hud.open_panel(PANEL_ID, &"m2.title", _build_results, true)


func is_open() -> bool:
	return hud.panel_id() == PANEL_ID


func results_panel() -> M2ResultPanel:
	return _panel if _alive(_panel) else null


func reason_panel() -> ReasonPanel:
	return _reason_panel if _alive(_reason_panel) else null


## İmar önerisi verilen parselleri takibe alır ve karşılaştırma başlangıcını o ana koyar. Başka panel açık değilse
## sonuç panelini açar. Aynı küme tekrar verilirse hiçbir şey değişmez.
func track_parcels(parcel_ids: PackedInt64Array, submitted_tick: int = -1) -> void:
	if parcel_ids.is_empty() or parcel_ids == tracked:
		return
	tracked = parcel_ids.duplicate()
	capture_baseline()
	proposed_tick = submitted_tick if submitted_tick >= 0 else baseline_tick
	if not hud.is_panel_open():
		open()
	elif is_open():
		_refresh_panel()


## Karşılaştırma başlangıcı: şu anki ekonomik sonuç (kurulu değilse null).
func capture_baseline() -> void:
	var o := facade.economy_outcome()
	baseline = o if o != null and o.available else null
	baseline_tick = facade.current_tick()


func build_model() -> M2ResultModel:
	return M2ResultModel.build(facade, tracked, baseline, baseline_tick, proposed_tick)


## Nedensellik panelini açar; `initial(panel)` ilk görünümü kurar.
func open_reason(initial: Callable) -> void:
	_reason_nav = []
	_reason_initial = initial
	hud.open_panel(PANEL_REASON, &"reason.title", _build_reason, true)


func _on_event_reason(event: SimEvent) -> void:
	open_reason(func(p: ReasonPanel) -> void: p.show_event(event))


# --- İç ---

func _build_results(ctx: UiContext) -> Control:
	_last_refresh_msec = Time.get_ticks_msec()
	_panel = M2ResultPanel.create(ctx, facade, self)
	_panel.reason_requested.connect(open_reason)
	return _panel


func _build_reason(ctx: UiContext) -> Control:
	_last_refresh_msec = Time.get_ticks_msec()
	var p := ReasonPanel.create(ctx, facade)
	_reason_panel = p
	if not _reason_nav.is_empty():
		p.restore_nav(_reason_nav)
	elif _reason_initial.is_valid():
		_reason_initial.call(p)
	p.nav_changed.connect(func() -> void: _reason_nav = p.nav_state())
	_reason_nav = p.nav_state()
	return p


func _on_tool_selected(tool_id: StringName) -> void:
	if tool_id == ModeToolbar.TOOL_RESULTS:
		open()


func _on_refreshed() -> void:
	_follow_zoning_flow()
	# Gerekçe paneli de aynı üst sınırı kullanır: eskiden her tick'te tüm düğümleri yeniden kurardı (kare takılması).
	if results_panel() != null or reason_panel() != null:
		_refresh_throttled()


func _refresh_panel() -> void:
	var p := results_panel()
	var rp := reason_panel()
	if p == null and rp == null:
		return
	_last_refresh_msec = Time.get_ticks_msec()
	if p != null:
		p.refresh()
	if rp != null:
		rp.refresh()


## Yenileme üst sınırı: sınır içindeyse tek bir kuyruklu yenileme planlanır (panel kapalıyken hiç iş yok).
func _refresh_throttled() -> void:
	var wait := default_interval_msec - (Time.get_ticks_msec() - _last_refresh_msec)
	if default_interval_msec <= 0 or wait <= 0:
		_refresh_panel()
		return
	if _flush_pending or not hud.is_inside_tree():
		return
	_flush_pending = true
	hud.get_tree().create_timer(float(wait) / 1000.0).timeout.connect(func() -> void:
		_flush_pending = false
		_refresh_panel())


## Karar akışında gönderilmiş (reddedilmemiş) imar önerisinin parselleri otomatik izlenir.
func _follow_zoning_flow() -> void:
	if decisions == null or decisions.zoning == null:
		return
	var z := decisions.zoning
	if z.last_submit == null or z.last_submit.is_rejected() or z.parcel_ids.is_empty():
		return
	track_parcels(z.parcel_ids, z.last_submit.tick)


func _on_panel_closed(panel_id: StringName) -> void:
	if panel_id == PANEL_ID:
		_panel = null
	elif panel_id == PANEL_REASON:
		_reason_panel = null


## Serbest bırakılmış nesne tipli parametreye geçirilemez ("previously freed" SCRIPT ERROR):
## Variant alınır, önce is_instance_valid.
func _alive(c: Variant) -> bool:
	return is_instance_valid(c) and (c as Control).is_inside_tree()
