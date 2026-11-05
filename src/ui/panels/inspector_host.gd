class_name InspectorHost
extends RefCounted
## Parsel/bölge denetçisi sahibi (T-041): seçili parseli ve kamera ölçek bandını tutar, paneli `HudRoot.open_panel` ile
## açar, sim ilerledikçe (kısıtlı) yeniler. UI yalnız `SimFacade` tipine bağlıdır (mock <-> gerçek sim: kod değişmez).
##
## Ana sahne: `var inspector := InspectorHost.attach(hud, facade, reason_opener, zoning_opener)`; haritada seçim
## `select_parcel(id)` (id <= 0: boş seçim), kamera bandı `set_band(band)`.
## - `reason_opener(initial: Callable)`: nedensellik panelini açar (M2Results.open_reason).
## - `zoning_opener(parcel_id: int)`: imar akışını bu parselle açar (DecisionPanels.open_zoning).
## - `zoning_adder(parcel_id) -> bool`: İMAR akışı açıkken haritada seçilen parsel denetçiyi AÇMAZ, teklifin
##   alanına eklenir (T-043A: birden çok parsel; `DecisionPanels.add_zoning_parcel`).
## - Başka panel açıkken boş tıklama o paneli ÇALMAZ; denetçi açıkken boş tıklama açıklayıcı boş durumu gösterir.

const PANEL_ID := &"inspector"
## Panel açıkken tick'te yenileme üst sınırı (duvar saati, ms); 0 = sınırsız.
static var default_interval_msec: int = 250

var hud: HudRoot = null
var facade: SimFacade = null
var parcel_id: int = SimContract.NO_ID
var band: StringName = &""

var _reason_opener: Callable = Callable()
var _zoning_opener: Callable = Callable()
var _zoning_adder: Callable = Callable()
var _panel: InspectorPanel = null
var _last_refresh_msec: int = -1000000
var _flush_pending: bool = false


static func attach(hud_in: HudRoot, facade_in: SimFacade, reason_opener: Callable = Callable(),
		zoning_opener: Callable = Callable(), zoning_adder: Callable = Callable()) -> InspectorHost:
	var h := InspectorHost.new()
	h.hud = hud_in
	h.facade = facade_in
	h._reason_opener = reason_opener
	h._zoning_opener = zoning_opener
	h._zoning_adder = zoning_adder
	hud_in.refreshed.connect(h._on_refreshed)
	hud_in.panel_closed.connect(h._on_panel_closed)
	return h


func rebind(facade_in: SimFacade) -> void:
	facade = facade_in
	parcel_id = SimContract.NO_ID


## Haritadan seçim. `id <= 0` boş seçimdir: denetçi açıksa boş durumu gösterir, değilse bir şey yapmaz.
func select_parcel(id: int) -> void:
	parcel_id = id if id > 0 else SimContract.NO_ID
	if parcel_id > 0 and hud.panel_id() == DecisionPanels.PANEL_ZONING and _zoning_adder.is_valid():
		_zoning_adder.call(parcel_id)  # imar akışı açık: seçim teklifin alanına eklenir, denetçi panelin yerini almaz
		return
	if parcel_id > 0:
		open()
	elif is_open():
		_refresh_panel()


## Ölçek bandı değişti (`CameraRig.scale_band_changed`): yalnız sunum sadeleşir, seçim ve veri aynı kalır.
func set_band(band_in: StringName) -> void:
	if band_in == band:
		return
	band = band_in
	if is_open():
		_refresh_panel()


func open() -> void:
	hud.open_panel(PANEL_ID, &"inspector.title", _build, true)


func is_open() -> bool:
	return hud.panel_id() == PANEL_ID


func panel() -> InspectorPanel:
	return _panel if is_instance_valid(_panel) and _panel.is_inside_tree() else null


func build_model() -> InspectorModel:
	return InspectorModel.build(facade, parcel_id, band)


# --- İç ---

func _build(ctx: UiContext) -> Control:
	_last_refresh_msec = Time.get_ticks_msec()
	_panel = InspectorPanel.create(ctx, facade, self)
	_panel.reason_requested.connect(_on_reason)
	_panel.zoning_requested.connect(_on_zoning)
	return _panel


func _on_reason(initial: Callable) -> void:
	if _reason_opener.is_valid():
		_reason_opener.call(initial)


func _on_zoning(id: int) -> void:
	if _zoning_opener.is_valid():
		_zoning_opener.call(id)


func _on_refreshed() -> void:
	if panel() != null:
		_refresh_throttled()


func _refresh_panel() -> void:
	var p := panel()
	if p != null:
		_last_refresh_msec = Time.get_ticks_msec()
		p.refresh()


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


func _on_panel_closed(panel_id: StringName) -> void:
	if panel_id == PANEL_ID:
		_panel = null
