# T-057 · Teknik yönetmen kararı · kaynak normal verisi deneyi

- Tarih: 2026-10-27 · Rol: technical-director (Codex; Claude Opus çalıştırıldığı iddia edilmez)
- Karar: **Mevcut A1 materyali FAIL; skaler AO/küresel normal kalibrasyonu durur. Yalnız bir çınarda kaynak LOD0 yüzey normali deneyi yetkilidir.** Bu karar sanat PASS'ı, kullanıcı onayı veya T-057 kapanışı değildir.
- REQ: VIS-01/02/03/05, WLD-01, TEK-03. Kaynak: T-057 görevi, bağımsız QA/art raporları, mevcut shader/import/bake kodu ve gerçek görüntüler.

## Doğrulanan teşhis

1. `bake_proxies.py` kaynak malzemeyi Emission+Transparent ile değiştirip yalnız albedo/alpha çıkarıyor (satır39–44). Gerçek yaprak yüzeylerinin normal ve yerel ışık varyansı kaydedilmiyor. Bu bir bug değil, fakat mevcut düz temsil için bilgi kaybıdır.
2. `proxy_canopy.gdshader` satır23–27 bütün piksellere sabit AO0.55 ve kart konumundan hesaplanan makro normal veriyor. Sabit AO, kaynak yaprakların yönelim dağılımını yeniden oluşturamaz; bu değeri tekrar ayarlamak çözüm planı değildir. Compatibility'deki AO etkinliğini bu incelemede ölçmedim.
3. Kaynak `veg_hero_plane_a_lod0.glb` JSON'u doğrudan okundu: düğümde transform yok, primitive gerçekten `POSITION`, `NORMAL`, `TEXCOORD_0` taşıyor. Kullanılacak yüzey normal verisi kaynakta zaten var.
4. Dört ham150m kare açıldı: `20261027-120725-...front-lod0.png`, `120851-...calibrated-front.png`, `120741-...top-lod0.png`, `120855-...calibrated-top.png`. Koyu X ortadan kalkmış; proxy hâlâ düzgün/açık renk lekesi, kaynakta görülen yaprak/faset ışık varyansından yoksun. Kaynak LOD0 yeniden tasarımı gerekmiyor.
5. Gerçek import politikası `proxy_import.gd` üzerinden ShaderMaterial atıyor; gizli lab düzeltmesi değildir. Gölge alma kapalı, yere gölge atma açık politikası şu deneyde korunabilir. Materyal unlit yapılmaz.

47test/import sonuçları uygulayıcı/QA raporlarından biliniyor; ben bu testleri tekrar çalıştırmadım. Yeni normal dokusunun başarılı olacağını henüz deneyle doğrulamadım.

## Seçilen en küçük deney

**Sadece çınar; mevcut3 kart,6 üçgen, aynı origin/bbox/UV ve mevcut albedo/alpha korunur.** Bütçeler,50/120m eşikleri, LOD0 ve ışık/kamera kabul koşulları değişmez.

1. Mevcut kaynak bake döngüsünün aynı ön/yan/üst projeksiyonlarında, ilk görünür kaynak yüzeyinin **gerçek nesne uzayı normalini** çıkar. Küresel normalden veya proxy kart normalinden üretme. Kaynak alpha0.45 maskesi ve aynı görüntü kırpma/112px içerik+8px kenar kullanılır. Yeni kaynak geçişi güneş, renk, gölge veya mevcut lab ortamından bağımsız sayısal veridir.
2. Blender dünya normalinden GLTF yerel uzayına dönüşümü açık tanımla. Kaynak node identity olduğu için Blender Z-up →glTF Y-up dönüşümü aday olarak `(nx,nz,-ny)`; bunu yön/arka yüz testiyle doğrulamadan kabul etme. Normal `[-1,1]` →RGB `[0,1]` kodlanır. Çift taraf yüzlerin görünen yüz işareti yanlış veya iki kez ters çevrilmemeli.
3. Ayrı **1024×384 RGBA8 veri atlası** kullan. Albedo atlasının y640–1023 bölgesindeki24slot ile aynı yerleşim; veri atlasında satır0–383. RGB gerçek normal, A ilk deneyde1/rezerve; henüz AO icat edilmez. Normal atlasını renk dokusu gibi gamma dönüştürme; bake için Raw/non-color çıkış, sampler'da `source_color` yok. Godot'un tangent normal haritası otomatik dönüştürmesi/RGTC mavi kanal yeniden kurması nesne normallerini bozabilir: üç signed bileşen korunmalı. İçe aktarılan bilinen eksen örneğiyle kanıtla; enum/sıkıştırma ayarı model belleğinden tahmin edilmez.
4. Mevcut varlığa özel shader ikinci sampler'dan bu normali okur, `2*rgb-1` ile açar, sıfıra yakın/mipte iptal olmuş vektörlere güvenli fallback uygular ve normalize eder. Nesne→view uzayına doğru normal dönüşümüyle `NORMAL` yazılır. Pozisyondan küresel normal artık ana veri değildir; sabit AO kalibrasyonu ile sonucu yeniden boyama yapılmaz. Gölge almama ve yere gölge atma, matte Lambert/roughness1/specular0, alpha ve ortak albedo aynen kalır.
5. Materyal/import/provenance yeni data Texture2D ve hash'ini açık taşır; albedo tek kalır ve bütün proxy'ler aynı veri dokusunu paylaşır. Gerçek ithal GLB'de sampler/politika doğrulanır; yalnız laboratuvar override'ı kabul edilmez. LOD0/L1/palmiye materyalleri değişmez.

Bu aşama normal verisini geri getirmeyi sınar. Kaynak öz-gölgelemesinin tamamını yeniden kurduğunu iddia etmez. **Normal-only deney başarısızsa yeni AO slider döngüsü veya sekiz tür toplu üretimi yapılmaz.** Kaynağa bağlı, güneşsiz ve alpha-aware yerel görünürlük/AO capture ayrı kanıt gerektirir; mevcut Emission bake'e rastgele koyulaştırma eklemek veya sabit güneşli fotoğraf kullanmak yetkili çözüm değildir.

## Kaynak maliyeti kararı

Tek Texture2D şartı kullanıcı kanonu değil, teknik çalışma tercihiydi. Kaynak normal bilgisini kaybetmek yerine bir ek ortak veri atlasına izin veriyorum.1024×384 RGBA8 taban1.5MiB; bütün mipler toplam **2,097,148 byte ≈2.00MiB** (teorik sıkıştırmasız). Mevcut5.33MiB albedo+mip hesabına eklenir: yaklaşık7.33MiB; sürücü/VRAM ölçümü değildir. Shader'a piksel başına bir ek veri örneklemesi gelir. Geometri6tri kalır; üçgen eşiği gevşetilmez. Deneyde gerçek dosya boyutu, gerçek Texture2D sayısı ve dar lab kare maliyeti ayrıca kaydedilir; gerçek kent/iPad performansı sonucu çıkarılmaz.

## Sonlu kabul / durma koşulu

Önce yalnız çınar için aşağıdaki kanıt oluşturulur; bütün türlerin render'ı beklenmez:

- Gerçek Godot150m ön/yan/üst, aynı origin/kamera/ışık ve kaynak LOD0 çerçevesi: kaynak ve yeni proxy karşılaştırması. Koyu X/geniş sabit panel sınırı olmamalı; yaprak/faset değişimi ve kaynakla genel taç ton ilişkisi görünür biçimde geri gelmeli. Bunu art-director değerlendirir; hash/üçgen geçişi sanat PASS yerine geçmez.
- Bir ön görünüm çifti, aynı kaynak ve proxy için güneş azimutu+60° ile ek tanı: iki temsil de ışığa tepki vermeli. Bu yeni gece/hava sistemi değildir; baked-sun/unlit kısa yolunu dışlar. Esas150m kabul ışığı değişmez.
- Bilinen normal ekseni/readback, aynı sourcealpha ve RGB normal varyansı; sourceLOD0+eski81 kayıt hash'leri değişmez; ortak kaynak/atlas/projeksiyon izlenebilir. Veri olmayan/sıfır normal veya normal dokusu kaldırılınca odaklı denetim anlamlı hata vermeli.
- **Bir normal-only deneme.** Normal bilgisi doğru olduğu hâlde taç hâlâ düz/açık kalır veya üç bakıştan birinde panel/X oluşursa deney FAIL ve kapsam durur. Sonraki teknik seçenek için yeni karar gerekir; batch full/teslim PASS başlatılmaz. Normal-only kanıt sanat kapısından geçerse aynı yöntem kalan7 palmiye dışı türe uygulanır, sonra tüm8far/yan-üst kanıtı, odaklı QA ve finalfull yapılır.

## Reddedilen yollar

- Sabit AO/tint değerlerini art arda değiştirmek: kayıp normal alanını üretmez, Compatibility davranışına ve tek ışık karesine bağımlıdır.
- Unlit veya mevcut güneş/gölgeyi albedoya bake etmek: ışık değişiminde tek dünya görünümünü bozar.
- Eşiği ileri taşımak, üçgen sınırını büyütmek, LOD0'ı tekrar tasarlamak veya lab ışığını değiştirmek: verilen sorunu kapatmaz ve bu kararın kapsamı değildir.
- Şimdiden tam octahedral/depth/parallax impostor renderer'ı yazmak: bir kaynak-normal deneyiyle ölçülmeden gerekli olduğu kanıtlanmadı.

## Referans ve API sınırı

Önce yerel `docs/engine-reference/godot/` okundu; bu özel shader ayrıntısı için sınıf düzeyinde referans içermiyor. Resmî [Godot spatial shader referansı](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html) `NORMAL`ın fragment'ta view uzayında olduğunu ve `shadows_disabled`ın almayı kapatıp atmayı koruduğunu belgeliyor. Bunlar mevcut shader/import ve gerçek render kanıtıyla uyumlu. Blender4.5 normal-output/bake node ayrıntısı bu incelemede runtime ile sınanmadı; uygulayıcı aynı kurulu4.5.14'te küçük eksen testiyle doğrulamalı. AO bake'in alpha kartlarını doğru hesaba kattığı kanıtlanmadı; bu nedenle AO yakalama ilk yetkili deneyin parçası değildir.

## Teknik karar 2 · tek ortak alan doğruluk deneyi (2026-10-27)

**EVET — aynı veriyle bir adet uygulama-doğruluğu düzeltmesi yetkilidir.** Normal-only deney veri/eksen/gamma/import bakımından doğrulandı; fakat yan150m'de parlak çapraz dikiş sürüyor. Mevcut shader `NORMAL`ı her kartın kendi UV'sinden okuduğundan, aynı fiziksel kesişim noktasında üç farklı normal alanı seçiyor. Bu, daha fazla bake veya AO ayarı gerektirmeden sınanabilecek bir adresleme/süreklilik kusurudur. Yeni araştırma, LOD0 tasarımı, doku, geometri, bütçe veya mesafe değişikliği yetkilendirilmez.

### Tek deneyin tam kapsamı

Yalnız deney çınarı ve mevcut üç kart/6tri, iki Texture2D kullanılır. Değişmeyen kaynak albedo/alpha ve normal atlasları yeniden bake edilmez. Tüm kartlar aynı nesne konumu ve güncel kamera yönünden **F(P,C)** materyal alanını hesaplar; kart kimliği, kartın kendi NORMAL'ı, FRONТ_FACING'i veya kendi UV'si alan seçemez.

1. `P` fragment'ın nesne uzayı konumudur. `C = normalize(camera_object_position - P)` güncel kamera doğrultusudur; dünya kamera konumu inverse model dönüşümüyle nesne uzayına alınır. Alan, aynı P/C için karttan bağımsız olmalıdır.
2. Ön/yan/üst kaynak projeksiyonlarının affine `P→UV_i` haritaları **gerçek dışa aktarılmış proxy POSITION/TEXCOORD_0 çiftlerinden** türetilir. Normali sabit olan üç kart ayrılır, üç köşeden affine u/v bazları çözülür; kalan köşe ile doğrulanır. Eksen işareti, yan görüntü aynalaması, üst yönü veya8px kenar model belleğinden tahmin edilmez. Orijinal albedo bölgesi ve normal veri bölgesi y640 ofseti metadata'dan gelir. Kart köşeleri ve orta noktalarındaki yeniden projeksiyon eski kendi-UV adresiyle eşleşmelidir.
3. Her projeksiyon için mevcut albedo atlasından `rgba_i` (RGB source_color ile lineer ışık uzayında), veri atlasından `n_i = 2*rgb_i-1` (non-color, gamma dönüşümsüz) okunur. Dışarı taşan projeksiyon kapsaması sıfırdır; tile'lar birbirine sarılmaz. Normal boş/sıfır/mipte iptal olmuşsa o örnek geçersizdir.
4. Normal capture her görünümün bake kamerasına bakan etkin yüz işaretini içerir. Bu nedenle geçerli her `n_i`, normalize edildikten sonra **güncel** C yarı-küresine yöneltilir: `dot(n_i,C)<0` ise `n_i=-n_i`. Proxy kartının FRONT_FACING değerine göre ikinci bir flip yapılmaz.
5. Sabit ve ayarsız yön ağırlıkları kullanılır: ön/yan/üst için kendi kaynak normal eksenine karşı `d_i = dot(C,axis_i)^2`; dik eksenlerde bu C bileşenlerinin kareleridir. Ağırlık `w_i = d_i * rgba_i.a * valid_i` olur. Toplamla normalize edilir. Yeni sharpness/tint/AO parametresi veya sonuçlara göre ağırlık taraması yoktur.
6. **Hem RGB hem normal aynı ağırlıklarla birleşir:** `color = sum(w_i*rgb_i)/sum(w_i)`, `n = normalize(sum(w_i*n_i))`. Yalnız normali birleştirip RGB'yi kartın kendi UV'sinde bırakmak tam materyal sürekliliğini garanti etmez. RGB lineer uzayda karıştırılır; normal decode/normalize sırası korunur. Payda sıfıra yakınsa veya vektör iptal olursa, geçerli en yüksek ağırlıklı kaynak örneği kullanılır; rastgele küresel normal/renk uydurulmaz. Bütün örnekler geçersizse fragment atılır.
7. İlk ve tek deneyde **geometrik silüet için mevcut kartın orijinal alpha maskesi/.45 eşiği korunur**; bu alanın kendi UV'si yalnız mevcut alpha için kullanılabilir. Ortak alan RGB ve normal içindir. Yeni alpha/derinlik/visibility modeli eklenmez. Bu sınırda hâlâ düz dikiş görülürse başka alpha ayarı denenmez; mimari reddedilir.
8. Ortak nesne normali doğru model normal matrisi→view dönüşümüyle NORMAL'a yazılır. Relightable matte Lambert, source palette, gölge almama/yere gölge atma ve mevcut AA şartları korunur. Güneş veya kamera bake'e dondurulmaz; unlit/emission/AO/tint kısa yolu yoktur.

### Maliyet ve kanıt

İki sampler değişmez; fakat fragment başına **3 albedo +3 normal örneklemesi** vardır (önce1+1 idi). Normal atlasının mevcut yaklaşık2MiB ek mip maliyeti değişmez. Bu yeni örnekleme maliyeti dar labda kaydedilir; kent/iPad bütçesi geçti denmez. Aynı F(P,C)'nin kart kesişiminde iki taraftan aynı RGB/normal verdiği debug veya sayısal örnekle doğrulanır; kart UV'sine geri dönüldüğünde bu kontrol anlamlı fark göstermelidir.

### Tek kabul / kesin durma koşulu

- Bir çınar,150m, değişmeyen kaynak kamera/ışık ile ön/yan/üst kaynak ve aday kareleri; ayrıca önceki +60° güneş ön çiftinin aynısı. Ham kareler açılır, mevcut normal-only adayla karşılaştırılır.
- Düz parlak/koyu çapraz veya sabit panel sınırı kalmamalı; kaynak yaprak/faset değişimi ve genel taç ton ilişkisi korunmalı. Sadece dikişi bulanıklaştırıp taç ayrıntısını yeniden tek renge indirmek başarısızlıktır. Silüet ve zemin gölgesi bozulmamalı.
- Bağımsız art-director gerçek görüntüde karar verir. Teknik hash/import/47test geçişi sanat PASS sayılmaz.
- **Bu tek shader doğruluk deneyi son sınırdır.** Veri adresleme/işaret/ortak-alan koşulları doğru olduğu hâlde üç bakıştan birinde düz dikiş veya kabul edilemez ton/ayrıntı kaybı sürerse mevcut üç çapraz kart mimarisi bu hedef için **REJECT / teknik blocker** olur. Sekiz türe yayılmaz, yeni AO/alpha/weight denemeleri ve final full başlatılmaz. Sonraki mimari ayrı karardır; bu görevde örtük bütçe/mesafe gevşetmesi yapılamaz.

Bu karar shader deneyi için yetkidir; deney henüz çalıştırılmadı ve başarılı olacağı iddia edilmez. Yeni varlık/kullanıcı onayı veya oyun entegrasyonu verilmedi.

## Teknik karar 3 · çapraz kart REJECT; tek kaynak-shell deneyi

**Karar:** Üç eşzamanlı çapraz kart mimarisi T-057 hedefi için reddedilir. Yukarıdaki sonlu durma kuralı gerçekleşti; yeniden alpha/weight/AO veya ortak-alan ayarı yapılmayacak. `experiments/t057-proxy-normals/FPC-REPORT.md` ve açılan `fpc-comparison-150m.png` doğruluk kontrollerine rağmen ön görünümde yatay şerit/kenar parçaları ve yan görünümde kaynakla farklı, açık taç tonu gösteriyor. Affine hata 1.39e-17, ortak P farkı 0, runtime/gamma/mip kontrollerinin geçmesi bu görsel başarısızlığı değiştirmiyor. Önceki deneyler tarihsel FAIL olarak korunur.

**Yeni mimari kararı:** Kaynaktan türetilen kapalı, gerçek 3D taç kabuğu ve kaynakla hizalı gövde, mevcut 40 üçgen sınırında teknik olarak uygulanabilir. Yalnız çınar için tek izole deney yetkilidir. Bu karar görsel PASS veya diğer türlere yayma yetkisi değildir. Geometri, yüzey ve gölge artık aynı 3D hacmi temsil eder; kesişen kartların ayrı görünürlük/derinlik alanları ortadan kalkar.

### Sabit deney tarifi

1. Değişmeyen çınar LOD0 GLB'sinden foliage üçgenleri, gerçek UV ve kaynak atlası okunur. Ham kart köşeleri destek noktası sayılmaz: saydam sprite köşeleri tacı şişirir. UV üçgenlerinin içinde kalan kaynak texel merkezleri barycentrik olarak 3D'ye taşınır; kaynak alpha >=0.45 olan örnekler tutulur. Yaprak/bark ayrımı gerçek materyal/atlas bölgesinden gelir. RGB kaynak renk uzayından lineere çevrilir; saydam siyah pikseller renk ortalamasına girmez. Kaynak dosya/hash, örnek sayısı, bounds ve eksen dönüşümü kaydedilir. Bu yeni ışık bake'i değildir.
2. Bu görünür kaynak noktalarından altı işaretli eksen ve sekiz küp köşegeni yönünde maksimum dot ürünü veren destek noktaları seçilir; eşitlikte sabit kaynak indeks sırası kullanılır. Tekrarlanan noktalar kaldırılır. En çok 14 noktanın convex hull'u, dışa dönük ve kapalı olarak üçgenlenir. Üç boyutlu dejenere olmayan bir hull için V<=14, T=2V-4<=24; dejenere kaynak veya geçersiz winding sessizce küreye dönüştürülmez, deney hata verir. Mevcut Blender araç zinciri kullanılır; yeni paket gerekmez.
3. En çok 8 üçgenlik kapaklı üçgen prizma gövde ve en çok 4 üçgenlik kaynak hizalı çatal desteği eklenir; toplam <=36, kesin üst sınır 40 üçgendir. Gövde merkezi/tabanı, incelme ve çatal bağlantısı gerçek kaynak gövde/branch konumlarından alınır. Taçla bağlantı kopuk olmayacak; origin, zemin teması ve kaynak ölçeği korunacak. Hull genel bir küre/koniyle değiştirilmez. Kaynak LOD0 yeniden tasarlanmaz.
4. **Temiz malzeme başlangıcı:** Opaque gerçek geometri, gerçek düz yüz normalleri, roughness=1 ve metallic=0; normal gölge alma/verme açık. Taç yüzünün rengi, yüz merkezine en yakın 16 geçerli kaynak foliage örneğinin lineer RGB ortalamasıdır (az örnek varsa hepsi); kaynak indeksleri ve sonuç renkleri kaydedilir. Yüz köşelerine aynı renk yazılır. Gövde rengi gerçek kaynak bark örneklerinden alınır. Tek vertex-color malzemesi kullanılabilir. glTF vertex renkleri lineerdir; importta ikinci sRGB dönüşümü yapılmadığı kontrol edilir. Sun yönü, AO, çarpan/tint, kamera veya bake normalinden renk üretilmez.
5. Alpha görünürlük maskesi artık kabuğu delmez: ALPHA=1, alpha-scissor/blend kapalı; eski kart UV/alpha ve F(P,C) yolu bu adayda yoktur. Ayrı kaynak normal atlası da kullanılmaz. Geçerli kaynak alpha yalnız offline destek/renk örneklerini seçer. Yeni texture gerekmez; adayın gerçek runtime sampler/material/mesh maliyeti ölçülür, sahnede kaynak LOD0 atlasının hâlâ yüklü olması proxy maliyetiyle karıştırılmaz.

### Tek sonlu doğrulama ve sınır

Deney ayrı dosyalarda tutulur; mevcut katalog/diğer yedi aday değiştirilmez. Uygulayıcı kendi çıktısının üçgen sayısını, kapalı hull kenarlarının ikişer yüz paylaşmasını, outward winding'i, kaynak kökenli destek/renk verisini, gerçek import edilmiş opaque materyali ve gölge politikasını doğrular. Eski LOD0/LOD1 alpha-MASK kontrolleri korunur; kartlara özgü aday testi kabuk için sahte MASK zorlamasına dönüşmez.

Mevcut aynı 150m kamera/zemin/ölçek ile ön, yan, üst kaynak–aday çiftleri ve +60 derece güneş ön çifti alınır; ham kareleri bağımsız art-director açar. 120m proxy başlangıcı çevresinde aynı türün LOD1→aday geçişi de bir eşleşmiş çiftle görülür; mesafe/FOV/eşik değiştirilmez. Kaynak taç kütlesi, tür silüeti, gövde bağlantısı, faset/ton ilişkisi ve değişen ışığa hacimsel tepki kabul edilebilir olmalıdır. X, şerit, kenar lekesi veya belirgin dolu geometrik top görünümü FAIL'dir. Kaynak iç boşluklarını dolduran convex hull'un 150m'de kabul edileceği **henüz doğrulanmamış temel risktir**; <=40 üçgen matematiği bunu garanti etmez.

**Bu tek kabuk deneyi geometri/veri doğruluğu sağlandığı hâlde sanatsal kabul alamazsa durulur.** Yeni yüz renk ayar turu, alpha deliği, destek yönü optimizasyonu, ek bake veya diğer türlere yayma yapılmaz. T-057 far temsil için mevcut sınırlar altında çözülmemiş mimari blocker olarak kaydedilir; yeni yöntem ayrı teknik karar gerektirir. Ancak bağımsız sanat PASS'ı sonrasında aynı mimarinin kalan türlerde ayrı kabulü planlanabilir; bu rapor tam batch/final-full başlatmaz. Orijinal 81 kayıt, 67 GLB, 14 PNG ve 10 LOD0 değişmez.

Bu bölüm yalnız rapor kararıdır; burada kod/asset değiştirilmedi, test/render çalıştırılmadı.
