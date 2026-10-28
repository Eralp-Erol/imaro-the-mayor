extends GdUnitTestSuite
## T-051 kısım 2 · Kent zemini maskesi: dolu parsel boyanır, boş uzak alan boyanmaz, çoğu dolu bloğun boş parseli
## boyanır, sanayi bayrağı G kanalına gider, deterministik; arazi malzemesine bağlanır (yeni malzeme yok).

const PARAMS := {"max_px": 256, "min_cell_m": 10.0, "grow_m": 2.0, "margin_m": 50.0, "block_fill_min": 0.5}


func _square(cx: float, cz: float, half: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx - half, cz - half), Vector2(cx + half, cz - half),
			Vector2(cx + half, cz + half), Vector2(cx - half, cz + half)])


func _net_with(parcels: Array) -> WorldNetwork:
	var net := WorldNetwork.new()
	for p: Array in parcels:
		var parcel := WorldParcel.new()
		parcel.id = int(p[0])
		parcel.block_id = int(p[1])
		parcel.outline = _square(float(p[2]), float(p[3]), 20.0)
		net.parcels[parcel.id] = parcel
	var by_block := {}
	for p: Array in parcels:
		if not by_block.has(p[1]):
			var block := WorldBlock.new()
			block.id = int(p[1])
			block.kind = WorldBlock.KIND_PARCELIZED
			net.blocks[block.id] = block
			by_block[p[1]] = block
		(by_block[p[1]] as WorldBlock).parcel_ids.append(int(p[0]))
	return net


func _cols(rows: Array) -> BuildingColumns:
	var cols := BuildingColumns.new()
	for r: Array in rows:
		cols.add(int(r[0]), 0, float(r[1]), float(r[2]), 0.0, 3, 0, 0, 0, 128, int(r[3]), BuildingColumns.ERA_MID)
	return cols


func _px(mask: Dictionary, x: float, z: float) -> Color:
	var origin: Vector2 = mask["origin"]
	var cell := float(mask["cell_m"])
	var image: Image = mask["image"]
	return image.get_pixel(int((x - origin.x) / cell), int((z - origin.y) / cell))


func test_filled_parcel_is_painted_and_far_area_is_not() -> void:
	var net := _net_with([[1, 1, 0.0, 0.0], [2, 2, 400.0, 0.0]])
	var mask := UrbanGroundMask.build(net, _cols([[1, 0.0, 0.0, 0]]), PARAMS)
	assert_bool(mask.is_empty()).is_false()
	assert_float(_px(mask, 0.0, 0.0).r).is_greater(0.9)
	# Parsel 2 yapısız ve bloğu boş: boyanmaz.
	assert_float(_px(mask, 400.0, 0.0).r).is_equal(0.0)
	assert_float(_px(mask, 200.0, 0.0).r).is_equal(0.0)


func test_vacant_parcel_in_mostly_filled_block_is_painted() -> void:
	var net := _net_with([[1, 1, 0.0, 0.0], [2, 1, 60.0, 0.0], [3, 1, 120.0, 0.0]])
	var mask := UrbanGroundMask.build(net, _cols([[1, 0.0, 0.0, 0], [2, 60.0, 0.0, 0]]), PARAMS)
	assert_float(_px(mask, 120.0, 0.0).r).is_greater(0.9)


func test_industrial_flag_goes_to_green_channel() -> void:
	var net := _net_with([[1, 1, 0.0, 0.0], [2, 2, 200.0, 0.0]])
	var mask := UrbanGroundMask.build(net, _cols([[1, 0.0, 0.0, 0], [2, 200.0, 0.0, BuildingColumns.FLAG_INDUSTRY]]),
			PARAMS)
	assert_float(_px(mask, 0.0, 0.0).g).is_equal(0.0)
	assert_float(_px(mask, 200.0, 0.0).g).is_greater(0.9)


func test_mask_is_deterministic_and_empty_without_buildings() -> void:
	var net := _net_with([[1, 1, 0.0, 0.0]])
	var cols := _cols([[1, 0.0, 0.0, 0]])
	var a := UrbanGroundMask.build(net, cols, PARAMS)
	var b := UrbanGroundMask.build(net, cols, PARAMS)
	assert_array((a["image"] as Image).get_data()).is_equal((b["image"] as Image).get_data())
	assert_bool(UrbanGroundMask.build(net, BuildingColumns.new(), PARAMS).is_empty()).is_true()


func test_view_applies_mask_to_the_shared_land_material_without_new_nodes() -> void:
	var world := WorldTestSupport.coarse(WorldTestSupport.control())
	var view: TerrainView = auto_free(TerrainView.new())
	view.chunk_cells = 32
	view.use_threads = false
	add_child(view)
	view.build(world)
	var children_before := view.get_child_count()
	var c := world.origin + world.size * 0.5
	var net := _net_with([[1, 1, c.x, c.y]])
	var stats := view.apply_urban_ground(net, _cols([[1, c.x, c.y, 0]]))
	assert_bool(stats.is_empty()).is_false()
	assert_int(view.get_child_count()).is_equal(children_before)
	var mat := (view.land_nodes()[0].mesh as ArrayMesh).surface_get_material(0) as ShaderMaterial
	assert_float((mat.get_shader_parameter("urban_rect") as Vector4).z).is_greater(0.0)
	assert_object(mat.get_shader_parameter("urban_tex")).is_not_null()


func test_look_data_has_urban_section_with_variant_weights_and_sidewalk() -> void:
	# T-062 A4: renkler kalktı (onaylı döşeme katmanları); parsel hash'i seçimi veri ağırlığıyla yapılır.
	var look := TerrainLook.from_file(TerrainLook.DATA_PATH)
	var u: Dictionary = look.data["urban"]
	var w: Dictionary = u["variants"]["residential"]
	assert_float(float(w["plaza"]) + float(w["dirt"]) + float(w["green"])).is_equal_approx(1.0, 0.0001)
	# yeşil payı bilinçli düşük (ağaç/peyzaj sonraki paket: B/C)
	assert_float(float(w["green"])).is_less_equal(0.25)
	var band: Array = u["sidewalk"]["band"]
	assert_float(float(band[0])).is_less(float(band[1]))
	assert_int(int(look.urban_mask_params()["max_px"])).is_between(512, 4096)
	assert_bool(look.urban_mask_params().has("variants")).is_true()


func test_variant_choice_is_a_pure_hash_of_the_id_and_follows_the_weights() -> void:
	var weights := {"plaza": 0.3, "dirt": 0.55, "green": 0.15}
	var counts := [0, 0, 0]
	for id in 4000:
		var a := UrbanGroundMask.variant_of(id, 6201, weights)
		assert_int(a).is_equal(UrbanGroundMask.variant_of(id, 6201, weights))   # aynı kimlik -> aynı seçim
		counts[a] += 1
	# Oranlar ağırlıkları izler (hash düzgün) ve her sonuç ortaya çıkar.
	assert_float(float(counts[UrbanGroundMask.VARIANT_PLAZA]) / 4000.0).is_equal_approx(0.3, 0.04)
	assert_float(float(counts[UrbanGroundMask.VARIANT_DIRT]) / 4000.0).is_equal_approx(0.55, 0.04)
	assert_float(float(counts[UrbanGroundMask.VARIANT_GREEN]) / 4000.0).is_equal_approx(0.15, 0.04)
	# Tohum seçimi değiştirir (negatif: sabit bir dönüş olamaz).
	var diff := 0
	for id in 200:
		if UrbanGroundMask.variant_of(id, 1, weights) != UrbanGroundMask.variant_of(id, 2, weights):
			diff += 1
	assert_int(diff).is_greater(20)
	# Ağırlık sıfırsa o seçim hiç çıkmaz.
	for id in 500:
		assert_int(UrbanGroundMask.variant_of(id, 6201, {"plaza": 0.0, "dirt": 1.0, "green": 0.0})).is_equal(
				UrbanGroundMask.VARIANT_DIRT)


func test_same_parcel_gets_the_same_ground_variant_in_the_mask_and_industrial_gets_none() -> void:
	var params := PARAMS.duplicate()
	params["variants"] = {"seed": 6201, "unit": "parcel", "residential": {"plaza": 0.5, "dirt": 0.0, "green": 0.5}}
	var net := _net_with([[1, 1, 0.0, 0.0], [2, 2, 200.0, 0.0], [3, 3, 400.0, 0.0]])
	var cols := _cols([[1, 0.0, 0.0, 0], [2, 200.0, 0.0, 0], [3, 400.0, 0.0, BuildingColumns.FLAG_INDUSTRY]])
	var a := UrbanGroundMask.build(net, cols, params)
	var b := UrbanGroundMask.build(net, cols, params)
	assert_array((a["image"] as Image).get_data()).is_equal((b["image"] as Image).get_data())
	# Her konut parseli tam bir seçim taşır: ya B (plaza) ya A (yeşil); sanayide ikisi de 0 (gravel).
	for x in [0.0, 200.0]:
		var px := _px(a, x, 0.0)
		assert_float(px.b + px.a).is_equal_approx(1.0, 0.001)
	var want1 := UrbanGroundMask.variant_of(1, 6201, params["variants"]["residential"])
	assert_float(_px(a, 0.0, 0.0).b).is_equal(1.0 if want1 == UrbanGroundMask.VARIANT_PLAZA else 0.0)
	var ind := _px(a, 400.0, 0.0)
	assert_float(ind.g).is_greater(0.9)
	assert_float(ind.b + ind.a).is_equal(0.0)
