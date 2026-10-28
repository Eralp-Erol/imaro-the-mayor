extends GdUnitTestSuite
## T-062 B1 · hücre MultiMesh verisi: görünüm B0 sütunlarıyla BİRE BİR; örnek başına kademe `VegetationLod` ile aynı;
## aynı girdi -> aynı tampon baytları (determinizm); yerleştirme zemin yüksekliğinden.


func test_layout_is_one_to_one_with_the_b0_columns() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cols := lay.cols
	assert_int(lay.y.size()).is_equal(cols.count)
	assert_int(lay.cell_count()).is_equal(cols.cell_keys.size())
	var world := VegetationViewTestSupport.world()
	for i in [0, cols.count / 2, cols.count - 1]:
		assert_float(lay.y[i]).is_equal_approx(world.height_at(cols.x[i], cols.z[i]), 0.0001)
	# her hücrenin y aralığı örneklerini kapsar
	for k in lay.cell_count():
		for i in range(cols.cell_start[k], cols.cell_start[k + 1]):
			assert_bool(lay.y[i] >= lay.cell_ymin[k] - 0.0001 and lay.y[i] <= lay.cell_ymax[k] + 0.0001).is_true()


func test_species_runs_cover_every_row_exactly_once_per_cell() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cols := lay.cols
	var total := 0
	var per_species := PackedInt32Array()
	per_species.resize(VegetationViewTestSupport.species().size())
	for k in lay.cell_count():
		var next := cols.cell_start[k]
		var last_sp := -1
		for run in VegetationCellBuilder.species_runs(cols, k):
			assert_int(run.y).is_equal(next)        # bitişik, boşluksuz
			assert_bool(run.x > last_sp).is_true()  # artan, tekil tür
			for i in range(run.y, run.z):
				assert_int(cols.species[i]).is_equal(run.x)
			total += run.z - run.y
			per_species[run.x] += run.z - run.y
			next = run.z
			last_sp = run.x
		assert_int(next).is_equal(cols.cell_start[k + 1])
	assert_int(total).is_equal(cols.count)
	assert_array(Array(per_species)).is_equal(Array(cols.species_counts()))


func test_canonical_buffer_encodes_position_yaw_scale_and_is_deterministic() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cols := lay.cols
	var k := lay.index_of_key(cols.peak_cell().y)
	var lo := cols.cell_start[k]
	var hi := mini(lo + 40, cols.cell_start[k + 1])
	var origin := lay.cell_origin(cols.cell_keys[k])
	var a := VegetationCellBuilder.canonical_buffer(lay, lo, hi, origin, 0.12)
	var b := VegetationCellBuilder.canonical_buffer(lay, lo, hi, origin, 0.12)
	assert_int(a.size()).is_equal((hi - lo) * VegetationCellBuilder.FLOATS_PER_INSTANCE)
	assert_array(Array(a.to_byte_array())).is_equal(Array(b.to_byte_array()))
	for n in hi - lo:
		var i := lo + n
		var o := n * VegetationCellBuilder.FLOATS_PER_INSTANCE
		# Godot MultiMesh: satır öncelikli 3x4 = Transform3D(Basis(UP, yaw) * ölçek, konum)
		var t := Transform3D(Basis(Vector3.UP, cols.yaw[i]) * Basis.from_scale(Vector3.ONE * cols.scale[i]),
				Vector3(cols.x[i] - origin.x, lay.y[i] - 0.12, cols.z[i] - origin.y))
		var expect := [t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x, t.basis.x.y, t.basis.y.y, t.basis.z.y,
				t.origin.y, t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z]
		for f in 12:
			assert_float(a[o + f]).is_equal_approx(expect[f], 0.0002)


func test_partition_matches_the_lod_rule_per_instance_at_the_boundaries() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cols := lay.cols
	var lod := VegetationLod.from_config(VegetationViewTestSupport.config())
	var k := lay.index_of_key(cols.peak_cell().y)
	var lo := cols.cell_start[k]
	var hi := cols.cell_start[k + 1]
	var origin := lay.cell_origin(cols.cell_keys[k])
	# kamera hücrenin bir köşesinde: aynı hücrede LOD0 ve LOD1 örnekleri birlikte (köşegen 362 m < 400 m)
	var cam := Vector3(origin.x, lay.cell_ymin[k] + 10.0, origin.y)
	for has_proxy in [false, true]:
		var part := VegetationCellBuilder.partition(lay, lo, hi, origin, 0.12, cam, lod, has_proxy)
		var expect := PackedInt32Array([0, 0, 0, 0])
		for i in range(lo, hi):
			var d := Vector3(cols.x[i], lay.y[i], cols.z[i]).distance_to(cam)
			expect[lod.tier_for(d, has_proxy)] += 1
		assert_array(Array(part["counts"])).is_equal(Array(expect))
		var counts: PackedInt32Array = part["counts"]
		for t in 3:
			assert_int((part["buffers"][t] as PackedFloat32Array).size()).is_equal(
					counts[t] * VegetationCellBuilder.FLOATS_PER_INSTANCE)
		assert_int(counts[0] + counts[1] + counts[2] + counts[3]).is_equal(hi - lo)
	# karışık gerçekten oluştu (test anlamlı): hücrede LOD1 örneği var
	var part2 := VegetationCellBuilder.partition(lay, lo, hi, origin, 0.12, cam, lod, false)
	var c2: PackedInt32Array = part2["counts"]
	assert_bool(c2[1] > 0).is_true()


func test_partition_is_deterministic() -> void:
	var lay := VegetationViewTestSupport.layout()
	var lod := VegetationLod.from_config(VegetationViewTestSupport.config())
	var k := lay.index_of_key(lay.cols.peak_cell().y)
	var cam := VegetationViewTestSupport.camera_over_peak(5.0)
	var origin := lay.cell_origin(lay.cols.cell_keys[k])
	var lo := lay.cols.cell_start[k]
	var hi := lay.cols.cell_start[k + 1]
	var a := VegetationCellBuilder.partition(lay, lo, hi, origin, 0.12, cam, lod, false)
	var b := VegetationCellBuilder.partition(lay, lo, hi, origin, 0.12, cam, lod, false)
	for t in 3:
		assert_array(Array((a["buffers"][t] as PackedFloat32Array).to_byte_array())).is_equal(
				Array((b["buffers"][t] as PackedFloat32Array).to_byte_array()))
