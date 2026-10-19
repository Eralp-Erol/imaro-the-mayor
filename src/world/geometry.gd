class_name BlockGeometry
extends Node3D
## Geometry is baked by material with normalized inverse-transpose normals.

const COLORS = {
	"cream": "e8dfca", "white": "f3ecdd", "sand": "d6c3a4", "rose": "d6b0a0",
	"sage": "b7c4b6", "blue": "afc1c8", "trim": "f2ead8", "glass": "466171",
	"roof": "b7866d", "metal": "536365", "solar": "2e526a", "tank": "c5cdca",
	"red": "ba5441", "navy": "365d75", "ochre": "d6aa58", "wood": "8d7151",
	"asphalt": "777f7e", "sidewalk": "d3cdbd", "line": "ede8d7", "grass": "93a779",
	"green": "6f8e50", "leaf": "8ca35e", "pine": "4f7251", "soil": "b1a187",
	"sea": "468d9d", "foam": "95c6c7", "hill": "94aaa5", "skin": "c89771",
	"pants": "405864", "orange": "d78f40", "concrete": "b6b6aa", "selection": "2eabac"
}
static var materials: Dictionary = {}
static var meshes: Dictionary = {}
var batches: Dictionary = {}

static func material(key: String) -> StandardMaterial3D:
	if not materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(COLORS.get(key, key))
		m.roughness = 0.93
		materials[key] = m
	return materials[key]

static func primitive(kind: String) -> Mesh:
	if not meshes.has(kind):
		if kind == "box":
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			meshes[kind] = box
		elif kind == "cylinder" or kind == "cone":
			var cylinder := CylinderMesh.new()
			cylinder.height = 1.0
			cylinder.top_radius = 0.0 if kind == "cone" else 0.5
			cylinder.bottom_radius = 0.5
			cylinder.radial_segments = 6
			meshes[kind] = cylinder
		else:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var ring := [Vector3(0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(-0.5, 0, 0), Vector3(0, 0, -0.5)]
			for i in range(4):
				for top in [true, false]:
					var a: Vector3 = ring[i if top else (i + 1) % 4]
					var b: Vector3 = ring[(i + 1) % 4 if top else i]
					var c := Vector3(0, 0.65 if top else -0.45, 0)
					var normal := (c - a).cross(b - a).normalized()
					for v in [a, b, c]:
						st.set_normal(normal)
						st.add_vertex(v)
			meshes[kind] = st.commit()
	return meshes[kind]

func shape(at: Vector3, size: Vector3, color: String, kind: String = "box", rotation: Vector3 = Vector3.ZERO) -> void:
	var key := color + ":" + kind
	if not batches.has(key):
		batches[key] = []
	batches[key].append(Transform3D(Basis.from_euler(rotation).scaled(size), at))

func bake() -> void:
	var surfaces: Dictionary = {}
	for key: String in batches:
		var parts := key.split(":")
		if not surfaces.has(parts[0]):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[parts[0]] = surface
		var st: SurfaceTool = surfaces[parts[0]]
		var arrays := primitive(parts[1]).surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in range(vertices.size()): indices.append(i)
		for transform: Transform3D in batches[key]:
			var normal_basis := transform.basis.inverse().transposed()
			for i in indices:
				st.set_normal((normal_basis * normals[i]).normalized())
				st.add_vertex(transform * vertices[i])
	for color: String in surfaces:
		var st: SurfaceTool = surfaces[color]
		st.index()
		var node := MeshInstance3D.new()
		node.mesh = st.commit()
		node.material_override = material(color)
		add_child(node)
	batches.clear()

func sign_text(text: String, at: Vector3, size: int = 48, pixel: float = 0.012, rotation_y: float = 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = Color("f5eddc")
	label.outline_size = 0
	label.no_depth_test = false
	label.shaded = true
	label.rotation.y = rotation_y
	add_child(label)

func tree(at: Vector3, palm: bool = false) -> void:
	shape(at + Vector3(0, 1.8, 0), Vector3(0.42, 3.6, 0.42), "wood", "cylinder")
	if palm:
		for i in range(6):
			var angle := i * TAU / 6.0
			shape(at + Vector3(cos(angle) * 1.2, 3.8, sin(angle) * 1.2), Vector3(3.4, 0.24, 0.9), "green", "diamond", Vector3(0, -angle, -0.18))
	else:
		shape(at + Vector3(0, 3.7, 0), Vector3(3.2, 3.3, 3.2), "green", "diamond")
		shape(at + Vector3(0.65, 4.6, 0.2), Vector3(2.7, 2.7, 2.7), "leaf", "diamond")

func bench(at: Vector3, angle: float = 0.0) -> void:
	shape(at + Vector3(0, 0.65, 0), Vector3(2.1, 0.18, 0.7), "wood", "box", Vector3(0, angle, 0))
	shape(at + Vector3(0, 1.05, -0.3), Vector3(2.1, 0.7, 0.13), "wood", "box", Vector3(0, angle, 0))
	for x in [-0.8, 0.8]:
		shape(at + Vector3(x, 0.3, 0), Vector3(0.15, 0.6, 0.5), "metal")

func person(at: Vector3, color: String) -> void:
	shape(at + Vector3(0, 1.5, 0), Vector3(0.38, 0.4, 0.36), "skin")
	shape(at + Vector3(0, 0.98, 0), Vector3(0.5, 0.65, 0.28), color)
	for x in [-0.14, 0.14]:
		shape(at + Vector3(x, 0.35, 0), Vector3(0.17, 0.65, 0.22), "pants")

func car(at: Vector3, color: String, angle: float = 0.0) -> void:
	var car_node := BlockGeometry.new()
	car_node.position = at
	car_node.rotation.y = angle
	car_node.shape(Vector3(0, 0.65, 0), Vector3(1.65, 0.7, 3.2), color)
	car_node.shape(Vector3(0, 1.2, 0.1), Vector3(1.45, 0.55, 1.65), "glass")
	car_node.shape(Vector3(0, 1.5, 0.1), Vector3(1.5, 0.15, 1.7), color)
	for x in [-0.82, 0.82]:
		for z in [-0.98, 0.98]:
			car_node.shape(Vector3(x, 0.4, z), Vector3(0.2, 0.65, 0.65), "pants")
	add_child(car_node)
	car_node.bake()
