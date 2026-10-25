# Yol görünümü (T-048)

`RoadView.build(network)` yalnız `mode() == road` kenarlarını okur; kapalı yolun fiziksel yüzeyi kalır.
`layer` taban/delta kaynağıdır, yükseklik katı değildir. Dünya/ağ/sim/kayıt değiştirilmez.

`data/view/road_style.json` geçici sanat verisidir. Sınıf rengi ve genişlik katsayısı buradadır;
varsayılan katsayı 1, ağın parsel cephesini belirleyen `edge.width` koridorunu korur.
Şerit ekseni düğüm konumlarıdır; bina yönü/cephe verisi yeniden yorumlanmaz.

1 km chunk başına yakın ve metro meshleri bir kez kurulur. Yakın görünüm ilçe/sokakta gerçek genişliktedir;
metro daha ince ve daha seyrek segmentlidir. Godot mesafe görünürlüğü seçer; kare başına script yoktur.
Arazi üçgenlerine kırpma (TerrainMeshBuilder köşegeni, stride=1) yüzeyin içine gömülmeyi engeller.
Köşe ve üçgen içi yükseklik görünür arazi düzlemi + veri ofsetidir; bilineer `height_at` ile eğri hücrelerde
kasıtlı olarak farklıdır. `--stride` arazi deneyi >1 bu görünümün kapsamı dışındadır.

T-042 çağıranı değişiklikten önce `plan()` sonucunu saklar. Değişiklikten sonra `RoadChunkPlan.build(net, style)`
ile yeni indeksi çıkarır. Eklenen/silinen/taşınan kenarların **eski ve yeni `edge_keys`** birleşimine,
uç düğümlerin eski/yeni `junction_keys` ve kavşak trimi etkilenen komşu kenarların `edge_keys` anahtarlarını ekler.
Bu birleşimi `rebuild_chunks(keys)` çağrısına verir. Eski plan geçerliliğini korur; yalnız verilen chunkların
mesh/düğüm kaynakları değiştirilir. İndeks yenileme O(ağ), mesh yenileme yalnız istenen chunklar içindir.
Silinen son kenar chunk düğümünü de kaldırır. Delta sinyal bağlaması T-042'ye aittir.

`stats` mantıksal yol/şerit sayısını (chunk sınırındaki parçalar tekrarlanmaz), chunk sayısını,
yakın/metro toplam üçgenlerini ve son kurulum süresini verir. Bunlar tüm dünya toplamıdır;
yerel görünür üçgen bütçesi ve GPU kare maliyeti başsız dummy renderer ile doğrulanamaz.
Playabledaki `--no-roads`, koordinatörün aynı kamera/koşullarda önce/sonra ölçümüne ayrılmıştır.
