class_name BuildingViewConfig
extends RefCounted
## BuildingView ayarları (T-012). Bunlar GÖRÜNÜM profil ayarlarıdır (ADR-0004: profil başına T-008/T-010 ölçümüyle
## yazılır); simülasyon bunları okumaz.

## LOD0/LOD1/HLOD1 chunk kenarı (m); kit spec §7.1: 1 km. Dünya origin'ine hizalanır.
var cell_m: float = 1000.0
## HLOD2 süper-chunk kenarı = cell_m x super_cells (spec §7.2: 4 x 4 km).
var super_cells: int = 4
var lod: BuildingLod = BuildingLod.new()
## Gölge (T-012 ölçüt 3): gölge DÜŞÜREN kademe `shadow_caster_lod`: 0 = LOD0 mesh'i düşürür (tam ayrıntı, gölge
## geçişi pahalı: sokak/yerel kareler ~+340k üçgen), 1 = LOD1 mesh'i YALNIZ-GÖLGE düğümü olarak düşürür (LOD0/LOD1
## görsel düğümleri gölge düşürmez; MultiMesh kaynağı LOD1 ile PAYLAŞILIR, ek bellek yok). Her iki halde gölge düşürme
## `lod0_end_m` (+ marjin) ile biter: "600 m ötesi LOD1'de kapalı" (art-director). HLOD'lar hiçbir zaman düşürmez
## (spec §7.2). `lod1_casts_shadow` ölçüm/deney içindir (LOD1 görsel düğümü de düşürür: gölge 600 m ötesinde AÇIK).
var cast_shadows: bool = true
var shadow_caster_lod: int = 1
var lod1_casts_shadow: bool = false
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
## HLOD1 renk kaydırma: PROXY köşe rengi `mat_kit_proxy` ile doğrudan okunur (sRGB yazılmış). Karşılaştırma ölçümü
## (`LOD1 <-> HLOD1`, K8) bunun gerekip gerekmediğini söyler; varsayılan: dönüşüm yok.
var proxy_colors_linear: bool = false
