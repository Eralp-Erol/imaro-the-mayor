class_name ParcelAreaHighlight
extends Node3D
## Açık imar panelinin teklif alanını (birden çok parsel) haritada vurgular (sanat direktörü düzeltmesi, M2).
## YALNIZ görünüm katmanı: parsel çokgenleri dünya verisinden (`WorldNetwork.parcels`) okunur, sim'e/komutlara
## hiçbir şey yazılmaz (CAN-03/determinizm). Her parsel için tek `ParcelSelectionRing` (aynı çizgi dili, ölçek bandı
## kuralları dahil: metro'da işaret yok, küçük parselde merkez halkası); en çok `MAX_RINGS` parsel çizilir (fazlası
## yalnız panelde sayılır; çizim maliyeti sınırlı kalır).
##
## Kullanım: `ParcelAreaHighlight.attach(hud, camera, net, view_root, ground)`; kaynak `HudRoot.map_highlight_changed`.

const MAX_RINGS := 40

var camera_rig: CameraRig = null
var ground_height: Callable = Callable()
var parcels: Dictionary = {}
var band: StringName = &""

var _rings: Array[ParcelSelectionRing] = []
var _ids: PackedInt64Array = PackedInt64Array()


static func attach(hud: HudRoot, rig: CameraRig, net: WorldNetwork, parent: Node3D,
		ground: Callable) -> ParcelAreaHighlight:
	var h := ParcelAreaHighlight.new()
	h.camera_rig = rig
	h.ground_height = ground
	h.parcels = net.parcels if net != null else {}
	parent.add_child(h)
	if rig != null:
		h.set_band(rig.scale_band)
		rig.scale_band_changed.connect(h.set_band)
	hud.map_highlight_changed.connect(h.show_parcels)
	h.show_parcels(hud.map_highlight())
	return h


func _init() -> void:
	name = "ParcelAreaHighlight"


func set_band(band_in: StringName) -> void:
	band = band_in
	for r in _rings:
		r.set_band(band_in)


## Vurgulanan parselleri değiştirir; boş liste hepsini kaldırır. Olmayan kimlik atlanır.
func show_parcels(ids: PackedInt64Array) -> void:
	_ids = ids.duplicate()
	var shown := 0
	for id in ids:
		var parcel := parcels.get(id) as WorldParcel
		if parcel == null or shown >= MAX_RINGS:
			continue
		_ring(shown).select(parcel)
		shown += 1
	for i in range(shown, _rings.size()):
		_rings[i].clear()


## Çizilen (işareti olan) parsel sayısı (test/ölçüm).
func marked_count() -> int:
	var n := 0
	for r in _rings:
		if r.has_mark():
			n += 1
	return n


func highlighted_ids() -> PackedInt64Array:
	var out := PackedInt64Array()
	for r in _rings:
		if r.parcel_id() > 0:
			out.append(r.parcel_id())
	return out


func _ring(index: int) -> ParcelSelectionRing:
	while _rings.size() <= index:
		var r := ParcelSelectionRing.new()
		r.name = "AreaRing%d" % _rings.size()
		add_child(r)
		r.bind(camera_rig, ground_height)
		r.set_band(band)
		_rings.append(r)
	return _rings[index]
