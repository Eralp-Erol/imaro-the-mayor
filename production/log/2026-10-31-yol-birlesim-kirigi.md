# Yol birleşim kırığı / kaması (2026-10-31)

Şikâyet: oyuncunun çizdiği yeni yol eski yola bağlandığı noktada görsel kırık/kama. Yalnız görünüm (`src/view/roads/**`); sim/ağ/dünya, UI, playable değişmedi (ağ `graph_hash` testle korunuyor).

## Yakalama (gerçek runtime, pencereli, bu Intel Mac / AMD Radeon Pro 560X, OpenGL Compatibility)
`tools/godot/junction_probe.gd`: gerçek Ismeral dünyasında oyuncunun çizim yoluyla (`RoadDraftCheck.apply` -> planarizer) T (90/60/35 derece; yerel/toplayıcı/arterial üstüne), uçtan uca (oyuncu yolunun serbest ucundan düz/+25/-40 derece devam) ve iki yolu birbirine bağlayan yol çizer; üst ve eğik görünüm PNG.
Görüntüler (repoda değil): `/private/tmp/claude-501/junction_screens/before_*.png` ve `after_*.png` (10 senaryo x üst/eğik).
En açık çiftler: `*_02_t35_local_on_collector_top`, `*_05_end_to_end_turn0_top`, `*_06_end_to_end_turn25_top`, `*_04_t90_local_on_arterial_oblique`, `*_08_bridge_two_roads_top`.

## Kök neden (görüldü + ölçüldü)
`RoadChunkPlan._add_node` düğüm başına TEK kırpma mesafesi hesaplıyordu: en geniş yarı genişlik ile her kol çifti için `yarı/tan(açı/2)`'nin en büyüğü; `RoadMeshBuilder._junction` kolların uç köşelerinin konveks zarfını dolgu yapıyordu. Sonuçlar:
1. Tek dar açılı çift (T'nin 35 derecelik kolu) düğümdeki TÜM kolları aynı büyük mesafeye kırpıyor -> dev kama dolgu (35 derecelik T'de ~286 m2 fazla alan; 80x80 m kutuda ideal yol alanının ~%20'si).
2. Düz geçen yolun (T'de karşı kenar; uçtan uca devamda iki kenar) kaldırımı kavşak dolgusunda (kaldırımsız) kesiliyordu: düz devamda bile ~15 m kaldırım kopması, çünkü kırpma >= yarı genişlik her düğümde uygulanıyordu.
3. Farklı genişlik/sınıfta kollarda zarf eğik pah kamaları.

## Düzeltme (yalnız görünüm)
- Yeni `src/view/roads/road_junction.gd` (`RoadJunction`): kırpma KOL ve YAN başına. Her kolun bir yan çizgisi, açısal komşusunun bakan yan çizgisiyle kesiştiği noktaya (P) kadar kırpılır (mitre; `s=(h_a cos g + h_b)/sin g`). Komşuyla > 170 derece yapan yan kırpılmaz. Dolgu çokgeni = kolların uç köşeleri açı sırasıyla (+ dışbükey köşede mitre; basit değilse konveks zarfa düşer).
- `road_chunk_plan.gd`: `arm_trims[düğüm][kenar] = Vector2(sağ, sol)`; `trims[düğüm]` = en büyük kol kırpması.
- `road_mesh_builder.gd`: şerit uçları eğik (sağ/sol kırpması farklıysa); küçük fark ilk/son parçanın köşesine gömülür (ek poligon yok), büyük fark ayrı yamuk parça; dolgu çokgeni dejenere ise (düz devam) hiç üretilmez; `_behind` eğik kesite göre; dolgu içbükeyse `concave` yolu.
- README güncellendi.

## Test
`tests/view/roads/road_junction_geometry_test.gd` (7 test, sentetik düz dünya): 0,5 m ızgarada ideal yol birleşimi (merkezden çıkan dikdörtgenler) ile mesh karşılaştırılır: kama (fazla alan) ve delik < ideal alanın %1'i, çift yüzey yok (kenar toleranslı), tüm normaller yukarı (ters sarım yok); T 90/60/35/20/-35/-90, arterial üstü dar kol, 4 yollu (farklı genişlik), uçtan uca kıvrım, metro, üçgen bütçesi (<= düzeltme öncesi 58), düz devamda dolgu/kırpma yok ve T'de geçiş yolunun karşı kenarı kırpılmıyor. `road_edit_sync_test` plan eşitliğine `arm_trims` eklendi.
Kırmızı-yeşil: eski `road_mesh_builder/road_chunk_plan` ile yeni suite KIRMIZI (T/arterial/metro testlerinde kama 37-286 m2 > eşik ~15 m2); yeni kodla 7/7 yeşil.

## Ölçümler (bu Intel Mac, başsız; iPad sayısı DEĞİL)
Gerçek Ismeral yol ağı `RoadView.build`, 3 koşunun en iyisi:
| | önce | sonra |
|---|---|---|
| near üçgen | 126.873 | 127.439 (+%0,4) |
| metro üçgen | 81.564 | 78.878 (-%3,3) |
| kurulum süresi | 2,32 s | 2,12 s |
| şerit / chunk | 7191 / 97 | 7191 / 97 |
Draw call: chunk başına mesh sayısı değişmedi (yeni mesh/malzeme yok); GPU kare süresi ölçülmedi.

## Doğrulanmış
- `tests/view` tümü: 436 test, 0 hata (gdunit, başsız). `gdlint` (gdtoolkit 4.5.0) src/view/roads, tests/view/roads, junction_probe: temiz.
- Önce/sonra gerçek pencereli yakalama ve GÖRÜLDÜ: T 90/60/35, arterial, uçtan uca (düz/+25/-40), iki yolu bağlayan yol: dev kama yok, geçiş yolunun karşı kaldırımı kesintisiz, uçtan uca devamda kaldırım kopması yok.

## Varsayılan / test edilmemiş
- `verify quick/full` KOŞTURULMADI (talimat). Playable demosunda uçtan uca elle çizim denenmedi; `RoadEditSync` artımlı yol testle (plan eşitliği) kapsandı, gerçek çizim akışı pencereli olarak denenmedi.
- iPad/cihaz kare süresi ve draw call sayısı ölçülmedi; yalnız bu Mac'te mesh kurulum süresi ve üçgen sayısı.
- Bükülme/çatalın dış köşesi için mitre limiti (3x yarı genişlik) ve 170/190 derece eşikleri sezgisel; keskin dönüşlerde (>150 derece) pah kalır.

## Kalan görsel kusurlar (bilerek bırakıldı; kapsam dışı ya da karar gerektirir)
1. Kavşak dolgusunda kaldırım yok (T-062 A4 tasarımı): mitre noktalarında (T çatalı, bükülme dış köşesi, dar açı çatalı) ~1-2 m'lik kaldırım dişi/çentik. Çözüm (kaldırımı dolguya taşımak) kendi başına bir shader/UV işi.
2. Doku dikişi (ASIL göze batan kalan şey, görünüm ama bu işin kapsamı dışı): aşınmış/yeni asfalt seçimi KENAR KİMLİĞİ hash'i ile (`RoadStyle.is_worn`). Oyuncu yolu mevcut kenarı bölünce yarım kenarlar farklı kimlik alır ve aşınma durumu birleşim noktasında aniden değişebilir (T'de eski yolun ortasında doku sıçraması; kavşak dolgusu baskın kenarın rengini alır). Kalıcı çözüm: aşınmayı kenar kimliği yerine konuma/koridora bağlamak (sanat/görünüm kararı) ya da bölünen yarımların kimliği korumasını sağlamak (world/sim, bu görevde dokunulmadı). Öneri: `design-director`/`art-director` ile konuşulsun.
