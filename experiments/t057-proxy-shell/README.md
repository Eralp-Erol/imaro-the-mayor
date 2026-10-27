# T-057 tek kaynak 3D shell deneyi — FROZEN / sanat kabulü yok

Yetki: `production/qa/T-057-technical-review.md` Teknik karar3. Yalnız bu yeni
klasör ve `assets/hero/vegetation/shell_experiment/` yazıldı; ana katalog,
30GLB/albedo/LOD0/import politikaları ve normal_experiment değiştirilmedi.

## Açılan sonuç ve sonlu durma

`comparison.png` yalnız düzeltilmiş import sonrası10gerçek kareyi içerir:
150m ön/yan/üst LOD0–aday,150m +60°güneş ön LOD0–aday,120m LOD1–aday.
Tüm seviyeler orijinal labın aynı origin/kamera/ışığı ve LOD0 bbox çerçevesini
kullanır. Ham1600×900 dosyalar/komutlar `frames.json` içindedir. Görsellerdeki
13.72m etiketi kaynakLOD0 kamera referansıdır; aday gerçek yüksekliği13.423m.

Uygulayıcı düzeltilmiş ön/yan/üst/120m PNG’leri açtı. Kesişen kart X/şeritleri
yok; ancak taç artık kaynak yaprak boşluklarını ve dağınık konturunu kaybeden,
koyu ve belirgin dolu geometrik/fasetli bir hacim olarak okunur. 120mLOD1
geçişinde kütle/ton farkı açıktır; güneş değişimi gerçek3D yüzeylere tepki verir
ama kaynak taç karakterini geri getirmez. **Sanat PASS verilmedi.** Sabit tarif
uygulandıktan sonra destek/renk/alpha ayarı yapılmadı, diğer7’ye yayılmadı.
Bağımsız art-director son hükmü verir; finitecriteriadaki dolu geometrik taç
riskinin gerçekleştiği uygulayıcı bulgusu olarak kaydedilir.

İlk10kare geçersizdi: GLB’de COLOR_0 doğru iken Godot materyali vertex rengi
albedoya katmıyordu ve beyaz görünüyordu. Bu bir veri/import kusuruydu;
`import.gd` ile yalnız lineer vertexcolor etkinleştirildi, sRGBfalse ve normal
gölge al/ver ayarı gerçekasset importuna yazıldı. Geometri/renk örnekleri/tarif
aynı kaldı. Beyaz kareler `invalid-white-frames.json` içinde ayrıca korunur;
son kanıt diye kullanılmaz ve sanat varyantı/tuning turu değildir.

## Sabit kaynak tarifi / provenance

`prepare.py`, mevcut atlasın Pillow RGBA8 byte’larını yalnız artifact’a çıkarır.
`build.py` gerçek GLB POSITION/UV/index ve atlas bölgesinden yaprak/barkı ayırır.
Yaprak üçgenleri içindeki texel merkezleri barycentrik3D’ye taşınır,alpha>=.45
olanlar tutulur: **7,440,320** geçerli kaynak örneği. RGB sRGB→lineer dönüşür;
saydam siyah örnekler dışarıda kalır. KaynakglTF Y-up→Blender(x,-z,y)→glTFY-up
çevrimi ile aynı origin/ölçek korunur; güneş/normal/AO bake’i yoktur.

6işaretli eksen+8küp köşegeni desteği maksimumdot ile alınır; eşitlikte ilk
kaynak üçgen/texel sırası kazanır. **14benzersiz gerçek source-alpha noktası**
BMesh convex-hull ve deterministik triangulation ile **24taç üçgeni** verir.
Ham saydam sprite köşeleri/hazır küre/koni kullanılmaz. Her yüzün merkezine
enyakın16geçerli örnek lineer RGB ortalaması bütün yüz köşelerine yazılır.
Kaynak örnekID’leri/renkler/yüzler `provenance.json` içinde kayıtlıdır.

Barkın kaynak pozisyonları weld edilip açık kaynak tube segmentlerinin gerçek
iki sınır halkası çıkarılır. Ana kaynak halkalarının merkezleri:
(0,0,0)→(.15,2,-.05)→(-.18,4.6,-.12)→(.1,6.5,-.08)→(0,8,-.1), glTFY-up.
İlk/son gerçek halkadan seçilen üçer nokta kapaklı8tri prizma gövdeyi kurar.
İlk gerçek kaynak fork zinciri halkası ve kaynak uç merkezi4tri kapalı tetra
çatalını kurar; bark rengi gerçek alpha-valid bark texellerinin lineer
ortalamasıdır. Gövde ucu ve çatal ucu taç içinde, çatal tabanı gövde içindedir.
3kapalı bileşen fiziksel olarak örtüşür; tek weld edilmiş manifold bitki
olduğu iddia edilmez. Toplam **24+8+4=36tri**,40sınırı gevşetilmedi.

## Gerçek dosya ve runtime ölçümü

| Ölçüm | Gerçek değer |
|---|---:|
| GLB | 5,352byte |
| glTF BIN buffer | 4,104byte |
| Dışa aktarılan verteks /üçgen |108/36|
| Runtime materyal /sampler |1/0|
| Runtime ana surface buffer toplam byte |1,944|
| Bbox min (X,Y,Z)m |(-4.789226,-0.033820,-3.750234)|
| Bbox max (X,Y,Z)m |(4.641502,13.422883,4.140020)|

1,944byte değeri RenderingServer.mesh_get_surface() vertex/attribute/skin/index
byte dizileri toplamıdır; shadowmesh/resource/driver overhead veya toplamVRAM
ölçümü değildir. Yeni Texture2D yoktur; labdaki zemin/kaynakLOD0 dokusu aday
sampler maliyeti diye sayılmaz. Ayrı benchmark veya şehir/iPad iddiası yok.

GLB tek vertexcolor materyalinde opaque,roughness1,metallic0; gerçek düz NORMAL
ve normal gölge alma/verme vardır. UV/alpha kart yolu,normalatlas/F(P,C),AO veya
tint yoktur. Aday importunda otomatik meshLOD kapalıdır; testte36tri kullanılır.
`import.gd` mat.vertex_color_use_as_albedo=true,vertex_color_is_srgb=false;
materyal Lambert/specularDisabled ve normal shadow al/ver ile ithal edilir.
Lab materyali değiştirmez, gerçek ithal adayGLB’yi seçer.

GLB COLOR_0 ile hesaplanan lineer RGB maksimum fark **7.34e-9**. Gerçek engine
vertex buffer renkleri ile source lineer ortalama farkı **0.00390654** (RGBA8
import quantization),geometri konumu farkı **0.000199852m** (importcompression).
Runtime doğrulaması materyal sRGBfalse değerini de kontrol eder; ikinci sRGB
dönüşümü yoktur. Renk/konum toleransları birbyte/1mm içinde ve ölçüm açıktır.

## Odaklı doğrulama / tekrar

```
uv run --with pillow==11.3.0 python experiments/t057-proxy-shell/prepare.py
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python experiments/t057-proxy-shell/build.py
python3 experiments/t057-proxy-shell/audit.py
tools/godot.sh --headless --path . --editor --import --quit
tools/godot.sh --headless --path . --script res://assets/hero/vegetation/shell_experiment/audit.gd
```

- `audit.json`:36tri;herkenar2yüz;24/8/4kapalı outward bileşen; gerçek flat NORMAL;
  14destek kaynakalpha texeline yeniden projeksiyon;24yüzün16kaynakRGB ortalaması
  bağımsız tekrar hesaplandı. Gövde/çatal/taç bağlantıları geometrik doğrulandı.
- `--negative=open` ilk gerçek taç yüzünü, `--negative=normal` bir gerçek decoded
  NORMAL’ı audit girdisinde bozar; ikisi de anlamlı tanı/nonzero verir. GLB dosyası
  değiştirilmez. `negative-results.json`; artifact loglar `shell/negative-*`.
- `determinism.json`:iki tam7.44Msource-sample üretiminde GLB+provenance2/2hash
  aynı; ikinci üretimden sonra görünüş ayarı yoktur.
- `preservation.json`:eski81kayıt/67GLB/14PNG,10vegetationLOD0 ve önceki44ana
  asset/policy hash’i korunur. Root/state/catalog/docs dosyaları düzenlenmedi.
- Gerçek import audit ve explicitGDScript lint temiz. Artifact loglar:
  `artifacts/verify/t057/shell/{audit.log,runtime-audit.log,lint.log,build1.log,build2.log}`.
- Broad47test/full,commit/push veya başka tür çalışması yok. Son karar bağımsız
  sanatta; deney donduruldu.

## Son gerçek kareler

- front/lod0/150m/sun+0: `artifacts/screenshots/captures/20261027-142114-t057-shell-final-plane-front-lod0-150-sun0.png`
- front/proxy/150m/sun+0: `artifacts/screenshots/captures/20261027-142119-t057-shell-final-plane-front-proxy-150-sun0.png`
- side/lod0/150m/sun+0: `artifacts/screenshots/captures/20261027-142123-t057-shell-final-plane-side-lod0-150-sun0.png`
- side/proxy/150m/sun+0: `artifacts/screenshots/captures/20261027-142128-t057-shell-final-plane-side-proxy-150-sun0.png`
- top/lod0/150m/sun+0: `artifacts/screenshots/captures/20261027-142133-t057-shell-final-plane-top-lod0-150-sun0.png`
- top/proxy/150m/sun+0: `artifacts/screenshots/captures/20261027-142139-t057-shell-final-plane-top-proxy-150-sun0.png`
- front/lod0/150m/sun+60: `artifacts/screenshots/captures/20261027-142145-t057-shell-final-plane-front-lod0-150-sun60.png`
- front/proxy/150m/sun+60: `artifacts/screenshots/captures/20261027-142151-t057-shell-final-plane-front-proxy-150-sun60.png`
- front/lod1/120m/sun+0: `artifacts/screenshots/captures/20261027-142157-t057-shell-final-plane-front-lod1-120-sun0.png`
- front/proxy/120m/sun+0: `artifacts/screenshots/captures/20261027-142204-t057-shell-final-plane-front-proxy-120-sun0.png`
