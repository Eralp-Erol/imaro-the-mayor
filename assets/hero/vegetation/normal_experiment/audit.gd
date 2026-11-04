extends SceneTree


func _initialize() -> void:
	call_deferred("_audit")


func _audit() -> void:
	var errors: Array[String] = []
	var scene := (
		load("res://assets/hero/vegetation/normal_experiment/plane_proxy.glb") as PackedScene
	)
	var node := scene.instantiate()
	var albedo := load("res://assets/hero/vegetation/vegetation_atlas.png") as Texture2D
	var normal_data := (
		load("res://assets/hero/vegetation/normal_experiment/object_normals.png") as Texture2D
	)
	var args := OS.get_cmdline_user_args()
	var textures := {}
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var mat := mesh.mesh.surface_get_material(0) as ShaderMaterial
		if mat == null:
			errors.append("experimental asset import material missing")
			continue
		if args.has("--negative=missing"):
			mat.set_shader_parameter("object_normals", null)
		if args.has("--negative=zero"):
			var zero := Image.create(1024, 384, false, Image.FORMAT_RGBA8)
			zero.fill(Color(0.5, 0.5, 0.5, 1.0))
			mat.set_shader_parameter("object_normals", ImageTexture.create_from_image(zero))
		var maps: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(
				"res://experiments/t057-proxy-normals/projection_maps.json"
			)
		)
		if args.has("--negative=map"):
			mat.set_shader_parameter("map_u_0", Vector4.ZERO)
		for i in range(3):
			var record: Dictionary = maps["maps"][i]
			var raw_u: Variant = mat.get_shader_parameter("map_u_%d" % i)
			var raw_v: Variant = mat.get_shader_parameter("map_v_%d" % i)
			if typeof(raw_u) != TYPE_VECTOR4 or typeof(raw_v) != TYPE_VECTOR4:
				errors.append("imported affine uniforms missing")
				continue
			var u: Vector4 = raw_u
			var v: Vector4 = raw_v
			for vertex in record["vertices"]:
				var point: Array = vertex["position"]
				var p := Vector4(point[0], point[1], point[2], 1.0)
				var uv: Array = vertex["uv"]
				if Vector2(u.dot(p), v.dot(p)).distance_to(Vector2(uv[0], uv[1])) > 0.00001:
					errors.append("actual imported affine UV roundtrip drift")
		var actual := mat.get_shader_parameter("object_normals") as Texture2D
		if actual == null or actual != normal_data:
			errors.append("normal data missing or replaced/zero")
			continue
		if mat.get_shader_parameter("atlas") != albedo:
			errors.append("albedo Texture2D identity changed")
		textures[albedo.get_instance_id()] = true
		textures[actual.get_instance_id()] = true
		var code := mat.shader.code
		if code.contains("AO =") or code.contains("unshaded") or code.contains("EMISSION"):
			errors.append("normal-only policy violated")
		var data_sampler := code.get_slice("uniform sampler2D object_normals", 1).get_slice(";", 0)
		if data_sampler.contains("source_color") or data_sampler.contains("hint_normal"):
			errors.append("normal data sampler gamma/normal reconstruction")
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED:
			errors.append("ground shadow disabled")
	var image := normal_data.get_image()
	if image.get_size() != Vector2i(1024, 384) or not image.has_mipmaps():
		errors.append("normal data size/mips")
	var axes := [
		Color8(255, 128, 128),
		Color8(0, 128, 128),
		Color8(128, 255, 128),
		Color8(128, 0, 128),
		Color8(128, 128, 255),
		Color8(128, 128, 0)
	]
	for i in range(axes.size()):
		if not image.get_pixel(1000 + i, 380).is_equal_approx(axes[i]):
			errors.append("raw XYZ sentinel/gamma drift: %d" % i)
	var config := ConfigFile.new()
	config.load("res://assets/hero/vegetation/normal_experiment/object_normals.png.import")
	if config.get_value("params", "compress/normal_map") != 2:
		errors.append("object XYZ must not use normal RGTC reconstruction")
	if config.get_value("params", "compress/mode") != 0:
		errors.append("normal data must be lossless")
	if textures.size() != 2:
		errors.append("expected2 actual Texture2D instances")
	for error in errors:
		push_error(error)
	if errors.is_empty():
		print("NORMAL_EXPERIMENT_IMPORT_OK textures=2 raw_XYZ_axes=6 mips=true ground_shadow=true")
	node.free()
	quit(0 if errors.is_empty() else 1)
