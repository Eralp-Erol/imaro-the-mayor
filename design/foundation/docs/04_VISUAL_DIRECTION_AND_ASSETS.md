# 04 — Sanat yönü, onaylanan görseller ve görsel olmayan kararlar

## Görsellerin rolü: sınırları belli yaratıcı referanslar

Bu paketin görselleri art direction, kentsel kimlik ve büyüme farkını gösteren **referanslardır**; tamamlanmış 3D model, sabit GIS, tek doğru şehir planı, zorunlu oyuncu geleceği veya onaylı UI değildir.

### Referans A — `01_anderva_approved_country.png`

**Statü: ülkenin kullanıcı onaylı genel görsel referansı.** Ana karanın sürekliliği, batıdaki Ismeral bölgesi, birbirinden farklı coğrafi kuşaklar, yedi okunabilir büyük kent, stilize ve okunabilir kuşbakışı dünya. Üzerindeki menu, olası nüfus/ekonomi sayıları, kampanya panosu, Orven'den zorunlu başlama iması, görseldeki tüm yan metinler **kanon değildir**. `01b` dosyası aynı görselin alt kampanya şeridi kırpılmış hâlidir; ayrı tasarım onayı yoktur.

### Referans B — `02_ismeral_t0_vs_mature_SELECTED.jpg`

**Statü: kullanıcı tarafından açıkça seçilen Ismeral karşılaştırması.** İki durum arasındaki gelişmişlik farkı, büyük körfez çevresinde D1+D6 çekirdeği, diğer bölgelerde açık gelişme potansiyeli, büyümüş metropolün çok merkezli ve ekonomik olarak karmaşık olması, T0 ile ilerlemiş şehir arasındaki dramatik fark. Metinde belirtilen **T0 limanı ana karada, D4'ün batısı** kuralı görselin her pikselinden üstündür. Adacıkların, iskelelerin, binaların, çizilmiş otoyolların ve ilçe sınırlarının tam konumu **kilitlenmedi**. İleri durum tek zorunlu ilerleme değil; bir örnek.

### Referans C — `03_ismeral_mature_architecture_DIRECTION.png`

**Statü: daha önce beğenilen mimari, atmosfer ve büyük metropol okunurluğu için ikincil yön.** Yoğun/seyrek doku arasındaki farklar, yaşanmış tarihî çekirdek, modern kent silueti, sanayi/logistik üretim, kamu yapıları, yüksek/orta/alçak yoğunluk, Ege/İzmir şehir hayatı. **Eski görselde hatalı liman/ada konumları, bölge sınırları ve ekrandaki kartlar devralınmaz.** Güncel seçilen karşılaştırma ve yazılı T0 kararları önceliklidir.

### Onay matrisi

| Özellik | Onaylanan / amaçlanan | Birebir alınmayacak |
|---|---|---|
| Ülke | Stilize kentsel coğrafya ve 7 anlamlı metropol | UI, istatistik, yan karakter kartları, kesin GIS |
| Ismeral | İzmir/Ege'yi çağrıştıran **gerçek metropol** ve tarihsel katman | Şekli sabit render kıyı çizgisi, tek tip turistik evler |
| T0 | D1+D6 kompakt ama yaşayan şehir; diğerlerinde küçük merkezler | Görselde birebir bina, stadyum, ada, yolların konumu |
| Olgun şehir | Geniş iş/konut/sanayi dokusu; yüksek ama çeşitli kentsel yoğunluk | Her oyuncunun aynı gökdelen/liman geleceğine zorlanması |
| Yakınlaşma | Aynı arazide şehir → sokak → insan ölçeği | Dört bağımsız resmin oyun dünyasını oluşturması |

## Görsel dil — uygulanabilir ama tek asset reçetesi olmayan tarif

**Ana hedef:** Üretilebilir gerçek zamanlı **low-key low-poly 3D**; şehir kütlesi yakın ve uzak ölçekte anlamlı, yoğun ama okunabilir, göz yormayan malzeme ve cepheler. Ülkede ve ilçede aynı sanat grameri. Modern, katmanlı Ege kent dokusu: farklı dönem apartmanları, ticari zemin katları, küçük sanayi, depolar, eski sanayi tuğla/taş/beton izleri, ofis ve yüksek bina kümeleri, kamusal altyapı, yürünebilir kıyılar, tramvay/feribot ilişkileri, ovalar, yamaçlar.

- **Tarık Tolunay Fractal:** kentin katmanlı yoğunluğu ve uzaktan okunurluğuna *esin*. Stil/kompozisyon doğrudan kopyalanmaz.
- **Tropico:** altyapının ve canlı toplumun şehirle kurduğu hissedilir ilişki; doğrudan kopya oyun/sanat hedefi değil.
- **Minecraft:** okunabilir sade hacim mantığı; pikselli/voxel estetiği zorunlu değil.
- **İzmir:** büyük körfez etrafında yaşanan şehir, karşı yaka, sanayi/liman, tarihî çarşı, meydan, saat kulesi, antik kalıntı, stadyum, üniversite ve çok dönemli mimari. Ne birebir İzmir haritası ne de Adriyatik turizm dekoru.

**Yakından / insan seviyesinde:** Binalar ve yollar maket değil kullanılabilir ölçekte hissedilmeli. Saat kulesi 5 katlı apartmanın çok üzerinde dev bir gökdelen gibi görünmemeli. Parklar, kaldırımlar, kamusal meydanlar, dükkânlar, servis araçları, günlük hayat vardır; antik kalıntılar dağların tepesine rasgele dekor olarak yerleştirilmez.

**Uzak ölçekte:** Metropol geniş, kentsel kütlesi çeşitli ve büyüme potansiyeli olan bir sistem olarak okunmalı. Tarım alanı yalnızca boş renk lekesi değil; sanayi yalnızca 3 konteyner; karşı yaka yalnızca birkaç turist evi değildir.

**Konseptlerdeki sinematik/gerçekçi efektler birebir gerçek zamanlı render hedefi değildir.** Orada onaylanan başta mimari/kentsel yerleşim hissidir; teknoloji ekibi bunu sürdürülebilir, tutarlı oyun grafik diline aktaracaktır.

## Kesin kaçınılacak hatalar

- Ülke haritasını metropol haritasında ikinci kez yaratmak; Ismeral'i bağımsız takımadalı mini ülkeye çevirmek.
- Her zoom'da farklı kıyı, dağ, nehir, yol, bina kütlesi icat etmek; oyunda tek dünya yerine ayrı dioramalar göstermek.
- T0 batı limanı/ana sanayiyi adaya koymak; tüm üretimi marinalarla değiştirmek.
- Ismeral'i küçük bir turistik kıyı kasabası yapıp sanayiyi, karşı yakayı, meydanları, stadyumu, tarihî sanayiyi ve antik izleri unutmak.
- Adriyatik/Venedik taş köprüsü, kanallar, kilise kuleleri, bütün çatılarda aynı kırmızı kiremit, parlak tatil köyü hissine kaymak.
- Saat kulesi / ağaçlar / dağlar / araçlarda ölçek sapması; oyuncak SimCity BuildIt estetiği ya da ağır hiperreal CGI'ı hedeflemek.
- Ülkenin diğer altı şehrini minicik kasabalar yapmak; Orven'i zorunlu başlangıç olarak işaretlemek.
- Konsept resimlerde yazan ekonomi sayıları, harita ölçeği, coğrafi yön okları veya yapay UI'ın onaylı olmasını varsaymak.

## Görsel kaliteyi ölçen asıl sorular

1. Bu yer, açıkça **İzmir'den beslenen özgün bir çağdaş şehir** ve gerçek bir karma metropol gibi okunuyor mu?
2. T0, boş kasaba değil, çalışan ama büyümeye açık bir şehir mi? D1+D6 anlamlı kentsel çekirdek mi?
3. Ana karada liman/sanayi yerinde mi; adalarda T0 büyük sanayi yok mu?
4. Kent mimarisinde eski/tarihî, orta dönem ve yeni yapı stoğu; kamusal hayat, sanayi, konut, ticaret ve tarım bir arada mı?
5. Gelecekte oyuncu kent planını başka yöne çevirebiliyor mu?
6. Ülke/metropol/ilçe/sokak görüntüleri aynı **3D kaynak coğrafyaya** dayanıyor mu ve aynı artistik grameri mi koruyor?

Bunlar *görsel kabul ilkeleridir*. Bu pakette yeni resim veya UI çizilmemiştir.
