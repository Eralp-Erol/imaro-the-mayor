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

## Teknik karar 4 · palmiye dışı uzak temsil: LOD1'in görünürlük-sıralı alt kümesi "LOD2" (2026-10-27)

- Rol: technical-director (Claude Opus, bu devir oturumu). Yalnız okuma + analitik hesap; Godot, Blender, test veya capture **çalıştırılmadı**. Kod/asset değişmedi. Bu karar sanat PASS'ı, kullanıcı onayı, oyun entegrasyonu veya T-057 kapanışı değildir.
- REQ: VIS-01/02/03/05, WLD-01, TEK-03; performans rejimi ADR-0001 (§Performans) ve ADR-0004 (karar 4–5).
- Okunan: `docs/agent-handoff/T057_CODEX_TO_CLAUDE_2026-10-27.md`, `production/tasks/T-057.md`, bu dosyanın Karar 1–3'ü, `production/qa/T-057-art-review.md` Karar 3, `experiments/t057-proxy-shell/README.md`, ADR-0001/0004, `design/library/README.md` §5, `design/specs/art/building-kit-v1.md` §7–9, `design/library/vegetation-hero.md`, `art/blender/vegetation/{build.py,rebuild.sh}`, `tools/library/{vegetation_catalog.py,check_vegetation_import.gd}`, `tests/library/test_vegetation_catalog.py`, `assets/hero/vegetation/vegetation_lab.gd`, `src/view/camera/camera_presets.gd`, `src/view/buildings/building_lod.gd`, `experiments/scale-bench/RESULTS.md`, `design/library/sheets/vegetation-hero/index.json`, 30 ana `.glb.import` dosyası.

### 4.0 Karar

1. Üç çapraz kart (≤6 tri) ve tek kapalı hull (36 tri) aileleri **REJECT olarak kalır**; onlarda yeni ayar yok. Palmiye dışı türler için T-057'de **tekil ağaç başına ≤40 üçgenlik uzak proxy aranmaz.**
2. İlk ve tek yeni aday: **LOD2 = LOD1'in bit-eşit alt kümesi.** Yeni vertex, yeni normal, yeni UV, yeni doku, yeni shader yok. LOD1'deki her yaprak kartı ve gövde/dal segmenti ya olduğu gibi kalır ya da bütünüyle çıkar. Hangisinin çıkacağına çevrimdışı, sabit 17 bakışta ölçülen **görünür piksel katkısı** karar verir (en gizli olan önce çıkar). Sabit kapsama koşulları bunu sınırlar (§4.2).
3. Sayısal bütçe: **LOD2 ≤ floor(0,6 × ölçülen LOD1)** ve ağaçta mutlak tavan 180 (=0,6×300). Çınarda bu **≤172 üçgen** demektir. Ek kazanç kapısı: 17 bakışta alpha öncesi rasterize fragment alanı ≤ 0,80 × LOD1. **Bu, 40 üçgenlik uzak sınırını açıkça gevşetir.** 40 sınırı kullanıcı kanonu değil, T-057'nin teknik çalışma değeriydi. Gevşetme yalnız bu kararla ve aşağıdaki sözleşme güncellemeleriyle geçerli olur. Kötü bir adayı uzağa itmek değildir: LOD2'nin geçiş mesafesi henüz yoktur (§4.4).
4. Tekil ağaç zinciri LOD0 → LOD1 → LOD2 ile biter. Daha uzak bant kit v1 §7'deki **hücre başına birleşik ağaç lekesi/HLOD** işidir. O ÇM'dir, T-057 kapsamı dışındadır ve ayrı görev ile ayrı sanat kapısı gerektirir. Aritmetik gerekçe §4.1-D'de.
5. Mesafe eşiği bu kararda **yazılmaz.** Yalnız ölçüm kuralı verilir (§4.4). Deneyde kullanılan 120/150/250 m değerleri önceki FAIL kareleriyle karşılaştırılabilirlik içindir, eşik kararı değildir.

### 4.1 Taban: mevcut LOD1'in ekran kaplaması ve maliyeti

**A. Kamera ve ölçek (doğrulandı, kaynak okundu).** Oyun kamerası dikey FOV 40° kullanır (`camera_presets.gd:15`, KEEP_HEIGHT sözleşmesi `camera_math.gd:111`). Lab da 40° kullanır (`vegetation_lab.gd:31`). `design/library/README.md` §5.1 tablosu 50° ile hesaplanmış; bu kameraya ait değildir. Çınar LOD0 13,72 m yükseklik × 10,01 m genişlik (GLB ölçümü). Formül: `px/m = H_px / (2·d·tan20°)`. Aşağıdaki tablo bir hesaptır, ölçüm değildir. iPad satırları doğal çözünürlükte ve 3D ölçeklemesiz render varsayar; hangi iPad modeli olduğu ve render ölçeği **bilinmiyor**.

| Profil (yatay FOV) | 50 m | 120 m | 150 m | 250 m |
|---|---|---|---|---|
| Lab 1600×900 (65,8°) | 24,7 px/m · 339×248 px | 10,3 · 141×103 | 8,2 · 113×83 | 4,9 · 68×50 |
| 1080p (65,8°) | 29,7 · 407×297 | 12,4 · 170×124 | 9,9 · 136×99 | 5,9 · 81×59 |
| iPad 11" 2388×1668 (55,0°) | 45,8 · 629×459 | 19,1 · 262×191 | 15,3 · 210×153 | 9,2 · 126×92 |
| iPad 13" 2752×2064 (51,8°) | 56,7 · 778×568 | 23,6 · 324×237 | 18,9 · 259×189 | 11,3 · 156×114 |

Hücre değeri: px/m · ağaç yükseklik×genişlik (bbox, px). Bbox alanı 1080p'de 150 m'de ≈13,4k px, 250 m'de ≈4,8k px. Gerçek taç kaplama oranı bbox'tan küçüktür ve **ölçülmedi**; deney karelerinden ölçülecek. Sonuç: 150 m'de çınar 1080p'de 136 px, iPad 13"te 259 px boyundadır. Bu boyda yaprak kümesi, boşluk ve ton farkı rahatça görülür; art-director'ın iki FAIL'i bu hesapla tutarlı. 250 m'de bile 81–156 px kalır. Yani "250 m'de fark görünmez" varsayımı yapılamaz.

**B. LOD1'in içeriği (doğrulandı: `build.py:133–142` + `tube()`/`tuft()` sayımı `index.json` ile eşleşiyor; çınar LOD1 GLB'si 576 vertex / 864 index).** Her quad'ın kendi 4 vertex'i var.

| Tür | LOD1 | Yaprak kartı tri | Gövde+dal tri | Odun payı |
|---|---:|---:|---:|---:|
| çınar | 288 | 128 (8 küme × 8 kart) | 160 (gövde 4 seg × 4 kenar = 32; 8 dal × 2 seg × 4 kenar = 128) | %56 |
| kızılçam | 286 | 126 | 160 | %56 |
| fıstık çamı | 272 | 128 | 144 | %53 |
| zeytin açık / burgulu | 122 / 152 | 42 / 56 | 80 / 96 | %66 / %63 |
| servi | 300 | 284 | 16 | %5 |
| maki / çit | 80 / 100 | 56 / 70 | 24 / 30 | %30 |

Çınar LOD1 dal ucu yarıçapı 0,045 m'dir. Bu çap 1080p'de 150 m'de **0,89 px**, 250 m'de 0,53 px eder. Dal segmentlerinin uzak (dirsek→taç) yarısı çoğunlukla yaprak kartlarının arkasında kalır. Yani LOD1 üçgenlerinin yarısından fazlası uzakta piksel-altı veya gizli odundur. Bunun görüntüye katkısı az, maliyeti var (ince üçgen, quad overshading; GPU davranışı **varsayım**). Yaprak kartları ise kaynak kümelerini ve alpha boşluklarını taşıyan kısımdır. İki FAIL ailesi tam olarak bunu kaybetti.

**C. Materyal / draw call (doğrulandı, kod okundu).** LOD1 tek surface ve tek paylaşılan atlas materyali kullanır: BaseMaterial3D, alpha-scissor 0,45, çift taraf, gölge alır ve atar. Bir MultiMesh'te tür/seviye başına 1 draw call, gölge geçişinde +1. Üçgen sayısı draw call'u değiştirmez. Her yeni LOD seviyesi, bant sınırını kesen her (hücre, tür) için +1 draw call ekler.

**Ölçüm karıştırıcısı (doğrulandı):** 30 ana bitki `.glb.import` dosyasının hepsinde `meshes/generate_lods=true` var (örn. `veg_hero_plane_a_lod1.glb.import`). `design/library/README.md` §5.2 notu ise "Godot otomatik mesh LOD kapalı" diyor. Shell/normal deneylerinde bu bayrak `false`. Önceki 150 m "LOD0" ve 120 m "LOD1" referans karelerinde Godot'nun otomatik sadeleştirilmiş index buffer'ı kullanmış olması mümkündür; hangi LOD'un çizildiği **doğrulanmadı**. 6-tri kartlar ve shell (`false`) FAIL'lerini bu açıklamaz. Yine de yeni taban ölçümü bu bayrak kapalıyken alınmalıdır (§4.3). Benimseme sırasında ana importlarda düzeltilmesi gereken bir sözleşme sapmasıdır.

**D. Kent/iPad bütçesi: "LOD1 288 tri'yi 120–250 m'de tutmak bütçeyi bozar mı?"**

Repodaki gerçek bütçe verisi:
- Toplam yerel evre görünür üçgen ≤ 900.000 ve kare ort ≤ 8 ms / P95 ≤ 16,6 ms (kit v1 §9, ÇM). Aynı bölümün ağaçsız kaba hesabı zaten ≈880k ("pay dar"; ölçülmedi).
- ADR-0001: masaüstü ort ≤ 8 ms, draw call ≤ 600 (hedef 400). **iPad bütçesi yok** ("cihaz ölçümünden sonra yazılır"). `M0-CLOSURE.md` iPad zincirini "denenmedi" diye kaydediyor.
- scale-bench'te ağaç, alpha, doku ve occlusion culling yoktu (RESULTS.md "What this does NOT prove").
- Oyunda bugün hiç ağaç yok (kit v1 §1 gözlem 5). Repoda ağaç yoğunluğu verisi yok.

Buna göre şu sayılar **ölçüm değil, parametrik hesaptır** (ρ = ağaç/ha; varsayılmıştır). Sokak kamerası (60 m, pitch 12°) ufka kadar görür. 1080p yatay görüş açısı içinde 120–250 m bandı 2,76 ha, 250–1000 m bandı 53,8 ha eder (iPad 13": 2,17 / 42,4 ha).

| ρ (varsayım) | 120–250 m ağaç | LOD1 288 | LOD2 tavanı 172 | 40 tri | 250–1000 m ağaç × 40 tri |
|---|---:|---:|---:|---:|---:|
| 25/ha | 69 | 20k tri (900k'nın %2,2'si) | 12k | 2,8k | 1.346 × 40 = 54k |
| 100/ha | 276 | 80k (%8,8) | 47k | 11k | 5.384 × 40 = 215k |
| 300/ha | 828 | 238k (%26) | 142k | 33k | 16.152 × 40 = 646k |

Gölge geçişi bu bantta yaklaşık ×2 ekler: bina gölge menzili 700 m (`building_view_config.gd:20`). Alpha fragment kaba hesabı da var. Çınar LOD1'in 64 kartının iki yüzlü alanı ≈416 m² (`build.py` dağılımlarından beklenen değer), rastgele yönde izdüşüm ≈208 m². Alpha-scissor `discard` ile çalıştığı için üçgenin örttüğü her piksel shade edilir. 120–250 m bandının alan ağırlıklı ortalaması 1080p'de ≈67 px/m². Bu, ağaç başına ≈14k fragment eder. ρ=100'de bu ≈3,9M fragment, yani ≈1,9 tam 1080p ekran alpha-test overdraw'u demektir (+MSAA, +gölge haritası). TBDR iPad GPU'sunda discard'ın HSR'ı bozması bilinen bir risktir; bu proje cihazında **ölçülmedi, varsayım**.

**Yanıt:**
- (i) Bant tek başına bütçeyi "kesin bozar" demek için veri yok. ρ≈100/ha cadde/park yoğunluğunda LOD1, 900k payının ≈%9'unu (gölgeyle ≈%18) tek bantta tüketir; kit v1 hesabına göre bu pay boş değildir. Bu kabul de ret de değildir.
- (ii) Bu bantta asıl risk üçgen değil, alpha overdraw ve gölge geçişi olabilir (varsayım). LOD2'nin kazanç kapısı bu yüzden fragment alanını da ölçer.
- (iii) Aritmetikle kesin olan: 250–1000 m'de tekil ağaç ağı ρ≥25/ha'da 40 tri ile bile 54k–646k eder; 172 tri ile ρ=100'de tek başına 900k'yı geçer. Tekil zincir bir yerde hücre HLOD'una devretmek **zorundadır**. Tekil ≤40 proxy'nin varlığı bu devri kaldırmaz.
- (iv) Mimari not (doğrulandı, `building_lod.gd:8–11`): `visibility_range` mesafeyi düğümün/MultiMesh'in AABB merkezinden ölçer. 1 km chunk MultiMesh ile ağaç başına 120 m'lik bir eşik uygulanamaz. Bitki hücre boyu veya örnek başına CPU kovalama, entegrasyonda godot-engineer'ın ölçümle vereceği ayrı bir karardır; burada sayı verilmez.

**Ölçülmeyen ve gereken ölçümler:**
- (1) Bölge başına ağaç yoğunluğu: dünya/yerleşim verisi yok.
- (2) Göreli lab kıyası: aynı sahnede sabit N örnekli grid, LOD1 ile LOD2 karşılaştırması 120–250 m'de. Compatibility, geliştirme Mac'i; ort/p95 ms, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, draw call, gölge açık/kapalı. Bu yalnız göreli kanıttır, şehir kabulü değildir.
- (3) iPad cihaz ölçümü: zincir denenmedi.
- (4) Gerçek şehir sahnesinde birleşik yük: ADR-0001'e göre ölçülmedi.
- (5) Otomatik mesh LOD'un önceki karelerde neyi çizdiği.

Tek ağaç mikro ölçümü bunların hiçbirinin yerine geçmez.

### 4.2 İlk aday: görünürlük-sıralı alt küme LOD2 (yalnız çınar)

**Neden bu aile.** İki FAIL'in ortak nedeni, temsilin kaynak yaprak kartlarını ve aralarındaki alpha boşluklarını başka bir şeyle (düzlem projeksiyonu veya kapalı yüzey) değiştirmesiydi. Alt küme LOD2 bunu yapısal olarak engeller. Kalan her kart LOD1'deki yerel konumunu, gerçek normalini, UV'sini, alpha maskesini ve materyalini bit-eşit korur. Alt küme LOD1'de olmayan bir yüzeyi dolduramaz; yalnız kart çıkarabilir. Bu yüzden boşluklar korunur ve yeni boşluk miktarı sabit bir kapsama koşuluyla sınırlanır. Kaybedilebilecek tek şey gizli içerdir. Mevcut LOD1 materyali (tek atlas, alpha-MASK 0,45, çift taraf, gölge al/at) **olduğu gibi yeniden kullanılır.** Yeni Texture2D, sampler, shader, `proxy_canopy`, AO veya tint yok.

**Üretim tarifi (deterministik, tek geçiş):**
1. **Girdi:** `assets/hero/vegetation/veg_hero_plane_a_lod1.glb`, `vegetation_atlas.png`, `atlas_layout.json`. Üçünün SHA-256'sı kaydedilir. Ana dosyalara yazılmaz.
2. **Ayrıştırma:** Üçgen sınıfı UV'nin düştüğü atlas bölgesinden (`plane` = yaprak, `bark` = odun) belirlenir. Vertex'ler **tam float32 konum eşitliğiyle** kaynaklanır (tolerans yok) ve bağlı bileşenler çıkarılır. Beklenen yapı tam olarak **64 yaprak bileşeni × 2 tri** ve **20 odun bileşeni × 8 tri**. `tube()` her segment halkasını kendi ekseniyle kurduğu için her segment ayrı bileşen olur. Başka bir sonuç çıkarsa üretim **hata verir ve durur**; sezgisel düzeltme yapılmaz. Segment yönü halka yarıçapından bulunur (büyük yarıçap = proksimal). Ebeveyn ilişkisi, proksimal halka merkezi ile ebeveynin distal halka merkezi arasında ≤1 mm eşleşmeyle kurulur. Her kart, centroid'ine en yakın dalın distal uç merkezine atanır: 8 küme. Eşitlikte GLB üçgen sırası kullanılır.
3. **Çıkarılamaz öğeler:**
   - Yere değen gövde segmenti.
   - Proksimal ucu en yüksek dal tabanının (z≤5,3 m Blender) altında kalan gövde segmentleri.
   - Her dalın gövdeye bağlı ilk segmenti. Bunlar 120 m'de görülen "dallanmış gövde"yi taşır; shell FAIL'inde bu kaybolmuştu.
   - Bir segment ancak distal çocuğu kalmamışsa çıkarılabilir. Kartlar kapsama koşuluna tabidir.
4. **Görünürlük rasterı (çevrimdışı, Python + Pillow 11.3.0 veya kurulu Blender 4.5.14'ün kendi Python'u; yeni bağımlılık yok):**
   - Ortografik ID z-buffer, **24 px/m** çözünürlükte. Bu değer, hedef profillerde 120 m'deki en yüksek px/m'ye (iPad 13" 23,6) yuvarlanmıştır. Daha yüksek çözünürlük daha muhafazakâr sonuç verir.
   - **17 sabit bakış:** 8 azimut (0°, 45° … 315°) × {12°, 40°} yükselti (sokak ve ilçe pitch'i) + tepeden 90°.
   - Her pikselde atlas taban seviyesinden en yakın texel alpha'sı okunur; ≥0,45 ise kapsar. Mip etkisi çevrimdışı modellenmez; Godot karelerinde görülür.
   - Öğe puanı = 17 bakışta en önde göründüğü piksel sayısı.
5. **Açgözlü çıkarma:** En düşük puanlı çıkarılabilir öğe çıkarılır (eşitlikte GLB sırası). Her adımdan sonra puanlar yeniden hesaplanır. Bir sonraki çıkarma şu koşullardan birini bozacaksa durulur:
   - (a) Her bakışta toplam alpha kapsaması ≥ 0,98 × LOD1.
   - (b) Her bakışta her kümenin kendi kart birleşim maskesi (başka kümelerin örtmesi hesaba katılmadan) ≥ 0,90 × LOD1. Böylece hiçbir küme incelip kaybolamaz.
   - (c) Her bakışta önde görünen odun pikseli ≥ 0,95 × LOD1.

   Bu altı değer (17, 24, 0,45, 0,98, 0,90, 0,95) **bu kararda bir kez sabitlenir. Sonuca bakıp değiştirilmez.**
6. **Yazım:** Saf Python GLB yazıcısı kullanılır. Kalan üçgenlerin vertex'leri ilk kullanım sırasıyla sıkıştırılır. POSITION/NORMAL/TEXCOORD_0 baytları LOD1'den aynen kopyalanır; index yeniden numaralanır. Materyal JSON'u aynen kalır. Görüntü URI'si `../vegetation_atlas.png` olur (`normal_experiment/plane_proxy.glb` emsali). Import, ana atlasla **aynı** `res://assets/hero/vegetation/vegetation_atlas.png` Texture2D'sini yüklemelidir. Yüklemezse durulur; atlas kopyalanmaz.
7. **Provenance JSON:** girdi hash'leri, 84 öğenin kimliği/tipi/kümesi/puan geçmişi, çıkarılan sıra, durmaya yol açan koşul, bakış başına kapsama/küme/odun oranları, alpha öncesi fragment alanı, bilgi amaçlı ön-yüz lineer albedo ortalaması. Albedo ortalaması kapı değildir, tanıdır.

**Bütçe gerekçesi.**
- Görevin önerdiği 60–120 aralığı a priori seçilemez. Çınarda yalnız yaprak kartları 128 tri; 120'nin altına inmek görünür kart silmeyi zorlar. Bu, ilk QA FAIL'ini (seyrek yamalar, taç kütlesi kaybı) tekrar üretir.
- **floor(0,6×LOD1)** bir kazanç kapısıdır, kalite hedefi değildir. Yeni bir seviye; asset, test sözleşmesi, geçiş riski ve bant başına draw call getirir. LOD1'e göre en az %40 üçgen ve %20 fragment tasarrufu sağlamıyorsa LOD1'i uzatmak daha basit ve görsel olarak daha güvenlidir.
- Beklenti (**hipotez**, doğrulanmadı): gizli distal dal ve üst gövde ≈64–80 tri, iç kartlardan bir miktar daha. Sonucun 172'nin altına inip inmediği deneyin ta kendisidir.

**Değerlendirilip ilk aday seçilmeyen yollar:**
- **LOD1'i doğrudan HLOD sınırına uzatmak:** Görsel süreklilik kusursuzdur ve geçiş yoktur, ama kazanç sıfırdır. Deneyde **kontrol ve geri dönüş yolu** olarak tutulur. LOD2 kazanç kapısını geçemezse veya sanat FAIL alırsa, maliyeti §4.1-D ölçümleriyle karar verilecek varsayılan yol budur.
- **Çok görünüşlü octahedral impostor:** Kaba hesapla 8×8 görünüş × 128² RGBA ≈4 MiB/tür/harita; normal veya derinlik haritasıyla iki katı; 8 türde onlarca MiB. Compatibility'de özel shader, görünüş seçimi/harmanlama, derinlik/parallax ve alpha kenar sorunları var. Godot'da hazır impostor desteği olduğu **doğrulanmadı**. Reddedilen kart ailesinin yüzey/ton sorunlarını yeniden açar. İlk aday değildir. Yalnız çok küçük ekran kaplamasında ihtiyaç kanıtlanırsa ayrı karar konusu olur.
- **Yalnız eşik/mesafe değişikliği** (6-tri kartları 250 m'ye itmek): 250 m'de çınar hâlâ 81–156 px boyundadır (§4.1-A). Kusur gizlenir, çözülmez. Yasak.
- **Küme başına küçük hull'lar:** Hâlâ kapalı ve fasetli yüzeyler; küme içi alpha boşluğu kaybolur. Shell FAIL'inin daha küçük ölçekli tekrarıdır.

### 4.3 Sonlu deney: tek çınar

**Yerleşim:** Üretici, raster ve raporlar `experiments/t057-lod2/` altına gider (`experiments/.gdignore` geçerli; runtime dosyası konmaz). İthal adaylar ve lab `assets/hero/vegetation/lod2_experiment/` altına gider. Burada ana LOD0 ve LOD1 baytlarının birer kopyası ile LOD2 bulunur, üçünün importu `generate_lods=false`. Lab, `shell_experiment/lab.gd` desenini izler: `--level=lod0|lod1|lod2|lod1_main` ve `--sun_yaw_offset`. Işık, kamera, zemin ve figür orijinal labla aynıdır.

**Ön kapılar (render'dan önce, otomatik):**
- (P1) Ayrıştırma 64+20 bileşen verir.
- (P2) LOD2'nin her üçgeni (konum, normal, UV) LOD1'de bit-eşit bulunur.
- (P3) Kapsama koşulları raporlanan değerlerle bağımsız yeniden hesapta tutar.
- (P4) Kazanç kapısı: tri ≤172 ve fragment alanı ≤0,80 × LOD1.
- (P5) İki tam üretim bayt-eşit (GLB + provenance).
- (P6) Gerçek importta 1 surface, BaseMaterial3D alpha-scissor 0,45, çift taraf, ana atlasla aynı Texture2D, mipmap var, import edilen üçgen = GLB üçgeni.
- Negatif denetimler anlamlı ve sıfırdan farklı çıkışla düşmelidir:
  - (N1) Bir LOD2 vertex'i 1e-4 m kaydırılır → P2 düşer.
  - (N2) Görünür bir dış kart silinir → P3 kapsama düşer.
  - (N3) Import'ta `generate_lods=true` yapılır → denetim düşer.

**P1/P2/P5/P6 başarısızsa** bu bir uygulama hatasıdır: düzelt ve yeniden çalıştır (bu tuning sayılmaz). **P4 başarısızsa** LOD2 render edilmez; "LOD2 kazanç yok" kaydedilir ve yol LOD1 uzatmaya döner. Sabit değerler değiştirilmez.

**Ham Godot kareleri (1600×900, 4×MSAA lab varsayılanı, önceki karelerle aynı origin/kamera/ışık/LOD0 bbox çerçevesi):**

| # | Koşul | Seviyeler | Kare |
|---|---|---|---:|
| K1 | 150 m ön / yan / üst, güneş +0° | lod0, lod1, lod2 | 9 |
| K2 | 150 m ön, güneş +60° | lod0, lod1, lod2 | 3 |
| K3 | 120 m ön, güneş +0° (LOD1→aday sabit çifti) | lod1, lod2 | 2 |
| K4 | 250 m ön ve üst, güneş +0° (tanı) | lod0, lod1, lod2 | 6 |
| K5 | 150 m ön, `--aa=off` (AA bağımlılığı tanısı) | lod1, lod2 | 2 |
| K6 | 150 m ön, `lod1_main` (otomatik LOD karıştırıcısı) | lod1_main + primitives monitörü | 1 |

Her kare için `frames.json` tutulur: yol, komut, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, draw call. K6 ile K1'deki lod1 arasındaki primitive farkı otomatik LOD'un etkisini sayısal olarak gösterir.

**Bağımsız art-director kararı (ham PNG'leri tek tek açarak, sırayla):**
1. **Kontrol:** K1/K2/K4'te LOD1, aynı mesafedeki LOD0'a göre kabul edilebilir mi? Değilse LOD2 yapısı gereği geçemez (LOD1'in alt kümesidir). Deney "LOD1'in kendisi 150 m'de yetersiz" bulgusuyla durur ve sorun LOD1 menziline taşınır. LOD2 hükmü verilmez.
2. **Aday:** K1–K3'te LOD2, LOD1'e göre değerlendirilir. **FAIL** sayılanlar:
   - Taç belirgin biçimde incelirse veya içinden arka plan görünürse.
   - Bir küme kaybolursa.
   - Kütle veya ton sıçraması olursa; özellikle iç kartların öz-gölgesi kalkınca taç açılırsa.
   - Dal ile gövde kopuk görünürse.
   - Panel, X veya şerit çıkarsa.

   K4 ve K5 tanıdır, tek başına PASS/FAIL nedeni değildir. Hash, üçgen ve import geçişleri sanat PASS'ının yerine geçmez.

**Hareketli kamera testi:** Gerekli, ama **yalnız statik çift sanat PASS aldıktan sonra.** Sabit çift zaten başarısızsa anlamsızdır. Yöntem: lab-only deterministik dolly. Ön bakış ekseninde 100→160 m, kare başına 1 m (duvar saatine bağlı değil, kare indeksine bağlı), 120 m'de sert geçiş, 61 PNG. Ek olarak her kare için tree-bbox maskesinde ardışık karelerin ortalama mutlak luminans farkı ölçülür. "Pop oranı" = geçiş karesindeki fark / geçiş dışı karelerin medyanı. Art-director 118–122 m karelerini ve şeridi açar. Pop oranı bu deneyde **kapı değildir**; §4.4 için kayıt altına alınır. Compatibility'de `visibility_range_fade_mode`'un çalışıp çalışmadığı **doğrulanmadı**. Fade yalnız bilgi amaçlı ayrı bir koşu olabilir.

**Yazılı durma koşulu:** Tek üretim, tek render seti, tek sanat hükmü.
- **Sanat FAIL'i** (kontrol geçtiyse): alt küme LOD2 ailesi T-057 için **REJECT** edilir. Başka kapsama eşiği, başka bakış seti, kart büyütme, renk, AO, alpha veya diğer 7 türe yayma yok. Üç temsil ailesinin başarısızlığı, "tekil ağaç başına ayrı uzak mesh gerekir" varsayımını düşürür. Sonraki karar yeni bir temsil denemek değil, **LOD1 uzatma (ölçülmüş maliyetle) + hücre HLOD görevi** arasında olur. Bu karar §4.1-D ölçümleri (2) ve (1) olmadan verilmez.
- **Sanat PASS'ı:** hareketli test yapılır. O da geçerse aynı sabit tarif kalan 7 tür için ayrı bir karar notuyla planlanır. Pine/cypress/olive küme ve dal kuralı türe göre ayrıca tanımlanmalıdır; servide odun %5 olduğu için kazanç kapısını geçemeyebilir. Bu, tür başına "LOD2 yok, LOD1 uzar" sonucu olarak kabul edilir.

### 4.4 Mesafe ve geçiş politikası (sayı yok, kural)

Eşik ancak görsel olarak kabul edilmiş bir temsil çifti (A→B) için belirlenir:

1. **Geometrik hata ε_m (metre):** A ve B, 17 bakışta yüksek çözünürlükte (≥100 px/m) alpha maskesiyle rasterize edilir. ε_m = simetrik fark pikselleri ile diğer maskenin en yakın pikseli arasındaki mesafelerin 95. persentili, metre cinsinden.
2. **Ekran hatası:** `e_px(d) = ε_m · H_px / (2·d·tan(FOV/2))`. Geçiş mesafesi `d* = ε_m · H_px / (2·tan(FOV/2)·e_max)`. Platform profili başına ayrı hesaplanır (ADR-0004 karar 1: render LOD profilin parçasıdır; iPad 13"ün eşiği 1080p'nin ≈1,9 katı). e_max sayısı burada uydurulmaz. **Çapası, art-director'ın kabul ettiği bir geçişin ölçülmüş e_px'idir** (örn. kabul edilmişse LOD0→LOD1). Godot'nun mesh LOD piksel eşiği varsayılanı bu sürümde **doğrulanmadı**; çapa olarak kullanılmaz.
3. **Ton koşulu:** Godot'da `d*` civarındaki gerçek karelerde ağaç maskesinde ΔL ve pop oranı, aynı çapa geçişinin ölçülen değerini aşmamalıdır.
4. **Uygulama payı:** `visibility_range` AABB merkezinden ölçtüğü için (`building_lod.gd`), hücre MultiMesh'inde `begin = d* + r_hücre` (yarım köşegen) alınır; histerezis margin ile verilir.
5. **Maliyet tarafı:** `d*` yalnız "daha yakında geçilemez" sınırıdır. A'nın bu bantta maliyeti ölçülmüş bütçe içindeyse geçiş daha uzağa konabilir. Daha yakına çekmek ise yasaktır.
6. **Belgeleme:** Seçilen her eşik ölçüm dosyası ve hesapla birlikte kaydedilir. Önceki 50/120 m değerleri "working-model-not-integrated" kalır ve PASS diye yeniden etiketlenmez.

### 4.5 Sözleşme: deney sırasında kesin kural, benimsenirse değişecekler

**Deney sırasında (kesin kural, istisnasız):** Yazılabilecek yerler yalnız `experiments/t057-lod2/` ve `assets/hero/vegetation/lod2_experiment/`. Şunlar **değişmez:**
- `data/library/catalog.json` (91 kayıt; 81 eski kayıt tam içerikle).
- 30 ana bitki GLB'si ve `.import`'ları.
- `vegetation_atlas.png` ve `atlas_layout.json`.
- 10 LOD0.
- `proxy_bakes.json`, `proxy_canopy.*`, `proxy_import.gd`.
- `shell_experiment/` ve `normal_experiment/`.
- `art/blender/vegetation/*`, `tools/library/*`, `tests/library/*`.
- Shell `preservation.json`'daki 44 ana asset/policy dosyası; 67 GLB + 14 PNG.

Deney sonunda aynı küme yeniden hash'lenir ve `experiments/t057-lod2/preservation.json` yazılır. Ana testler deney için değiştirilmez.

**Benimsenirse (yalnız sanat + hareketli test PASS ve ayrı bir benimseme görevi sonrası), birlikte güncellenecekler:**
- `production/tasks/T-057.md` ölçüt 1–2: "LOD0/LOD1/proxy" ve "proxy ≤40". Palmiye dışı için yeni metin: "LOD2 ≤ floor(0,6×LOD1), mutlak ≤180; tekil zincir hücre HLOD'unda biter". Palmiyeler mevcut 40-tri PROXY'de kalır; onların uzak kabulü de ayrıca kanıtlanmamıştır. Görev metnini Studio Director günceller. Önerilen yer bu değişiklik için yeni bir ADR (bitki LOD zinciri). Kit v1 §9 / README §5.2'deki "bitki 72/12" ÇM bütçesi ile T-057'nin 1800/300 hero değerleri arasındaki çelişki entegrasyondan önce o ADR'de çözülmelidir.
- `art/blender/vegetation/derive_lod2.py` (yeni, saf Python) ve `rebuild.sh`: `build.py --base-only` → `derive_lod2.py` → katalog. Palmiye dışı türlerde `bake_proxies.py` / `pack_proxies.py` / `--proxy-only` adımları kaldırılır. Atlasın y640–1023 bölgesindeki tile'lar önce **bayt-eşit bırakılır** (ölü piksel). Atlası sıfırlamak, kendi drift testi olan ayrı bir adımdır. `build.py` budget sözlüğüne LOD2 eklenir ve PROXY yalnız palmiyelerde kalır. Wrapper uçtan uca bir kez gerçekten çalıştırılır (önceki devirde yalnız `bash -n` yapılmıştı).
- `vegetation_catalog.py`:
  - `limits()` içine LOD2 kuralı.
  - `measure_chain` seviyeleri LOD0/LOD1/LOD2 (+ palmiye PROXY).
  - `proxy_source`/`proxy_runtime` (AO 0,55, AO_LIGHT_AFFECT 0,75 alanları) yerine `lod2_source`: LOD1/atlas/derive script SHA'ları, sabit parametreler, kalan öğe listesi hash'i, kapsama oranları.
  - `distances_m.status = "unset-pending-measurement"`.
  - `check_vegetation_proxy_tiles.py` çağrısı yalnız tile'lar tutuluyorsa yapılır.
  - `validate_chain`: LOD0 > LOD1 > LOD2 monotonluğu, LOD2 ⊂ LOD1 bit-eşit alt küme, cap, provenance hash, kapsama yeniden hesabı, `.import` içinde `generate_lods=false` ve boş `import_script`.
- `check_vegetation_import.gd`: palmiye dışı canopy ShaderMaterial dalı ve `AO = 0.55` / `AO_LIGHT_AFFECT = 0.75` / `local_position - canopy_center` aramaları, `proxy_canopy.gdshader` / `proxy_import.gd` dosyalarıyla **birlikte** emekliye ayrılır. LOD2 mevcut BaseMaterial dalından geçer: scissor 0,45, cull disabled, tek paylaşılan Texture2D, mipmap, gölge atma açık. Sayaç `canopy_checked == 8` yerine `lod2_checked == 8` olur; toplam mesh sayısı seviye listesinden türetilir, sabit 30 değil. Kalite denetimi kaldırılmaz, konusu değişir.
- `tests/library/test_vegetation_catalog.py`:
  - `test_nonpalm_proxy_uses_complete_source_views_and_bounds` (6 tri / 12 UV) yerine `test_nonpalm_lod2_is_bitwise_subset_of_lod1` ve `test_lod2_coverage_meets_fixed_constraints`.
  - `test_proxy_runtime_shader_drift_is_rejected` ve `test_proxy_import_assignment_missing_is_rejected` yerine `test_lod2_import_rejects_auto_lod_or_custom_script`.
  - Korunacak negatif testler: `test_lod2_vertex_perturbation_is_rejected`, `test_lod2_outer_card_removal_fails_coverage`, `test_lod2_over_cap_is_rejected`, `test_lod2_provenance_drift_is_rejected`.
  - Tile testleri tile'lar kaldığı sürece kalır.
  - `test_ten_proposals...` sırası LOD1 > LOD2 olur.
  - Değişmeyenler: user-field koruma, kaynak tipi yönlendirme, bozuk source, eski 81 kayıt.
- Kontak sayfası, galeri ve `index.json` LOD2 kolonu alır; `design/library/vegetation-hero.md` güncellenir.
- Ana 30 importtaki `generate_lods=true` sapması aynı benimseme görevinde düzeltilir ve testle kilitlenir.

### 4.6 Uygulayıcı rolleri (tek uzman sıralı, aynı anda tek Godot)

1. **technical-artist** (sonnet): `experiments/t057-lod2/` altında ayrıştırma, görünürlük rasteri, açgözlü çıkarma, GLB yazıcı, provenance, P1–P5, N1–N2, iki üretim determinizmi. Godot gerekmez. P4 FAIL ise burada durur ve rapor verir.
2. **godot-engineer** (sonnet): `assets/hero/vegetation/lod2_experiment/` altında import (`generate_lods=false`), runtime audit (P6, N3), lab scripti, K1–K6 capture'ları ve primitives/draw call kaydı, `preservation.json`. Tek Godot süreci; yalnız kendi PID'i.
3. **art-director** (opus): ham PNG'ler tek tek açılır; önce kontrol sorusu, sonra aday. Sonuç `production/qa/T-057-art-review.md` dosyasına eklenir.
4. PASS ise **godot-engineer** hareketli dolly testini yapar → art-director yeniden bakar. Ardından istenirse göreli N-örnek lab kıyası (§4.1-D ölçüm 2) yapılır.
5. **qa-engineer**: bağımsız doğrulama. **technical-director**: benimseme veya ret kararı. Benimseme görevi ayrıca açılır.

Her aşama sonunda safe pause. Bu deney final full, kontak/galeri yenileme veya oyun entegrasyonu başlatmaz.

### Doğrulanan / varsayılan / test edilmemiş

- **Doğrulanan (dosya okundu):**
  - FOV 40° (oyun + lab).
  - Çınar LOD1 = 128 yaprak + 160 odun tri; GLB 576 vertex / 864 index.
  - Diğer türlerin LOD1 dağılımı `build.py`'den hesaplandı ve `index.json` ile eşleşiyor.
  - 30 ana importta `generate_lods=true`.
  - `visibility_range` AABB-merkez davranışı (`building_lod.gd` notu; T-012 ölçümü, ben tekrarlamadım).
  - Bütçe metinleri (ADR-0001, kit v1 §9, README §5); iPad ölçümünün olmadığı.
  - `../vegetation_atlas.png` URI emsali.
  - `check_vegetation_import.gd` ve testlerin eski shader metnine bağımlılığı.
- **Hesap (ölçüm değil):** piksel tablosu, bant alanları, ρ'ya göre üçgen tablosu, fragment kaba hesabı.
- **Varsayılan:** ρ değerleri; iPad modeli ve doğal çözünürlükte render; TBDR discard maliyeti; LOD2'nin 172'nin altına ineceği; iç kart öz-gölgesinin kalkmasının tonu etkilemeyeceği (risk, sanat kapısında görülür).
- **Test edilmemiş / çalıştırılmamış:** Bu kararın hiçbir adımı. Önceki karelerde otomatik LOD'un etkisi. Compatibility'de fade. Godot'nun `../` URI ile aynı Texture2D'yi paylaşması (emsal raporu var, ben doğrulamadım). Kent, iPad ve birleşik yük performansı.
