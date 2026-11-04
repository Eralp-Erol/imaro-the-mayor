class_name NetworkLatticeFrame
extends RefCounted
## Sokak ızgarasının koordinat çerçevesi (T-049 A2): (i, j) ızgara indeksi -> dünya konumu. Düz ızgara (ref + u*i*bu +
## v*j*bv) "tek yönlü, dümdüz blok" görünümü verir; çerçeve iki bükülme ekler (veri: network.json `organic` bend):
##   - twist: merkezden uzaklaştıkça ızgarayı `deg` kadar döndürür (smoothstep r0_m..r1_m): çekirdek sokakları
##     eğik/yay, çevre ızgarası farklı yönde olur (eski çekirdek + sonradan eklenen mahalle).
##   - disp: düşük frekanslı, tohumlu vektör gürültüsü (amp_m, cell_m): sokaklar dümdüz doğru olmaktan çıkar.
## Tohum `layout_seed`'ten gelir (topoloji dünya tohumundan bağımsız kalır). Saf; Node/Time/OS yok. Koordinat gömme yok.

var ref: Vector2 = Vector2.ZERO
var u: Vector2 = Vector2.RIGHT
var v: Vector2 = Vector2.DOWN
var bu: float = 100.0
var bv: float = 100.0
var twist_rad: float = 0.0
var twist_r0: float = 0.0
var twist_r1: float = 1.0
var disp_amp: float = 0.0
var disp_cell: float = 600.0
var disp_seed: int = 0


static func create(ref_pos: Vector2, angle: float, block_u: float, block_v: float, bend: Dictionary,
		seed_hash: int) -> NetworkLatticeFrame:
	var f := NetworkLatticeFrame.new()
	f.ref = ref_pos
	f.u = Vector2.from_angle(angle)
	f.v = Vector2(-f.u.y, f.u.x)
	f.bu = block_u
	f.bv = block_v
	f.disp_seed = seed_hash
	var tw: Dictionary = bend.get("twist", {})
	f.twist_rad = deg_to_rad(float(tw.get("deg", 0.0)))
	f.twist_r0 = float(tw.get("r0_m", 0.0))
	f.twist_r1 = maxf(float(tw.get("r1_m", 1.0)), f.twist_r0 + 1.0)
	var dp: Dictionary = bend.get("disp", {})
	f.disp_amp = float(dp.get("amp_m", 0.0))
	f.disp_cell = float(dp.get("cell_m", 600.0))
	return f


## Izgara indeksinin (bükülmüş) dünya konumu.
func point(i: int, j: int) -> Vector2:
	return bend(ref + u * (float(i) * bu) + v * (float(j) * bv))


## Düz ızgara konumunu bükülmüş konuma çevirir.
func bend(q: Vector2) -> Vector2:
	var p := q
	if twist_rad != 0.0:
		var rel := q - ref
		p = ref + rel.rotated(twist_rad * smoothstep(twist_r0, twist_r1, rel.length()))
	if disp_amp > 0.0:
		p += Vector2(NetworkNoise.value(disp_seed, q, disp_cell),
				NetworkNoise.value((disp_seed + 7919) & 0xFFFFFFFF, q, disp_cell)) * disp_amp
	return p


## Bükülmenin (ham ızgara konumuna göre) en çok kaydırabileceği uzaklık; indeks aralığını genişletmek için.
func max_shift(radius: float) -> float:
	return 2.0 * radius * absf(sin(twist_rad * 0.5)) + disp_amp * 1.5
