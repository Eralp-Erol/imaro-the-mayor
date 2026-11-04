class_name VegetationViewTestSupport
extends RefCounted
## tests/view/vegetation ortak yardımcıları (test paketi değildir). B0 hafif-ağ sütunları
## (`VegetationTestSupport.light`)
## üzerine görünüm düzeni; mesh'siz (`numbers_only`) ve mesh'li (`load_full`) görünüm tabloları; süreç başına bir kez.
## SALT OKUNUR kullanın.

static var _layout: VegetationLayout = null
static var _look_numbers: VegetationLook = null
static var _look_full: VegetationLook = null


static func config() -> VegetationViewConfig:
	return VegetationViewConfig.load_default()


static func species() -> VegetationSpecies:
	return VegetationTestSupport.species()


static func has_proxy() -> PackedByteArray:
	var sp := species()
	var out := PackedByteArray()
	for i in sp.size():
		out.append(1 if sp.has_proxy(i) else 0)
	return out


static func world() -> WorldData:
	return SettlementTestSupport.light().net.world


static func layout() -> VegetationLayout:
	if _layout == null:
		_layout = VegetationLayout.build(VegetationTestSupport.light(), world(), species().height_m, has_proxy())
	return _layout


## YAZILABİLİR yeni düzen (maske testleri; paylaşılan `layout()` salt okunurdur).
static func fresh_layout() -> VegetationLayout:
	return VegetationLayout.build(VegetationTestSupport.light(), world(), species().height_m, has_proxy())


## Tepe hücresinin ortasından doğu-batı geçen, `radius` yarıçaplı koridor ([a, b, r]).
static func peak_corridor(radius: float = 10.0) -> Array:
	var lay := layout()
	var o := lay.cell_origin(lay.cols.peak_cell().y)
	var c := lay.cols.cell_m
	return [Vector2(o.x, o.y + c * 0.5), Vector2(o.x + c, o.y + c * 0.5), radius]


static func look_numbers() -> VegetationLook:
	if _look_numbers == null:
		_look_numbers = VegetationLook.numbers_only(species(), config())
	return _look_numbers


static func look_full() -> VegetationLook:
	if _look_full == null:
		_look_full = VegetationLook.load_full(species(), config())
	return _look_full


## En kalabalık hücrenin merkezinde, `height` m yükseklikte kamera noktası (dünya).
static func camera_over_peak(height: float = 30.0) -> Vector3:
	var lay := layout()
	var key := lay.cols.peak_cell().y
	var o := lay.cell_origin(key)
	var c := lay.cols.cell_m * 0.5
	return Vector3(o.x + c, lay.cell_ymin[lay.index_of_key(key)] + height, o.y + c)


## Yeni görünüm (sahneye eklenir, auto_free çağıranda).
static func make_view(parent: Node, p_look: VegetationLook, p_config: VegetationViewConfig = null) -> VegetationView:
	var view := VegetationView.new()
	parent.add_child(view)
	view.setup(p_look, p_config if p_config != null else config())
	view.set_layout(layout())
	return view
