extends Control
## T-028 Ismeral etiketli topoloji haritası (DEV; Q-015 incelemesi). Dünya + ağ + T0 yerleşimi çalışma zamanında
## üretilir (WorldData görünümü, ayrı harita kaynağı değil; WLD-01/TEK-03). Damga: ÇALIŞMA VERİSİ — ONAYSIZ (Q-015).
## Açma: tools/godot.sh --path . res://scenes/dev/topology_map.tscn -- --view=full --seed=1467
## Komut satırı (-- sonrası): --seed=N (varsayılan: veri dosyası) --view=full|districts|table|D1..D6
##   --no-settlement (yoğunluk katmanı boş, hızlı) --cell=M (dünya hücresi m)
##   --no-fixed-size (2000x2000 içerik ölçeğini kapat)
##   --hide=density,network,contours,regions (tam harita katmanlarını kapat).
## Tuşlar: 1 tam harita · 2 D1–D6 yakın kesit · 3 kanon tablosu + sorular · H yoğunluk · N ağ · C kontur ·
##   R bölge elipsi.
## Üretilmiş hiçbir şey diske yazılmaz.

const DEFAULT_VIEW := "full"

var _model: TopologyModel = null
var _page: Control = null
var _view_name: String = DEFAULT_VIEW
var _args: Dictionary = {}


func _ready() -> void:
	var args := _parse_args()
	_args = args
	if not args.has("no-fixed-size"):
		# Pencere küçük olsa da (macOS menü çubuğu) tasarım uzayı 2000x2000 görüntüye render edilir.
		get_window().content_scale_size = Vector2i(2000, 2000)
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_view_name = String(args.get("view", DEFAULT_VIEW))
	var seed_arg := int(args["seed"]) if args.has("seed") else -1
	var cell := float(args["cell"]) if args.has("cell") else -1.0
	var loaded := TopologyLoader.load_all(seed_arg, not args.has("no-settlement"), cell)
	if loaded["model"] == null:
		push_error("topology_map: dünya verisi geçersiz: %s" % ", ".join(loaded["errors"]))
		return
	_model = loaded["model"]
	print("topology_map: üretim ms %s · özet %s" % [loaded["timings_ms"], _model.summary()])
	_show(_view_name)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_show("full")
		KEY_2:
			_show("districts")
		KEY_3:
			_show("table")
		KEY_H, KEY_N, KEY_C, KEY_R:
			_toggle_layer(key.keycode)


func _show(view_name: String) -> void:
	if _page != null:
		_page.queue_free()
	_view_name = view_name
	match view_name:
		"districts":
			var sheet := TopologyDistrictSheet.new()
			_attach(sheet)
			sheet.setup(_model, [])
		"table":
			var page := TopologyTablePage.new()
			_attach(page)
			page.setup(_model)
		_:
			if view_name.length() == 2 and view_name.begins_with("D"):
				var one := TopologyDistrictSheet.new()
				_attach(one)
				one.setup(_model, [StringName(view_name)])
			else:
				var map := TopologyMapView.new()
				_attach(map)
				var hidden := String(_args.get("hide", "")).split(",")
				map.show_density = not hidden.has("density")
				map.show_network = not hidden.has("network")
				map.show_contours = not hidden.has("contours")
				map.show_regions = not hidden.has("regions")
				map.setup(_model)


func _attach(page: Control) -> void:
	_page = page
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)


func _toggle_layer(keycode: Key) -> void:
	var map := _page as TopologyMapView
	if map == null:
		return
	match keycode:
		KEY_H:
			map.show_density = not map.show_density
		KEY_N:
			map.show_network = not map.show_network
		KEY_C:
			map.show_contours = not map.show_contours
		KEY_R:
			map.show_regions = not map.show_regions
	map.queue_redraw()


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
