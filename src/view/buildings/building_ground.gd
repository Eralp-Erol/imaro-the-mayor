class_name BuildingGround
extends RefCounted
## Yapı ayak izinin zemin oturması (T-012 ölçüt 1): yükseklik `WorldData.height_at`'ten, su üstüne taşma yok.
## Saf ve iş parçacığı güvenli (yalnız WorldData okur). Yapı tabanını EN DÜŞÜK örnek yüksekliğine oturtur (havada kalma
## yok; yüksek taraf temel eteğine gömülür, kit spec §2.1: 2,5 m). Örnek noktaları: merkez + 4 köşe + 4 kenar ortası.
##
## Dönüş `NAN` = ayak izi su üstünde/dünya dışında (çizilmez). `coast_margin_m`: ayak izi her yönde bu kadar
## genişletilmiş halkada da su denetlenir (arazi mesh'i bilineer yükseklikten hücre basamağıyla ayrışır; T-001c'ye
## kadar).

const SINK_M := 0.2
const SAMPLES: Array[float] = [-1.0, 0.0, 1.0]


## Ayak izi (yarı genişlik hw, yarı derinlik hd; yerel +Z cephe) için taban yüksekliği ya da NAN.
static func base_y(world: WorldData, x: float, z: float, yaw: float, hw: float, hd: float,
		coast_margin_m: float = 0.0) -> float:
	var c := cos(yaw)
	var s := sin(yaw)
	var low := INF
	for sx in SAMPLES:
		for sz in SAMPLES:
			var h := _sample(world, x, z, c, s, sx * hw, sz * hd)
			if is_nan(h):
				return NAN
			low = minf(low, h)
			if coast_margin_m > 0.0:
				var hm := _sample(world, x, z, c, s, sx * (hw + coast_margin_m), sz * (hd + coast_margin_m))
				if is_nan(hm):
					return NAN
	return low - SINK_M


## Yerel (lx, lz) noktasının dünya yüksekliği; su ya da dünya dışıysa NAN.
static func _sample(world: WorldData, x: float, z: float, c: float, s: float, lx: float, lz: float) -> float:
	# Basis(UP, yaw) satırları: x' = lx*c + lz*s ; z' = -lx*s + lz*c
	var wx := x + lx * c + lz * s
	var wz := z - lx * s + lz * c
	if not world.contains(wx, wz):
		return NAN
	var h := world.height_at(wx, wz)
	return NAN if h < world.sea_level else h
