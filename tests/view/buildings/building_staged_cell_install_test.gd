extends GdUnitTestSuite
## Yol onayı sonrası kare sivrilmesi düzeltmesi (WLD-01; görünüm yalnız temsil): kamulaştırma gizlemesinde bir hücrenin
## kurulumu birim birim (modül, HLOD1 yüzey dilimi) kare dilimlerine bölünür; biten görünüm TEK ÇAĞRIDA kurulanla AYNI
## düğüm adları, MultiMesh tamponları ve HLOD1 köşe akışıdır. Sabit kare/süre yok: bütçe 0 -> çağrı başına en çok bir
## birim; eski hücre yalnız bitişte yer değiştirir.

var _kit: BuildingKit
var _world: WorldData


func before() -> void:
	_kit = BuildingTestSupport.kit()
	_world = BuildingTestSupport.flat_world(8000.0, 100.0, Rect2(), 15.0)


func _view(slice_verts: int = 0) -> BuildingView:
	var view: BuildingView = auto_free(BuildingView.new())
	add_child(view)
	var cfg := BuildingViewConfig.new()
	cfg.use_threads = false
	view.setup(_world, _kit, cfg)
	if slice_verts > 0:
		view.hlod1_slice_verts = slice_verts
	return view


func _cols() -> BuildingColumns:
	var a := _kit.module_index(BuildingTestSupport.MID_A)
	var b := _kit.module_index(BuildingTestSupport.HOUSE_B)
	var rows: Array = []
	for i in 10:
		rows.append({"m": a, "x": 500.0 + i * 40.0, "z": 500.0, "parcel": 1 + i})
		rows.append({"m": b, "x": 500.0 + i * 40.0, "z": 540.0, "parcel": 100 + i})
	rows.append({"m": a, "x": 2600.0, "z": 500.0, "parcel": 300})
	return BuildingTestSupport.columns(rows)


## Hücre düğümünün çocuk adları + MultiMesh tamponları + HLOD1 köşe/normal/renk akışı (yüzey sınırlarından bağımsız).
func _cell_signature(view: BuildingView, key: Vector2i) -> String:
	var node := view.cell_node(key)
	if node == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var names: Array[String] = []
	for child in node.get_children():
		names.append(String(child.name))
	ctx.update(",".join(names).to_utf8_buffer())
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			ctx.update(((child as MultiMeshInstance3D).multimesh.buffer).to_byte_array())
		elif child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				verts.append_array(arrays[Mesh.ARRAY_VERTEX])
				normals.append_array(arrays[Mesh.ARRAY_NORMAL])
				colors.append_array(arrays[Mesh.ARRAY_COLOR])
	ctx.update(verts.to_byte_array())
	ctx.update(normals.to_byte_array())
	ctx.update(colors.to_byte_array())
	return ctx.finish().hex_encode()


func _hlod1_surfaces(view: BuildingView, key: Vector2i) -> int:
	for child in view.cell_node(key).get_children():
		if child is MeshInstance3D and String(child.name) == "HLOD1":
			return (child as MeshInstance3D).mesh.get_surface_count()
	return 0


func test_zero_budget_installs_at_most_one_unit_per_call_and_equals_the_one_shot_cell() -> void:
	var cols := _cols()
	var staged := _view(3)   # çok küçük yüzey: HLOD1 birden çok dilim
	staged.set_columns(cols, 1)
	var oneshot := _view()
	oneshot.set_columns(cols, 1)
	var hidden := PackedInt32Array([1, 2, 3, 104])
	staged.set_parcels_hidden(hidden, true)
	oneshot.set_parcels_hidden(hidden, true)
	var old_cell := staged.cell_node(Vector2i(0, 0))
	var calls := 0
	var partial_seen := false
	while staged.pending_work() > 0 and calls < 2000:
		var rep := staged.pump_pending(0)
		calls += 1
		assert_int(int(rep["done"])).override_failure_message("bütçe 0: çağrı başına en çok bir birim").is_less_equal(1)
		if int(rep["done"]) == 0 and staged.pending_work() > 0 and staged.cell_node(Vector2i(0, 0)) == old_cell:
			partial_seen = true   # yarım hücre: eski düğüm yerinde
	oneshot.pump_pending(1 << 40)
	assert_int(oneshot.pending_work()).is_equal(0)
	assert_int(staged.pending_work()).is_equal(0)
	assert_bool(partial_seen).override_failure_message("hücre birden çok çağrıya yayılmalıydı").is_true()
	assert_object(staged.cell_node(Vector2i(0, 0))).is_not_same(old_cell)
	for key: Vector2i in oneshot.cell_keys():
		assert_str(_cell_signature(staged, key)).override_failure_message("hücre %s" % str(key)) \
				.is_equal(_cell_signature(oneshot, key))
	assert_int(staged.building_count()).is_equal(oneshot.building_count())
	assert_int(_hlod1_surfaces(staged, Vector2i(0, 0))).is_greater_equal(_hlod1_surfaces(oneshot, Vector2i(0, 0)))


func test_hiding_every_building_of_a_cell_while_it_is_half_built_drops_the_partial_cell() -> void:
	var cols := _cols()
	var view := _view()
	view.set_columns(cols, 1)
	view.set_parcels_hidden(PackedInt32Array([1]), true)
	view.pump_pending(0)   # (0,0) hücresi yarım kalır
	assert_int(view.pending_work()).is_greater(0)
	var rest := PackedInt32Array()
	for i in range(2, 11):
		rest.append(i)
	for i in 10:
		rest.append(100 + i)
	view.set_parcels_hidden(rest, true)   # hücredeki son yapılar da gizlendi
	var calls := 0
	while view.pending_work() > 0 and calls < 2000:
		view.pump_pending(0)
		calls += 1
	assert_int(view.pending_work()).is_equal(0)
	assert_object(view.cell_node(Vector2i(0, 0))).override_failure_message("yarım hücre geri gelmemeli").is_null()
	assert_int(view.building_count()).is_equal(1)   # yalnız 300 numaralı parselin yapısı kaldı
