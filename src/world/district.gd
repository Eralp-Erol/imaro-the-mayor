class_name DistrictView
extends Node3D

var parcel_nodes: Dictionary = {}
var selection: BlockGeometry
var specs: Array[Dictionary]

func build(data: Array[Dictionary]) -> void:
	specs = data
	var ground := BlockGeometry.new()
	add_child(ground)
	ground.shape(Vector3(4, -0.7, 0), Vector3(116, 1.0, 102), "grass")
	ground.shape(Vector3(-112, -0.9, 0), Vector3(116, 0.2, 240), "sea")
	ground.shape(Vector3(-50, -0.1, 0), Vector3(8, 0.7, 102), "sidewalk")
	ground.shape(Vector3(-54.1, 0.1, 0), Vector3(0.45, 0.6, 102), "trim")
	for x in [-44.0, 0.0, 44.0]:
		ground.shape(Vector3(x, -0.1, 0), Vector3(7, 0.2, 95), "asphalt")
		for z in range(-43, 46, 7):
			ground.shape(Vector3(x, 0.02, z), Vector3(0.15, 0.02, 2.4), "line")
	for z in [-39.0, 0.0, 39.0]:
		ground.shape(Vector3(0, -0.08, z), Vector3(95, 0.2, 7), "asphalt")
		for x in range(-42, 44, 7):
			ground.shape(Vector3(x, 0.04, z), Vector3(2.4, 0.02, 0.15), "line")
	for bx in [-22.0, 22.0]:
		for bz in [-20.0, 20.0]:
			ground.shape(Vector3(bx, 0.0, bz), Vector3(36, 0.5, 30), "sidewalk")
	for x in [-44.0, 0.0, 44.0]:
		for z in [0.0, 39.0]:
			for offset in range(-2, 3):
				ground.shape(Vector3(x + offset * 1.1, 0.04, z - 4.6), Vector3(0.55, 0.025, 2.0), "line")
	for z in range(-42, 49, 13):
		ground.tree(Vector3(-50, 0.4, z), true)
		ground.bench(Vector3(-52, 0.35, z + 5), PI / 2)
	for x in [-39.8, 4.2, 39.8]:
		for z in [-33.0, -5.0, 6.0, 34.0]:
			ground.tree(Vector3(x, 0.25, z))
	for i in range(12):
		var px := -49.0 if i < 5 else (-39.6 if i % 2 == 0 else 39.5)
		ground.person(Vector3(px, 0.35, -34 + (i * 13 % 72)), ["navy", "red", "ochre", "cream"][i % 4])
	for z in [-27, 18, 33]:
		ground.car(Vector3(-45.7, 0.05, z), "ochre" if z == 18 else "white")
	ground.car(Vector3(1.7, 0.05, -16), "navy", PI)
	ground.car(Vector3(23, 0.05, 40.7), "red", PI / 2)
	# Sparse real geometry beyond the playable district, not a photographic backdrop.
	for i in range(7):
		ground.shape(Vector3(-80 + i * 29, -2, -108 - (i % 2) * 10), Vector3(48, 28 + i % 3 * 11, 38), "hill", "diamond")
	for i in range(18):
		ground.shape(Vector3(-64 - (i % 4) * 8, -0.77, -62 + i * 8), Vector3(2.6, 0.025, 0.12), "foam")
	ground.bake()
	for parcel in specs:
		update_parcel(parcel)
	selection = BlockGeometry.new()
	add_child(selection)
	for z in [-5.95, 5.95]:
		selection.shape(Vector3(0, 0.4, z), Vector3(8.2, 0.12, 0.22), "selection")
	for x in [-4.0, 4.0]:
		selection.shape(Vector3(x, 0.4, 0), Vector3(0.22, 0.12, 11.9), "selection")
	selection.bake()
	selection.visible = false

func update_parcel(p: Dictionary) -> void:
	if parcel_nodes.has(p.id):
		remove_child(parcel_nodes[p.id])
		parcel_nodes[p.id].queue_free()
	var g := BlockGeometry.new()
	g.position = Vector3(p.x, 0.28, p.z)
	g.rotation.y = p.rotation
	add_child(g)
	parcel_nodes[p.id] = g
	match p.use:
		"empty":
			g.shape(Vector3(0, 0.02, 0), Vector3(7.5, 0.12, 11.2), "soil")
			for x in [-3.65, 3.65]:
				g.shape(Vector3(x, 0.35, 0), Vector3(0.2, 0.6, 10), "sand")
			g.shape(Vector3(0, 0.1, -3.5), Vector3(2.2, 0.2, 1.5), "grass")
		"park":
			g.shape(Vector3(0, 0.02, 0), Vector3(7.4, 0.12, 11.1), "grass")
			g.shape(Vector3(0, 0.1, 0), Vector3(2, 0.1, 11.1), "sidewalk")
			g.tree(Vector3(-2, 0, -3))
			g.tree(Vector3(2, 0, 2))
			g.bench(Vector3(-2, 0, 1))
			g.person(Vector3(0.2, 0.2, -1), "red")
		"service":
			building(g, p, 2, "sage", "MAHALLE EVİ")
		"construction":
			construction(g, p)
		_:
			building(g, p, p.floors, p.color, p.shop)
	g.bake()
	var body := StaticBody3D.new()
	body.set_meta("parcel_id", p.id)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var height: float = p.floors * 2.35 if p.use in ["apartment", "construction"] else 0.4
	box.size = Vector3(7.8, height, 11.6)
	collision.shape = box
	collision.position.y = height / 2
	body.add_child(collision)
	g.add_child(body)

func building(g: BlockGeometry, p: Dictionary, floors: int, color: String, shop: String) -> void:
	var width: float = 6.3 + (p.id % 3) * 0.3
	var depth := 8.5 if p.id % 3 != 0 else 9.2
	var height := floors * 2.35 + 0.65
	g.shape(Vector3(0, height / 2, 0), Vector3(width, height, depth), color)
	g.shape(Vector3(0, 0.25, 0), Vector3(width + 0.2, 0.5, depth + 0.2), "sand")
	g.shape(Vector3(0, height + 0.06, 0), Vector3(width + 0.25, 0.2, depth + 0.25), "trim")
	g.shape(Vector3(0, height + 0.18, 0), Vector3(width - 0.45, 0.08, depth - 0.45), "roof")
	for x in [-width / 2, width / 2]:
		g.shape(Vector3(x, height + 0.4, 0), Vector3(0.16, 0.6, depth), color)
	for z in [-depth / 2, depth / 2]:
		g.shape(Vector3(0, height + 0.4, z), Vector3(width, 0.6, 0.16), color)
	for floor in range(floors):
		var y := floor * 2.35 + 1.3 + (0.65 if floor > 0 else 0.0)
		for z in [-2.7, 0.0, 2.7]:
			g.shape(Vector3(width / 2 + 0.015, y, z), Vector3(0.06, 1.25, 1.0), "glass")
			g.shape(Vector3(-width / 2 - 0.015, y, z), Vector3(0.06, 1.25, 1.0), "glass")
		for x in [-2.05, 1.8]:
			g.shape(Vector3(x, y, -depth / 2 - 0.015), Vector3(1.3, 1.3, 0.08), "glass")
			g.shape(Vector3(x, y, depth / 2 + 0.015), Vector3(1.45, 1.6, 0.08), "glass")
			if floor > 0:
				var balcony_z := depth / 2 + 0.55
				g.shape(Vector3(x, y - 0.95, balcony_z), Vector3(2.25, 0.18, 1.2), "trim")
				g.shape(Vector3(x, y - 0.45, balcony_z + 0.52), Vector3(2.25, 0.72, 0.12), color)
				g.shape(Vector3(x, y - 0.05, balcony_z + 0.52), Vector3(2.3, 0.09, 0.14), "metal")
				for side in [-1.06, 1.06]:
					g.shape(Vector3(x + side, y - 0.5, balcony_z), Vector3(0.12, 0.62, 1.15), color)
	if shop != "":
		g.shape(Vector3(0, 1.2, depth / 2 + 0.05), Vector3(5.9, 2.1, 0.12), "glass")
		var awning := "red" if shop == "BAKKAL" else "navy"
		g.shape(Vector3(0, 2.45, depth / 2 + 0.8), Vector3(6.3, 0.18, 1.7), awning, "box", Vector3(0.13, 0, 0))
		g.shape(Vector3(0, 2.7, depth / 2 + 0.13), Vector3(6.3, 0.7, 0.15), awning)
		g.sign_text(shop, Vector3(0, 2.72, depth / 2 + 0.24), 48, 0.014)
		if shop == "KAFE":
			for x in [-2.0, 1.8]:
				g.shape(Vector3(x, 0.8, depth / 2 + 1.6), Vector3(0.9, 0.12, 0.8), "wood")
				g.shape(Vector3(x, 0.4, depth / 2 + 1.6), Vector3(0.16, 0.8, 0.16), "metal")
	else:
		g.shape(Vector3(-0.1, 1.0, depth / 2 + 0.08), Vector3(1.0, 2.0, 0.1), "wood")
	if p.id % 4 == 0:
		g.shape(Vector3(1, height + 1.0, 0), Vector3(2.3, 0.8, 0.8), "tank", "cylinder", Vector3(0, 0, PI / 2))
		g.shape(Vector3(1, height + 0.5, 1.0), Vector3(2.3, 0.1, 1.5), "solar", "box", Vector3(0.4, 0, 0))
	if p.id % 3 == 0:
		g.shape(Vector3(width / 2 + 0.3, 4.1, 1.4), Vector3(0.6, 0.7, 1.0), "tank")

func construction(g: BlockGeometry, p: Dictionary) -> void:
	g.shape(Vector3.ZERO, Vector3(7.5, 0.25, 10.8), "soil")
	var built: int = maxi(1, int(ceil(p.get("progress", 0.1) * p.floors)))
	for floor in range(built):
		var y := floor * 2.35
		g.shape(Vector3(0, y + 0.15, 0), Vector3(6.8, 0.3, 8.5), "concrete")
		for x in [-3.0, 0.0, 3.0]:
			for z in [-3.8, 0.0, 3.8]:
				g.shape(Vector3(x, y + 1.2, z), Vector3(0.35, 2.35, 0.35), "concrete")
	for x in [-3.8, 3.8]:
		g.shape(Vector3(x, 0.8, 0), Vector3(0.12, 1.6, 11), "ochre")
	g.shape(Vector3(0, 0.8, 5.45), Vector3(7.6, 1.6, 0.12), "ochre")
	g.sign_text("ŞANTİYE", Vector3(0, 1, 5.55), 38, 0.016)
	g.shape(Vector3(-3, 8.5, -4.5), Vector3(0.35, 17, 0.35), "orange")
	g.shape(Vector3(0, 16.8, -4.5), Vector3(11, 0.35, 0.4), "orange")

func select(id: int) -> void:
	selection.visible = id >= 0
	if id >= 0:
		selection.position = Vector3(specs[id].x, 0, specs[id].z)

func pick(point: Vector3) -> int:
	for p in specs:
		if absf(point.x - p.x) < p.width / 2 and absf(point.z - p.z) < p.depth / 2:
			return p.id
	return -1

func pick_ray(camera: Camera3D, screen: Vector2) -> int:
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 600)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.collider.get_meta("parcel_id", -1) if not hit.is_empty() else -1
