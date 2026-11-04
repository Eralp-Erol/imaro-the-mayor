class_name NetworkFootprint
extends RefCounted
## Kentsel doku ayak izi (T-011): bir bölgenin yerleşim kümesi (elips) veya T0 saha çıkıntısı (iki saha arasındaki
## şerit).
## Kontrol verisinden (`network.json` fabrics) ve WorldData'dan türetilir; koordinat gömülü değildir. Saf veri.

const SHAPE_ELLIPSE := &"ellipse"
const SHAPE_CAPSULE := &"capsule"

var id: StringName = &""
## Bu ayak izinin bağlı olduğu çalışma bölgesi kodu (boş olabilir).
var region_code: StringName = &""
var template: StringName = &""
var shape: StringName = SHAPE_ELLIPSE
## Elips: merkez, yarıçaplar (m), dönüş (rad).
var center: Vector2 = Vector2.ZERO
var radii: Vector2 = Vector2.ONE
var rotation_rad: float = 0.0
## Şerit (capsule): iki uç (m) ve yarı genişlik (m).
var seg_a: Vector2 = Vector2.ZERO
var seg_b: Vector2 = Vector2.ZERO
var pad: float = 1.0
## Organik sınır alanı (T-049 A; `NetworkShape` pişirir): ölçek çarpanı raster'ı (w x w), sol-üst köşe, hücre boyu.
## Boşsa saf elips. `norm_dist = elips_uzaklığı / warp_at(p)`.
var warp: PackedFloat32Array = PackedFloat32Array()
var warp_origin: Vector2 = Vector2.ZERO
var warp_cell: float = 80.0
var warp_size: int = 0
## Izgara (lattice) parametreleri: network.json fabrics[].lattice (derin kopya).
var lattice: Dictionary = {}


## Normalize uzaklık: ≤ 1 içeride. `inflate_m` ayak izini her yönde bu kadar büyütür.
func norm_dist(p: Vector2, inflate_m: float = 0.0) -> float:
	if shape == SHAPE_CAPSULE:
		return NetworkGeometry.distance_point_segment(p, seg_a, seg_b) / maxf(pad + inflate_m, 1.0)
	var d := p - center
	var c := cos(rotation_rad)
	var s := sin(rotation_rad)
	var ux := (d.x * c + d.y * s) / maxf(radii.x + inflate_m, 1.0)
	var uy := (-d.x * s + d.y * c) / maxf(radii.y + inflate_m, 1.0)
	var e := sqrt(ux * ux + uy * uy)
	if warp_size > 0:
		return e / warp_at(p)
	return e


## Pişirilmiş ölçek alanı (bilineer); raster dışı 1.0 (raster ayak izi erişimini kapsar).
func warp_at(p: Vector2) -> float:
	var fx := (p.x - warp_origin.x) / warp_cell
	var fy := (p.y - warp_origin.y) / warp_cell
	var last := float(warp_size - 1)
	if fx < 0.0 or fy < 0.0 or fx > last or fy > last:
		return 1.0
	var i0 := mini(int(fx), warp_size - 2)
	var j0 := mini(int(fy), warp_size - 2)
	var tx := fx - float(i0)
	var ty := fy - float(j0)
	var k := j0 * warp_size + i0
	var top := lerpf(warp[k], warp[k + 1], tx)
	var bottom := lerpf(warp[k + warp_size], warp[k + warp_size + 1], tx)
	return lerpf(top, bottom, ty)


func set_warp(grid: PackedFloat32Array, origin: Vector2, cell: float, size: int) -> void:
	warp = grid
	warp_origin = origin
	warp_cell = cell
	warp_size = size


func contains(p: Vector2, inflate_m: float = 0.0) -> bool:
	return norm_dist(p, inflate_m) <= 1.0


func bounds() -> Rect2:
	if shape == SHAPE_CAPSULE:
		var lo := Vector2(minf(seg_a.x, seg_b.x), minf(seg_a.y, seg_b.y)) - Vector2(pad, pad)
		var hi := Vector2(maxf(seg_a.x, seg_b.x), maxf(seg_a.y, seg_b.y)) + Vector2(pad, pad)
		return Rect2(lo, hi - lo)
	if warp_size > 0:
		return Rect2(warp_origin, Vector2.ONE * warp_cell * float(warp_size - 1))
	var r := maxf(radii.x, radii.y)
	return Rect2(center - Vector2(r, r), Vector2(2.0 * r, 2.0 * r))


func state_row() -> Array:
	return [String(id), String(region_code), String(template), center.x, center.y, radii.x, radii.y, pad]
