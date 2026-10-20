class_name WorldDebugMarkers
extends Node3D
## Geliştirici işaretleri (varsayılan KAPALI): D1–D6 bölge çapaları ve T0 saha işaretleri, WorldData'dan (gerçek veri).
## Parsel/ilçe sınırı değildir; yalnız çapa ve veri işareti. Kamera uzaklığına göre ekranda ~sabit boyut.

const REGION_COLORS: Array[Color] = [
	Color(0.9, 0.25, 0.25), Color(0.65, 0.4, 0.85), Color(0.25, 0.5, 0.95),
	Color(0.4, 0.75, 0.25), Color(0.9, 0.55, 0.2), Color(0.98, 0.75, 0.2),
]
const SITE_COLORS := {&"port": Color(1.0, 0.1, 0.1), &"first_industry": Color(1.0, 0.95, 0.2)}

var _items: Array[Node3D] = []
var _labels: Array[Label3D] = []


func build(world: WorldData) -> void:
	for child in get_children():
		child.queue_free()
	_items.clear()
	_labels.clear()
	for region in world.regions:
		var color := REGION_COLORS[(region.id - 1) % REGION_COLORS.size()]
		_add_marker(world, region.anchor, String(region.code), color, 1.0)
	for site in world.sites:
		var color: Color = SITE_COLORS.get(site.kind, Color.WHITE)
		_add_marker(world, site.position, String(site.id), color, 0.6)
	visible = false
	set_process(false)


func set_markers_visible(value: bool) -> void:
	visible = value
	set_process(value)


## Çağıran kamera uzaklığına göre ölçek günceller.
func rescale_for(camera: Camera3D) -> void:
	for node in _items:
		var d := camera.global_position.distance_to(node.global_position)
		node.scale = Vector3.ONE * maxf(d * 0.012, 20.0)


func _add_marker(world: WorldData, pos: Vector2, text: String, color: Color, size: float) -> void:
	var holder := Node3D.new()
	holder.name = "Marker_%s" % text
	var y := maxf(world.height_at(pos.x, pos.y), world.sea_level)
	holder.position = Vector3(pos.x, y, pos.y)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25 * size
	cyl.bottom_radius = 0.25 * size
	cyl.height = 10.0 * size
	cyl.radial_segments = 6
	cyl.rings = 1
	pole.mesh = cyl
	pole.position = Vector3(0, 5.0 * size, 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	pole.material_override = mat
	holder.add_child(pole)
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.06 * size
	label.font_size = 48
	label.outline_size = 12
	label.modulate = color
	label.position = Vector3(0, (11.5 if size >= 1.0 else 17.0) * size, 0)
	holder.add_child(label)
	add_child(holder)
	_items.append(holder)
	_labels.append(label)
