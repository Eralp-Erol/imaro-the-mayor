class_name VegetationCellBuilder
extends RefCounted
## Hücre başına MultiMesh verisi (T-062 B1): SAF, deterministik. Tür başına bitişik satır aralığı ("koşu") bir
## MultiMeshInstance3D'nin örnekleridir; örnek dönüşümü sütunlardan (x, z, yaw, scale) ve `VegetationLayout.y`dan gelir.
## Örnek başına 12 float, satır öncelikli 3x4: `Basis(UP, yaw)` x düzgün ölçek (BuildingColumns ile AYNI yaw
## sözleşmesi).

const FLOATS_PER_INSTANCE := 12


## Hücre k içinde tür koşuları: Array[Vector3i](tür, başlangıç, bitiş), artan tür (sütunlar türe göre kümeli).
static func species_runs(cols: VegetationColumns, k: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var lo := cols.cell_start[k]
	var hi := cols.cell_start[k + 1]
	var i := lo
	while i < hi:
		var sp := cols.species[i]
		var j := i
		while j < hi and cols.species[j] == sp:
			j += 1
		out.append(Vector3i(sp, i, j))
		i = j
	return out


## [lo, hi) satırlarının tam tamponu (hücre yerel koordinatı: x/z `origin`e göre, y zemin - sink_m).
static func canonical_buffer(layout: VegetationLayout, lo: int, hi: int, origin: Vector2,
		sink_m: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize((hi - lo) * FLOATS_PER_INSTANCE)
	var o := 0
	var cols := layout.cols
	var masked := not layout.hidden.is_empty()
	for i in range(lo, hi):
		if masked and layout.hidden[i] != 0:
			continue   # yeni yol koridoru: örnek çizilmez (sütun duruyor)
		_write(buf, o, cols.x[i] - origin.x, layout.y[i] - sink_m, cols.z[i] - origin.y, cols.yaw[i], cols.scale[i])
		o += FLOATS_PER_INSTANCE
	buf.resize(o)
	return buf


## [lo, hi) satırlarını kameraya uzaklığa göre kademelere böler (örnek başına). Dönüş:
## {"buffers": Array[PackedFloat32Array](LOD0, LOD1, PROXY), "counts": PackedInt32Array(LOD0, LOD1, PROXY, NONE)}.
## Kademe kuralı `VegetationLod.tier_for` ile BİREBİR aynıdır (kareli mesafe kıyası; d < sınır).
static func partition(layout: VegetationLayout, lo: int, hi: int, origin: Vector2, sink_m: float, cam: Vector3,
		lod: VegetationLod, has_proxy: bool) -> Dictionary:
	var cols := layout.cols
	var l0 := lod.lod0_end_m * lod.lod0_end_m
	var l1 := lod.lod1_end_m * lod.lod1_end_m
	var lp := lod.palm_proxy_end_m * lod.palm_proxy_end_m
	var cap := (hi - lo) * FLOATS_PER_INSTANCE
	var b0 := PackedFloat32Array()
	var b1 := PackedFloat32Array()
	var bp := PackedFloat32Array()
	b0.resize(cap)
	b1.resize(cap)
	bp.resize(cap)
	var counts := PackedInt32Array([0, 0, 0, 0])
	var masked := not layout.hidden.is_empty()
	for i in range(lo, hi):
		if masked and layout.hidden[i] != 0:
			continue
		var dx := cols.x[i] - cam.x
		var dy := layout.y[i] - cam.y
		var dz := cols.z[i] - cam.z
		var d2 := dx * dx + dy * dy + dz * dz
		var lx := cols.x[i] - origin.x
		var ly := layout.y[i] - sink_m
		var lz := cols.z[i] - origin.y
		if d2 < l0:
			_write(b0, counts[0] * FLOATS_PER_INSTANCE, lx, ly, lz, cols.yaw[i], cols.scale[i])
			counts[0] += 1
		elif d2 < l1:
			_write(b1, counts[1] * FLOATS_PER_INSTANCE, lx, ly, lz, cols.yaw[i], cols.scale[i])
			counts[1] += 1
		elif has_proxy and d2 < lp:
			_write(bp, counts[2] * FLOATS_PER_INSTANCE, lx, ly, lz, cols.yaw[i], cols.scale[i])
			counts[2] += 1
		else:
			counts[3] += 1
	b0.resize(counts[0] * FLOATS_PER_INSTANCE)
	b1.resize(counts[1] * FLOATS_PER_INSTANCE)
	bp.resize(counts[2] * FLOATS_PER_INSTANCE)
	var bufs: Array[PackedFloat32Array] = [b0, b1, bp]
	return {"buffers": bufs, "counts": counts}


static func _write(buf: PackedFloat32Array, o: int, lx: float, ly: float, lz: float, yaw: float, sc: float) -> void:
	var c := cos(yaw)
	var s := sin(yaw)
	buf[o] = c * sc
	buf[o + 1] = 0.0
	buf[o + 2] = s * sc
	buf[o + 3] = lx
	buf[o + 4] = 0.0
	buf[o + 5] = sc
	buf[o + 6] = 0.0
	buf[o + 7] = ly
	buf[o + 8] = -s * sc
	buf[o + 9] = 0.0
	buf[o + 10] = c * sc
	buf[o + 11] = lz
