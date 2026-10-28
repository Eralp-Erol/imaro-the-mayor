# Yol görünümü (T-048)

`RoadView.build(network)` yalnız `mode() == road` kenarlarını okur; kapalı yolun fiziksel yüzeyi kalır.
`layer` taban/delta kaynağıdır, yükseklik katı değildir. Dünya/ağ/sim/kayıt değiştirilmez.

`data/view/road_style.json` geçici sanat verisidir. Sınıf yüzeyi (onaylı asfalt/çakıl katmanı kimlikleri) ve genişlik
katsayısı buradadır; varsayılan katsayı 1, ağın parsel cephesini belirleyen `edge.width` koridorunu korur.

**T-062 A4 (yüzey):** yollar `art/shaders/road_surface.gdshader` ShaderMaterial'iyle çizilir; arazi ile AYNI onaylı
`Texture2DArray`'i (`GroundLayerSet`, `LibraryGate` kimlikleri) dünya-xz UV ile örnekler. Sınıf başına taban/eskimiş
katman ve eskimiş payı veridedir; seçim kenar kimliği hash'iyle (`ViewHash`, deterministik). Köşe rengi yüzey kodudur
(R katman indeksi, G parlaklık, B kaldırım bandı m/8); köşe UV'si (eksene yanal ofset, yarım genişlik) kesit kenarında
`sidewalk_cobble` kaldırımı + koyu bordürü shader'da çizer: ek geometri/draw call yok. Kavşak dolgusunda kaldırım yok.
Şerit ekseni düğüm konumlarıdır; bina yönü/cephe verisi yeniden yorumlanmaz.

`chunk_m` (veri: `road_style.json`, şimdi 2 km; T-049 perf'te 1 km'den çıkarıldı) başına yakın ve metro meshleri bir kez kurulur. Yakın görünüm ilçe/sokakta gerçek genişliktedir;
metro daha ince ve daha seyrek segmentlidir. Godot mesafe görünürlüğü seçer; kare başına script yoktur.
Arazi üçgenlerine kırpma (TerrainMeshBuilder köşegeni, stride=1) yüzeyin içine gömülmeyi engeller.
Kırpma Geometry2D yerine hücre ızgarası + görünür köşegen boyunca yarım-düzlem bölmesidir; yükseklik çokgenin
düştüğü arazi üçgeninin düzleminden gelir. Yalnız kavşak dolgusundan çıkan (içbükey olabilen) parçalar ve dünya
sınırı Geometry2D'ye düşer. Kavşak dolgusu, şeridin uç çizgisinin gerisinde kalıyorsa (olağan kavşak) hiç kırpılmaz.
Köşe ve üçgen içi yükseklik görünür arazi düzlemi + veri ofsetidir; bilineer `height_at` ile eğri hücrelerde
kasıtlı olarak farklıdır. `--stride` arazi deneyi >1 bu görünümün kapsamı dışındadır.

T-042 çağıranı değişiklikten önce `plan()` sonucunu saklar. Değişiklikten sonra `RoadChunkPlan.build(net, style)`
ile yeni indeksi çıkarır. Eklenen/silinen/taşınan kenarların **eski ve yeni `edge_keys`** birleşimine,
uç düğümlerin eski/yeni `junction_keys` ve kavşak trimi etkilenen komşu kenarların `edge_keys` anahtarlarını ekler.
Bu birleşimi `rebuild_chunks(keys)` çağrısına verir. Eski plan geçerliliğini korur; yalnız verilen chunkların
mesh/düğüm kaynakları değiştirilir. İndeks yenileme O(ağ), mesh yenileme yalnız istenen chunklar içindir.
Silinen son kenar chunk düğümünü de kaldırır. Delta sinyal bağlaması T-042'ye aittir.

**Kurulum süresi (T-048 sonrası perf):** chunk verisi (yakın + metro) saf fonksiyondur; `RoadView.build` /
`rebuild_chunks` ≥ `MIN_THREADED_CHUNKS` (4) chunk için `WorkerThreadPool` kullanır, düğümler/mesh nesneleri
ana iş parçacığında ve anahtar sırasıyla kurulur. Sonuç iş parçacığı sayısından bağımsızdır
(`use_threads = false` aynı mesh'leri çıkarır; test var). Kavşak dolgusu bir toplu işte önbelleklenir,
`build` planı bir kez çıkarır. Üçgenleme ilk köşeye göre yerel koordinatta yapılır: 30 km'de float32 mutlak
koordinat Godot üçgenlemesini bozup çokgeni sessizce atıyordu (eski sürümde yol üçgenlerinin ~%5'i eksikti).

`stats` mantıksal yol/şerit sayısını (chunk sınırındaki parçalar tekrarlanmaz), chunk sayısını,
yakın/metro toplam üçgenlerini ve son kurulum süresini verir. Bunlar tüm dünya toplamıdır;
yerel görünür üçgen bütçesi ve GPU kare maliyeti başsız dummy renderer ile doğrulanamaz.
Playabledaki `--no-roads`, koordinatörün aynı kamera/koşullarda önce/sonra ölçümüne ayrılmıştır.

**Uzak mod (T-049 perf, `FarLod`):** Compatibility/OpenGL'de maliyet draw call başınadır (bu Intel/AMD Mac'te ölçülen
~15-20 us/çağrı). `build_far_mesh = true` iken tüm chunk'ların METRO meshleri ayrıca TEK birleşik `FarRoads` meshine
konur; kamera uzaklığı `FarLod.ENTER_M` (24 km) üstüne çıkınca `set_far_mode(true)` chunk düğümlerini gizleyip bunu
gösterir (EXIT 21 km). Metro kamerasında ~259 yol draw call'ı -> 1. Aynı köşeler (metro temsili); CPU'da metro köşe
dizileri tutulur. `rebuild_chunks` uzak meshi de günceller. Playable `--no-far-lod` ile kapatılır (A/B).
