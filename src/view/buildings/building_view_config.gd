class_name BuildingViewConfig
extends RefCounted
## BuildingView ayarları (T-012). Bunlar GÖRÜNÜM profil ayarlarıdır (ADR-0004: profil başına T-008/T-010 ölçümüyle
## yazılır); simülasyon bunları okumaz.

const HLOD1_PROXY := "proxy"
const HLOD1_BOX := "box"

## LOD0/LOD1/HLOD1 chunk kenarı (m); kit spec §7.1: 1 km. Dünya origin'ine hizalanır.
var cell_m: float = 1000.0
## HLOD2 süper-chunk kenarı = cell_m x super_cells (spec §7.2: 4 x 4 km).
var super_cells: int = 4
var lod: BuildingLod = BuildingLod.new()
## Görünüm kademeleri (T-062 A3): LOD0 kademesi = hero LOD1 mesh'i, LOD1 kademesi = hero PROXY (hero LOD0 çizilmez).
## Gölge (T-012 ölçüt 3): gölge DÜŞÜREN kademe `shadow_caster_lod`: 0 = LOD0 mesh'i düşürür (tam ayrıntı, gölge
## geçişi pahalı: sokak/yerel kareler ~+340k üçgen), 1 = LOD1 mesh'i YALNIZ-GÖLGE düğümü olarak düşürür (LOD0/LOD1
## görsel düğümleri gölge düşürmez; MultiMesh kaynağı LOD1 ile PAYLAŞILIR, ek bellek yok). Her iki halde gölge düşürme
## Görsel LOD0 menzilinden bağımsız gölge sonu: 700 m = 650 m eşik + 50 m marjin.
## Böylece K8 için uzatılan görsel LOD0, 600 m ötesinde LOD1 gölgesi kapalı kararını değiştirmez.
## HLOD'lar hiçbir zaman düşürmez. `lod1_casts_shadow` ölçüm/deney içindir (LOD1 görsel düğümü de gölge düşürür).
var cast_shadows: bool = true
var shadow_caster_lod: int = 1
var lod1_casts_shadow: bool = false
var shadow_end_m: float = 700.0
## Ayak izini kıyıdan bu kadar genişleterek su denetimi (m).
var coast_margin_m: float = 4.0
## HLOD2 kütle kümeleme ızgarası (m) ve yükseklik kademesi eşikleri (m); en yüksek `hlod2_keep_top_share` ayrı kutu.
var hlod2_cell_m: float = 96.0
var hlod2_tier_edges_m: Array[float] = [9.0, 18.0]
var hlod2_keep_top_share: float = 0.1
## true: kütle rengi alan ağırlıklı deterministik ÖRNEKLEME (kent tek renge inmez); false: alan ağırlıklı baskın.
var hlod2_sample_colors: bool = true
## Kademe anahtarları (ölçüm/deney): kapalı kademe hiç kurulmaz.
var build_lod0: bool = true
var build_lod1: bool = true
var build_hlod1: bool = true
var build_hlod2: bool = true
var use_threads: bool = true
## HLOD1 kaynağı (ADR-0006 §3.1): "proxy" = hero PROXY mesh'i (atlas renginden piştirilmiş), "box" = ayak izi kutusu.
## Renk her iki halde de modül PROXY atlasından yükleme anında piştirilir. Perf A/B içindir (A5).
var hlod1_source: String = HLOD1_PROXY
