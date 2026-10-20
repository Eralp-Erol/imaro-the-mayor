class_name BuildingCellData
extends RefCounted
## Bir chunk'ın (hücre) render VERİSİ (T-012): düğüm/Mesh nesnesi içermez, iş parçacığında üretilir. Düğümleri
## BuildingView ana iş parçacığında kurar. Mesh verisi render'dan ayrıdır (başsız test edilir).

var key: Vector2i = Vector2i.ZERO
## Hücre köşesi (dünya x, z); örnek dönüşümleri bu origin'e GÖRELİ (32-bit hassasiyet).
var origin: Vector2 = Vector2.ZERO
## Çizilen modüller (sıralı) ve modül başına örnek sayısı / MultiMesh tamponu (örnek başına 16 float:
## 3x4 dönüşüm satırları + 4 özel veri).
var modules: PackedInt32Array = PackedInt32Array()
var counts: PackedInt32Array = PackedInt32Array()
var buffers: Array[PackedFloat32Array] = []
## Çizilen yapıların sütun indeksleri (hücre sırası), hücre içi sıra numaraları (`kept_ord`: hücre içeriği
## değişmediyse sütun indeksleri kayabilir -> `rebind` ile yeniden bağlanır) ve taban yükseklikleri.
var kept: PackedInt32Array = PackedInt32Array()
var kept_ord: PackedInt32Array = PackedInt32Array()
var base_y: PackedFloat32Array = PackedFloat32Array()
## Su/dünya dışı nedeniyle atılan yapı sayısı.
var dropped: int = 0
var lod0_tris: int = 0
var lod1_tris: int = 0
## HLOD1: birleştirilmiş PROXY mesh (hücre origin'ine göre).
var hlod1_vertices: PackedVector3Array = PackedVector3Array()
var hlod1_normals: PackedVector3Array = PackedVector3Array()
var hlod1_colors: PackedColorArray = PackedColorArray()


## Hücre içeriği aynıyken sütun indeksleri değiştiyse (başka hücrede ekleme/silme) yeni plana bağlar.
func rebind(plan: BuildingChunkPlan) -> void:
	var idx := plan.indices(key)
	var out := PackedInt32Array()
	for o in kept_ord:
		out.append(idx[o])
	kept = out


func instance_count() -> int:
	return kept.size()


func hlod1_triangles() -> int:
	return hlod1_vertices.size() / 3


## Mesh tamponlarını bırakır (düğümler kurulduktan sonra bellek); yerleşim özeti (kept/base_y) kalır.
func release_geometry() -> void:
	buffers = []
	hlod1_vertices = PackedVector3Array()
	hlod1_normals = PackedVector3Array()
	hlod1_colors = PackedColorArray()
