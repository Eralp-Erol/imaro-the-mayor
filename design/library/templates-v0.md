# Şablon önerileri v0 — kullanıcı onayına sunulacak

- Statü: **ÖNERİ** (art-director, T-052, 2026-10-25). Buradaki **hiçbir şablon çizilmedi ve hiçbiri onaylı değil.** Her satır katalogda `proposed` olarak başlar; kontak sayfasında çizildikten sonra kullanıcı kimlik bazında `approved / rejected / not` verir. Onaysız şablon oyunda görünmez (T-052 ölçüt 5).
- Kurallar: `design/library/README.md` (palet alanları §2, ölçek §3, bütçe §5, standart ışık §6, isimlendirme §8). Bina şablonları burada değil: `design/specs/art/building-kit-v1.md` §4.
- REQ: VIS-01, VIS-02, VIS-03, VIS-05, VIS-07; WLD-01, WLD-07; CAN-03 (insan/araç sayısı sim verisinden, T-050).
- Sütunlar: **Kimlik** · **Tarif** (silüet + imza ayrıntısı) · **Boyut** (u × g × y m) · **Üçgen** LOD0/LOD1 (README §5 tavanı içinde) · **Palet** (izinli satırlar) · **Referans notu** (ne alındı / ne alınmadı) · **İhtiyaç** (hangi oyun sorununu çözer).
- Dalga: **1** = T-050/T-042 için ilk sayfa · **2** = ikinci tur · **3** = kullanıcı kararından sonra.
- Ölçü ve renk değerleri **[ÇM]**; görsel sonuçları **[DOĞRULANACAK]** (kontak sayfası yok).

Referans gözlemi (yalnız görselde görülen, 2026-10-25'te açılıp bakıldı): `03_*` ZOOM 4 "sokak seviyesi" — geniş döşeme kaldırım, palmiye ve yaprak ağacı sırası, ortada/yanda iki hatlı tramvay, 3+ şeritte akan otomobil, yayalar, uzakta saat kulesi; ZOOM 3 — meydan döşemesi, palmiyeler, iskeleye yanaşmış beyaz gövdeli vapurlar. `02_*` D1/D3/D6 küçük kesitleri — beyaz üst yapılı, renkli gövde bantlı vapur; meydanda kalabalık. Bunlar **tür ve ilişki** ilhamıdır; araç/vapur tasarımı, renk düzeni, şerit sayısı kopyalanmaz (VIS-07).

---

## a) İnsan (`hum_*`)

### a.1 Önce karar: stilizasyon seviyesi (aynı boyda üç örnek yan yana çizilip sorulur)
| Seçenek | Tarif | LOD0 üçgen | Görünür bütçe (street ≤ 80k payının ≈ yarısı) | Artı | Risk |
|---|---|---|---|---|---|
| **A — Piyon** | uzuvsuz: gövde prizması (6–8 kenar) + baş kutusu + saç kapağı | 24–40 | ≈ 1.000 figür | en ucuz, uzakta temiz benek | yakında "oyun taşı/oyuncak" okunur (VIS-05 riski) |
| **B — Blok figür** (art-director önerisi) | 2 bacak + daralan gövde + 2 kol + baş + saç; el/ayak yok; yüz yok | 80–120 | ≈ 350–500 figür | sokakta insan gibi okunur, yürüme salınımı yapılabilir; F04 "okunabilir sade hacim" | çok yakında (< 20 m) kaba |
| **C — Faset figür** | daralan uzuvlar, ayakkabı/el kutusu, burun düzlemi, palto/etek formları | 200–320 | ≈ 150–200 figür | yakında zengin | bütçe; kalabalık seyrekleşir; "yarı gerçekçi" uncanny riski |

Hesap (ölçüm değil): 200 m'de insan ≈ 8 px (README §5.1) → seçenekler arası fark yalnız < ~80 m'de görülür. Bu yüzden karar **yakın sokak kamerasının ne kadar kullanılacağına** bağlıdır.

### a.2 Gövde / silüet tipleri (seçilen seviyede çizilir; çekirdek 6 + isteğe bağlı 4)
| Kimlik | Tarif | Boyut (boy · omuz) | Üçgen (B) | Palet | Referans notu | İhtiyaç | Dalga |
|---|---|---|---|---|---|---|---|
| `hum_adult_m_a` | yetişkin erkek, pantolon + üst; dik duruş | 1,76 · 0,48 | 100 / 14 | üst/alt CL, SK, HR | ZOOM 4 yayaları: gündelik kent giyimi | kalabalığın ana gövdesi; ölçek | 1 |
| `hum_adult_f_a` | yetişkin kadın, pantolon | 1,64 · 0,42 | 100 / 14 | CL, SK, HR | aynı | ana gövde | 1 |
| `hum_adult_f_b` | yetişkin kadın, etek/elbise: alt gövde tek trapez (bacak ayrımı yalnız diz altı) | 1,64 · 0,42 | 90 / 12 | CL, SK, HR | — | silüet çeşitliliği (uzakta etek formu ayırt edilir) | 1 |
| `hum_adult_broad_a` | iri/geniş gövdeli yetişkin (cinsiyet nötr okunur), ceket | 1,74 · 0,56 | 100 / 14 | CL koyu ağırlıklı, SK, HR | — | gövde çeşitliliği; "aynı insan klonu" hissini kırar | 1 |
| `hum_elder_a` | yaşlı, 5° öne eğik, kısa adım; varyant `b` baston | 1,62 · 0,44 | 100 / 14 | yaşlı seti (a.3), HR3 gri | — | mahalle hayatı; F02 "yaşayan şehir" | 1 |
| `hum_child_a` | çocuk, iki boy varyantı (1,12 / 1,32), oran: baş/boy ≈ 1/5,5 (chibi değil) | 1,12–1,32 · 0,32 | 90 / 12 | çocuk/genç seti | — | okul, park, aile; ölçek (çocuk–yetişkin farkı) | 1 |
| `hum_teen_a` | genç/öğrenci, sırt çantası kutusu | 1,68 · 0,44 | 110 / 14 | çocuk/genç seti | — | okul/üniversite çevresi (D5 olgun) | 2 |
| `hum_worker_a` | iş kıyafeti: tulum veya yelek; varyant `b` baret | 1,76 · 0,50 | 110 / 14 | iş seti (CL16 yalnız burada) | — | şantiye, liman, sanayi avlusu: **inşaatın ve üretimin görünür olması** (sim inşaat durumuyla bağlı) | 1 |
| `hum_seated_a` | oturan figür (bank/kafe), kalça 0,45 m | 1,30 (oturuşta) | 90 / 12 | CL, SK, HR | ZOOM 3 meydan hayatı | bank/kafe bölgelerinde durağan yaşam | 2 |
| `hum_vendor_a` | ayakta satıcı, önlük bandı; `fur_simit_cart_a` veya kiosk yanında | 1,74 · 0,48 | 100 / 14 | CL2/CL1 önlük, SK, HR | İzmir sokak hayatı (tür, kopya değil) | çarşı/meydan ticaretinin görünmesi | 2 |

Bisiklet/motosiklet sürücüsü araç şablonunun parçasıdır (b).

### a.3 Renk setleri (palet alanı "insan", README §2.1; değerler öneri, render'da doğrulanacak)
| Satır | Ad | Hex | | Satır | Ad | Hex |
|---|---|---|---|---|---|---|
| SK1 | açık ten | #E0BFA3 | | CL7 | gri-yeşil | #8A8F86 |
| SK2 | orta ten | #C99C7C | | CL8 | zeytin | #6F7448 |
| SK3 | buğday/esmer ten | #A87656 | | CL9 | kısık tuğla kırmızı (aksan) | #8E4A3E |
| SK4 | koyu ten | #6E4A36 | | CL10 | toprak turuncu (aksan) | #A0603F |
| HR1 | siyah-kahve saç | #2A2420 | | CL11 | hardal (aksan) | #C9A04A |
| HR2 | kahve saç | #5A4030 | | CL12 | petrol | #5E7F86 |
| HR3 | gri saç | #9C968E | | CL13 | soluk mor | #7A5A6E |
| HR4 | açık kahve saç | #A5845A | | CL14 | gül kurusu (aksan) | #C98E86 |
| CL1 | kırık beyaz | #E6E1D6 | | CL15 | koyu kahve | #3B2F2A |
| CL2 | bej | #D2C3A5 | | CL16 | iş yeleği turuncusu (**yalnız iş**) | #C47A40 |
| CL3 | açık kot mavisi | #9FB3C2 | | | | |
| CL4 | kot laciverti | #3E5470 | | | | |
| CL5 | gece laciverti | #2E3440 | | | | |
| CL6 | grafit | #5B5F63 | | | | |

Hesaplanan HSV (2026-10-25): tüm CL satırlarında s ≤ 0,63 (CL16 0,67), v 0,25–0,90; SK h 21–28°, s 0,27–0,51. README §2.2 sınırları içinde.

| Set | Üst | Alt | Not |
|---|---|---|---|
| Gündelik açık | CL1, CL2, CL3, CL12, CL14, CL11 | CL3, CL4, CL2, CL8 | gündüz/sıcak hava ağırlığı |
| Gündelik koyu | CL4, CL5, CL6, CL15, CL13, CL9 | CL5, CL6, CL15 | serin hava / akşam |
| Ofis / resmî | CL1, CL5, CL6, CL7 | CL5, CL6 | D1 merkez, kamu yapıları çevresi |
| İş | CL4, CL6, CL8, CL16 (yelek) | CL4, CL6, CL15 | D3, şantiyeler |
| Yaşlı | CL15, CL6, CL7, CL2, CL13 | CL6, CL15, CL5 | — |
| Çocuk / genç | CL3, CL11, CL12, CL14, CL9, CL1 | CL4, CL3, CL6 | — |

Örnek verisi (teknik not, godot-engineer/technical-artist): figür başına 4 satır = üst, alt, ten, saç (`INSTANCE_CUSTOM` 4 kanalı). Binadaki parlaklık sapması kanalı burada yoktur; gerekirse ayrı çözüm.

### a.4 Okunurluk kuralları
- Uzak (> 300 m): **çizilmez** (sahte kalabalık lekesi yok). 80–300 m: LOD1 (≤ 16 üçgen; baş + gövde + bacak bloğu), renk = üst giyim satırı. < 80 m: LOD0.
- Kalabalık ritmi: gruplar (2–4 kişi) + tekil yürüyenler; düzgün aralıklı "asker dizisi" yok. Yoğunluk ve tür sim verisinden (T-050).
- Yüz, logo, yazı, sembol yok.

### a.5 Kullanıcıya sorulacak (insan)
1. **Stilizasyon:** A (piyon), B (blok figür — öneri) mi, C (faset) mi? Yakın sokak kamerasını (< 50 m) ne sıklıkla kullanmayı düşünüyorsunuz?
2. Gövde tiplerinin sayısı: çekirdek 6 yeterli mi, 10'un tamamı mı?
3. **Giyim çeşitliliği ve kimlik işaretleri** (Q-010 içerik tonu AÇIK): kalabalıkta başörtüsü, şapka/kasket gibi kültürel/dini olarak okunabilecek giyim öğeleri yer alsın mı, hangi oranda? (Karar verilene kadar: hiçbiri eklenmez.)
4. **Mevsim/hava:** kıyafet setleri mevsime göre değişsin mi (yaz açık / kış koyu)? Oyunda mevsim var mı? (Karar yoksa: yıl boyu karışık sabit dağılım.)
5. Üniformalı kamu personeli (polis, zabıta, sağlık, itfaiye) görünsün mü? Kurum yapısı AÇIK (F05-D); karar yoksa yok.
6. Protagonist ve adlı karakterler bu kütüphanenin dışında mı kalsın (Q-005, T-026)? (Öneri: evet; `hum_*` anonimdir.)

---

## b) Araç (`veh_*`)

### b.1 Şablonlar
Tüm araçlar: tek mesh, tek surface; tekerlek 6 kenarlı silindir (LOD1'de tekerlek yok, gövde alt bandı koyu); camlar koyu bant (VH13); far/stop ışık yaymaz; plaka/marka/logo/yazı yok. Tüm boyutlar u × g × y m.

| Kimlik | Tarif | Boyut | Üçgen | Palet | Referans notu | İhtiyaç | Dalga |
|---|---|---|---|---|---|---|---|
| `veh_car_hatch_a` | kısa iki hacimli otomobil, dik arka | 4,0 × 1,75 × 1,50 | 120 / 20 | gövde VH1–VH9; cam VH13; alt VH14 | ZOOM 4 akan trafik (tür) | kent trafiğinin çoğunluğu; dar sokak ölçeği | 1 |
| `veh_car_sedan_a` | üç hacimli sedan, belirgin bagaj kademesi | 4,6 × 1,80 × 1,45 | 130 / 22 | aynı | aynı | silüet çeşitliliği; taksi tabanı (b.4 soru) | 1 |
| `veh_car_cross_a` | yüksek gövdeli crossover/SUV, kısa kaput | 4,5 × 1,85 × 1,65 | 130 / 22 | aynı (koyu/beyaz ağırlık) | — | yeni dönem katmanı | 1 |
| `veh_car_old_a` | köşeli 1970–80'ler sedanı (jenerik, marka çağrışımı yok) | 4,4 × 1,65 × 1,40 | 120 / 20 | VH1, VH7, VH8, VH6, VH9 | — | **dönem katmanı** (VIS-02 çok dönemli kent); isteğe bağlı | 2 |
| `veh_minibus_a` | dolmuş/minibüs: tek hacim, yüksek tavan, yan sürgü kapı çizgisi | 6,5 × 2,05 × 2,60 | 160 / 24 | VH1, VH2, VH10/VH11 adayı | İzmir dolmuş hissi (tür) | gündelik toplu ulaşımın sokakta görünmesi | 1 |
| `veh_bus_12_a` | 12 m alçak tabanlı kent otobüsü; geniş ön cam, iki kapı çizgisi | 12,0 × 2,55 × 3,10 | 200 / 28 | gövde VH16/VH1 + livery bandı VH11/VH12 [AÇIK] | ZOOM 4 (tür) | toplu ulaşım kararlarının görünür sonucu | 1 |
| `veh_bus_18_a` | körüklü 18 m otobüs (2 gövde) | 18,0 × 2,55 × 3,10 | 220 / 32 | aynı | — | yoğun hatlar (olgun) | 3 |
| `veh_tram_a` | 5 modüllü tramvay, yuvarlatılmış burun, pantograf | 32,0 × 2,65 × 3,40 (+pantograf 0,8) | 400 / 48 | gövde VH16 + bant VH11/VH12 [AÇIK] | ZOOM 4: orta hatlı, açık gövdeli tramvay (tür; tasarım kopyalanmaz) | tramvaylı kesitin (c) anlamı; ulaşım kararı | 3 (T0'da tramvay var mı? b.4) |
| `veh_van_a` | kamyonet/panelvan, yüksek tavan | 4,8 × 1,90 × 1,95 | 120 / 20 | VH1, VH2, VH3, VH6 | F04 "servis araçları" | esnaf/teslimat; ticaretin sokakta görünmesi | 1 |
| `veh_pickup_a` | açık kasa kamyonet | 5,2 × 1,85 × 1,80 | 120 / 20 | VH1, VH3, VH9, VH8 | — | D4 tarım, D2 atölye | 2 |
| `veh_truck_box_a` | 2 dingilli kapalı kasa kamyon | 8,5 × 2,50 × 3,60 | 160 / 24 | kabin VH1/VH6/VH7; kasa VH1/VH2 | — | dağıtım, sanayi–kent bağı | 1 |
| `veh_truck_semi_a` | tır: çekici + dorse (konteyner dorse varyantı `b`) | 16,5 × 2,55 × 4,00 | 200 / 28 | kabin VH1/VH7/VH6; konteyner A1/A2/A3/W13/R7 (kit) | 02 D3 liman kesiti (tür) | liman/lojistik: VIS-04 "sanayi 3 konteyner değil" | 2 |
| `veh_ferry_a` | yolcu vapuru: koyu gövde bandı + beyaz 2 güverteli üst yapı + kısa baca | 45 × 10 × 9 (su üstü) | 650 / 80; PROXY ≤ 24 | üst yapı VH16/VH1; gövde VH15/VH5 [AÇIK]; cam VH13 | 02 D6 / 03 ZOOM 3 beyaz vapurlar (tür) | **D1↔D6 bağının görünmesi** (WLD-05, F02 feribot); metroda da görünür | 2 |
| `veh_ferry_car_a` | araba vapuru: açık güverte, iki uçlu | 65 × 14 × 8 | 700 / 80 | aynı | — | olgun ulaşım | 3 |
| `veh_boat_fish_a` | balıkçı teknesi: ahşap gövde, küçük kabin | 9 × 3 × 2,5 | 110 / 16 | gövde VH1/VH6/VH15, kabin VH1 | F02 D2 "balıkçılık ilişkili işler" | D2/D3 kıyı hayatı (marina değil, iş teknesi) | 2 |
| `veh_bike_a` | bisiklet + sürücü (blok figür, oturuş pozu) | 1,75 × 0,60 × 1,70 (sürücüyle) | 110 / 14 | çerçeve VH4/VH6/VH7; sürücü CL/SK/HR | — | bisiklet yolu kesitinin anlamı; D6 kıyı | 1 |
| `veh_moto_a` | motosiklet/kurye + sürücü (kask kutusu) | 2,0 × 0,80 × 1,70 | 120 / 16 | gövde VH4/VH7/VH3; sürücü CL | — | D1/D5 dar sokak, teslimat | 1 |
| `veh_svc_garbage_a` | belediye çöp kamyonu (arka sıkıştırma kutusu) | 8,0 × 2,50 × 3,40 | 160 / 24 | VH1 + VH11/VH12 bant [AÇIK] | — | **belediye hizmetinin görünür olması** (oyuncunun kararı sokakta) | 2 |
| `veh_constr_mixer_a` | beton mikseri (eğik silindir) | 8,5 × 2,50 × 3,80 | 180 / 24 | kabin VH1/VH3; tambur VH2/A3 | — | inşaat durumunun görünmesi (sim inşaat, Q-016) | 2 |
| `veh_train_freight_a` | lokomotif (`a`) + yük vagonu (`b`: kapalı, `c`: konteyner) | 18 × 3 × 4,2 / 14 × 3 × 4 | 220 / 28 her biri | VH4/VH7/VH3, vagon R5/R7/A1 | F02 D3 "karayolu/demiryolu ilişkisi" | ağdaki ray hatlarının (`network.json` `rail`) anlam kazanması | 3 |
| `veh_svc_ambulance_a`, `veh_svc_fire_a` | — | — | — | — | — | kurum yapısı AÇIK | 3 |

### b.2 Araç paleti (alan "araç", README §2.1)
| Satır | Ad | Hex | Pay (özel otomobil) |
|---|---|---|---|
| VH1 | beyaz | #E4E3DF | %28 |
| VH2 | gümüş | #B9BCBE | %18 |
| VH3 | orta gri | #85898C | %14 |
| VH4 | antrasit | #3A3D40 | %10 |
| VH5 | kısık siyah | #222427 | %8 |
| VH6 | soluk mavi | #3F5571 | %8 |
| VH7 | kısık kırmızı | #8A524C | %6 |
| VH8 | şampanya bej | #C7B89A | %5 |
| VH9 | koyu yeşil | #4C5A48 | %3 |
| VH10 | sarı (taksi adayı) | #D9B44A | yalnız taksi/servis [AÇIK] |
| VH11 | petrol (kamu bandı adayı A) | #2F6E73 | yalnız kamu [AÇIK] |
| VH12 | bordo (kamu bandı adayı B) | #8E3B3B | yalnız kamu [AÇIK] |
| VH13 | cam / lastik koyu | #2A2E33 | tüm araçlar |
| VH14 | şasi / tampon gri | #6D6A64 | tüm araçlar |
| VH15 | tekne/vapur gövde kırmızı-kahve | #8E3A30 | yalnız tekne [AÇIK] |
| VH16 | açık üst yapı / tramvay gövde | #C9CBC6 | toplu taşıma, vapur |

Hesaplanan HSV (2026-10-25): özel gövde (VH1–VH9) s ≤ 0,45 (VH7 kısık kırmızı tam sınırda 0,45; ilk taslaktaki #8C3A35 s 0,62 ile sınırı aştığı için kısıldı — sayfada fazla kahve okunursa yeniden bakılır); kamu/taksi/tekne satırları (VH10–VH12, VH15) s 0,58–0,66 (≤ 0,66 istisna sınırı içinde); hiçbir satır s > 0,70 değil.

### b.3 Okunurluk ve yerleşim kuralları
- Silüet ayrımı: hatchback (dik arka), sedan (kademe), crossover (yüksek), minibüs (tek hacim), otobüs (uzun kutu), tramvay (bölümlü + pantograf), kamyon (kabin + kasa ayrı ton) — her biri 200 m'de (≈ 20–60 px) **profil ve renk bloğu** ile ayırt edilmeli [DOĞRULANACAK].
- Ölçek kontrolü: otomobil kapı eşiği ≈ insan dizi; otobüs ≈ 1 kat; tramvay ≈ 2 dükkân cephesi değil, ~5–6 parsel cephesi (32 m) [hesap].
- Araç sayısı ve türü sim verisinden (T-050); park etmiş araç ile hareketli araç ayrı kural (park şeridi yalnız kesitte varsa).

### b.4 Kullanıcıya sorulacak (araç)
1. **Marka/görünüm:** tamamen jenerik (öneri) mi, yoksa belirli dönem/ülke otomobil karakteri (ör. 1970–80'ler yerli sedan hissi) mi? `veh_car_old_a` dönem katmanı istenir mi?
2. **Taksi:** taksiler ayırt edilsin mi; edilecekse rengi (sarı VH10 İzmir/Türkiye çağrışımı yapar — istenir mi, yoksa Anderva'ya özgü başka renk mi)?
3. **Kamu/toplu taşıma renk kimliği (livery):** Ismeral belediyesinin taşıtları tek bir renk kimliği taşısın mı? Aday: beyaz gövde + petrol (VH11) veya bordo (VH12) bant, ya da başka. (Gerçek kurum renk düzenleri kopyalanmaz.)
4. **T0'da tramvay var mı?** Kanon tramvayı kent dokusunun parçası sayıyor (F04 "tramvay/feribot ilişkileri") ama T0 ağında (`network.json`) tramvay yok. Seçenekler: (a) T0'da yok, oyuncu inşa eder; (b) T0'da D1'de bir hat var; (c) sonra karar. Karar yoksa tramvay şablonu dalga 3'te kalır.
5. **Banliyö treni** ve **araba vapuru** T0'da var mı? (Ağda yük/ray hattı ve yolcu feribotu var.)
6. Vapur gövde rengi: koyu (lacivert/kısık siyah) mı, kırmızı-kahve mi?
7. Ambulans/itfaiye/polis gibi acil durum araçları görünsün mü (kurum yapısı AÇIK)?
8. Araç yoğunluğu: sokaklar "yaşanmış ama sakin" mi, "yoğun ve tıkanık" mı hissettirmeli? (Sim verisinden türer; görsel tavan bu cevaba göre ayarlanır.)

---

## c) Yol kesitleri (`rds_*`)

### c.1 İlke
- Bir yol kesiti, **yapı hattından yapı hattına** (parsel cephesinden karşı parsel cephesine) tam kesittir: bölümlerin sırası ve genişliği, yüzey satırları, işaretleme, ağaç/donatı sırası. Toplam genişlik ağ sınıfının `width_m`'i ile **eşleşir** (bugün: arterial 22, collector 15, local 10, field 6, rail 14 m — `data/world/ismeral/network.json`).
- **Yol çizim aracı (T-042) yalnız `approved` kesitleri sunar.** Oyuncu sınıf değil kesit seçer; sınıf ve genişlik kesitten türer. Sim maliyeti/kapasitesi sim'in verisidir (bu belge değil).
- Simetri ve okunurluk: taşıt yüzeyi koyu (U2/U12), yaya yüzeyi açık (U3/U1), ayrım bordür (U11) ve ton farkıyla; ilçe uzaklığında yol "koyu çizgi + açık kenar" olarak okunur (v1 §10.2 C2-3).
- Bugünkü yollar (T-048 tek renk şerit, `road_style.json`) katalogda `provisional-in-use`; bu kesitler onaylanınca onların yerini alır.

### c.2 Kesitler (soldan sağa; genişlikler m; toplam = sınıf genişliği)
Kısaltmalar: K kaldırım (U3, bordür U11 0,15 m) · Ş taşıt şeridi (U2) · P park şeridi (U2, MK1 sınır) · B bisiklet (U2 + kısık renkli şerit [AÇIK] veya ayrık döşeme) · R refüj · T tramvay yatağı · A ağaç çukuru (K içinde).

| Kimlik | Ad | Kesit | Toplam | Sınıf (ağ) | İşaretleme | Ağaç / donatı | Bölge | Referans notu | İhtiyaç | Dalga |
|---|---|---|---|---|---|---|---|---|---|---|
| `rds_ped_6_a` | yaya çarşı sokağı | döşeme 6,0 (ortada 0,6 taş oluk U4), bordür yok | 6,0 | **yeni sınıf `ped`** [AÇIK] | yok | tente (bina `_gf`), kiosk seyrek | D1, D6 tarihî çekirdek | 03 ZOOM 3 çarşı dokusu (ilişki) | tarihî ticaretin dar, araçsız dokusu; v1 §12.1 "organik çarşı" | 1 |
| `rds_hill_8_a` | yamaç sokağı (tek yön) | K 1,5 · Ş 3,0 · cep/park 2,0 · K 1,5 | 8,0 | `local` daraltılmış varyantı [AÇIK] | yok | direk tek taraf | D5, D1 yamaç | 03 genel: yamaç mahalleleri | eğimde dar sokak; kot farkını okunur kılar | 2 |
| `rds_local_10_a` | yerel sokak (çift yön) | K 2,0 · Ş 3,0 · Ş 3,0 · K 2,0 | 10,0 | `local` | yalnız kavşakta yaya geçidi | direk tek taraf, 30 m aralık | her bölge konut | — | kentin baskın sokağı | 1 |
| `rds_local_10_b` | yerel sokak (tek yön + park) | K 2,0 · P 2,2 · Ş 3,5 · K 2,3 | 10,0 | `local` | park sınırı MK1 | direk; ağaç yok | D1, D6 yoğun konut | — | park eden araçla yaşanmış sokak | 1 |
| `rds_coll_15_park_a` | cadde (parklı) | K 2,5 · P 2,0 · Ş 3,0 · Ş 3,0 · P 2,0 · K 2,5 | 15,0 | `collector` | orta kesik çizgi, park sınırları | direk iki taraf; durak cebi yok | konut/karma | — | mahalle caddesi | 1 |
| `rds_coll_15_tree_a` | ağaçlı ticaret caddesi | K 4,25 (A 1,2 dahil) · Ş 3,25 · Ş 3,25 · K 4,25 | 15,0 | `collector` | orta kesik çizgi | çınar sırası iki taraf (8–10 m aralık), bank, durak | D1, D2, D6 merkez | ZOOM 4 geniş kaldırım + ağaç (ilişki) | dükkân bandının (`_gf`) yaşandığı cadde | 1 |
| `rds_coll_15_bike_a` | bisiklet yollu cadde | K 2,5 · B 1,75 · Ş 3,25 · Ş 3,25 · B 1,75 · K 2,5 | 15,0 | `collector` | orta çizgi, bisiklet şeridi ayırıcı | direk | D6, D1 | — | bisiklet ulaşımı seçeneği | 2 |
| `rds_ind_15_a` | sanayi yolu | K 2,0 · yükleme/kamyon park 3,5 · Ş 3,75 · Ş 3,75 · K 2,0 | 15,0 | `collector` | orta çizgi; yükleme alanı sınırı | seyrek direk; ağaç yok | D3, D4 depo | 02 D3 kesiti (geniş, yatay) | kamyon ölçeği; sanayinin "avlulu" okunması | 1 |
| `rds_art_22_a` | ana arter (2+2, refüjlü) | K 3,5 · Ş 3,25 · Ş 3,25 · R 2,0 · Ş 3,25 · Ş 3,25 · K 3,5 | 22,0 | `arterial` | şerit kesik çizgileri, kenar çizgisi | refüjde alçak çalı/çim; çift kollu direk refüjde | bölgeler arası | 02 T0 "temel karayolu" (ilişki) | bölgeler arası bağlantı; mevcut ağın sınıfı | 1 |
| `rds_art_22_tram_a` | tramvaylı cadde (1+1, orta hat) | K 4,5 · Ş 3,25 · T 6,5 (çift hat) · Ş 3,25 · K 4,5 | 22,0 | `arterial` | şerit kenar çizgileri; tramvay yatağı bordürle ayrık | katener direği (orta), ağaç sırası kaldırımda | D1, D6 [AÇIK] | ZOOM 4 orta hat (ilişki) | tramvay kararı için mevcut sınıfa sığan kesit | 3 |
| `rds_blvd_30_a` | ağaçlı bulvar (2+2, geniş refüj) | K 5,25 · Ş 3,25 · Ş 3,25 · R 6,5 (ağaç sırası) · Ş 3,25 · Ş 3,25 · K 5,25 | 30,0 | **yeni sınıf `boulevard`** [AÇIK] | şerit çizgileri | refüjde çınar/palmiye sırası; kaldırımda bank | D1, D6 merkez (olgun) | ZOOM 4 (ilişki) | prestij aksları; refüj ileride tramvaya dönüşebilir (aynı iskelet) | 2 |
| `rds_blvd_30_tram_a` | tramvaylı bulvar | K 5,25 · Ş 3,25 · Ş 3,25 · T 6,5 · Ş 3,25 · Ş 3,25 · K 5,25 | 30,0 | `boulevard` [AÇIK] | şerit çizgileri, tramvay yatağı | katener direği, palmiye sırası kaldırımda | D1, D6 | ZOOM 4 doğrudan tür ilhamı | ulaşım politikasının en görünür sokak sonucu | 3 |
| `rds_coast_28_a` | kıyı yolu + promenad | K 3,5 (yapı tarafı) · Ş 3,25 · Ş 3,25 · B 2,5 (çift yön) · promenad 15,0 (döşeme 9 + çim/palmiye şeridi 6) · rıhtım kenarı 0,5 | 28,0 | **yeni sınıf `coast`** [AÇIK]; bugün kıyı bağlantısı `collector` 15 | şerit çizgileri, bisiklet ayırıcı | palmiye sırası 10–12 m aralık (`vegetation.json` promenad 12 m ile uyumlu), promenad direği, bank | D1, D6, D2 kıyı | F02 "Kordon hissi veren uzun, kamusal kıyı bandı"; ZOOM 3 | kanonun istediği yürünebilir kıyı (VIS-02) | 1 |
| `rds_field_6_a` | tarla yolu | banket 1,0 · stabilize 4,0 (U9/U6) · banket 1,0 | 6,0 | `field` | yok | seyrek kavak/zeytin sırası (tarla kenarı) | D4 | 02 D4 ova | tarım dokusunun okunması | 1 |
| `rds_rail_14_a` | ray koridoru (çift hat) | kenar 3,0 · balast yatağı 8,0 (aks arası 4,0; ray MK3) · servis yolu 3,0 | 14,0 | `rail` (oyuncu çizemez, T-042 kapsam dışı) | — | katener yok (dizel/yük varsayımı [AÇIK]) | D3–D4–D1 | F02 D3 demiryolu ilişkisi | mevcut ağdaki ray hattının görünümü | 2 |

Tüm toplamlar elle toplandı (ör. `rds_coast_28_a`: 3,5 + 3,25 + 3,25 + 2,5 + 15,0 + 0,5 = 28,0). Şerit 3,0–3,75, park 2,0–3,5, bisiklet 1,75/2,5, kaldırım ≥ 2,0 (yamaç 1,5) README §3 aralıklarındadır.

### c.3 İşaretleme şablonları (`mrk_*`)
| Kimlik | Tarif | Ölçü | Palet | Görünürlük |
|---|---|---|---|---|
| `mrk_lane_dash_a` | şerit ayırıcı kesik çizgi | 0,12 genişlik; 3 m çizgi / 6 m boşluk [ÇM] | MK1 #D8D6CE | < 300 m |
| `mrk_edge_solid_a` | kenar / orta sürekli çizgi | 0,15 | MK1 | < 300 m |
| `mrk_crosswalk_a` | yaya geçidi (zebra) | çubuk 0,5 / boşluk 0,5, boy 3–4 m | MK1 | < 400 m (kavşak okunurluğu) |
| `mrk_stop_line_a` | dur çizgisi | 0,4 | MK1 | < 300 m |
| `mrk_park_bay_a` | park şeridi sınırı | 0,10 | MK1 | < 200 m |
| `mrk_yellow_a` | sarı çizgi (yükleme, durak, yasak) | 0,12 | MK2 #C9A94E | < 300 m |
| `mrk_rail_a` | ray çifti (tramvay/tren) | 1,435 açıklık, 0,07 ray | MK3 #5C5F61 | < 600 m |

Kural: işaretleme yol yüzeyinin üstünde ince ayrı şerit (decal/doku yok); yazı, ok sembolü, logo yok (dalga 1). Parlayan beyaz yok (MK1 v 0,85).

### c.4 LOD sadeleşmesi (tek dünya: konum ve genişlik değişmez, yalnız ayrıntı silinir)
| Seviye | Ne kalır |
|---|---|
| Sokak (< 300 m) | tüm bölümler, bordür, işaretleme, ağaç/donatı |
| İlçe (300 m – ~3 km) | taşıt yüzeyi (tek ton) + yaya/promenad yüzeyi (tek ton) + refüj/tramvay yatağı tonu; işaretleme ve bordür yok; ağaç sırası LOD1/leke |
| Metro (> ~3 km) | tek şerit; ton sınıfa göre (arter/bulvar/kıyı biraz açık, yerel koyu); kıyı promenadı açık şerit olarak kalır; **genişlik gerçek** (öneri) |

Not: bugünkü `road_style.json` metroda genişliği × 0,55 daraltıyor. Tek dünya ilkesine göre bu sınırda bir sadeleştirmedir; art-director önerisi metroda gerçek genişlik + ton hiyerarşisi. Okunurluk sorunu çıkarsa (yollar metroda kaybolursa) tersine karar yakalamayla verilir [DOĞRULANACAK].

### c.5 Kapsam dışı (ayrı şablon ailesi gerekir; soru)
Kavşak/meydan bağlantısı, dönel kavşak, köprü kesiti, merdivenli yamaç sokağı, iskele/rıhtım kesiti, otopark.

### c.6 Kullanıcıya sorulacak (yol kesiti)
1. **Genişlikler:** önerilen genişlikler (yerel 10, cadde 15, arter 22, bulvar 30, kıyı 28, yaya 6, yamaç 8) kabul mü? İzmir'e göre daha dar/daha geniş mi olmalı?
2. **Yeni sınıflar:** ağda bugün yalnız arterial/collector/local/field/rail var. `ped` (yaya), `boulevard`, `coast` (kıyı promenadı), daraltılmış yamaç sokağı ayrı sınıf olarak eklensin mi?
3. **Oyuncu ne seçer:** yol çizerken oyuncu **kesit** mi seçer (ör. "ağaçlı ticaret caddesi") yoksa yalnız **sınıf** mı (kesit bölgeye göre otomatik)? Sonradan kesit değiştirme (ör. refüjü tramvaya çevirme) oynanış olsun mu?
4. **Bisiklet yolu** rengi: ayrı renkli şerit (kısık kırmızı/yeşil) mi, yalnız çizgiyle ayrılmış asfalt mı?
5. **Park şeritleri** kesitte olsun mu? (Park eden araçlar sokak hayatı verir; kapasiteyi azaltır.)
6. **Tramvaylı kesitler** (`rds_art_22_tram_a`, `rds_blvd_30_tram_a`) T0'da var mı yoksa yalnız oyuncu yatırımıyla mı gelir? (b.4 soru 4 ile aynı karar.)
7. Kıyı promenadının içeriği: palmiye mi, çınar mı, karışık mı? Promenad genişliği 15 m uygun mu?
8. İşaretleme düzeyi: şerit çizgileri + yaya geçidi yeterli mi; ok/yazı/sembol istenir mi?

---

## d) Bitki (`veg_*`)

Mevcut (`provisional-in-use`, T-051): `veg_plane`, `veg_palm`, `veg_pine`, `veg_olive` (`data/view/vegetation.json`). Bütçe: LOD0 ≤ 72, LOD1 ≤ 12; uzakta ağaç lekesi (v1 §7). **Palmiye ≤ 11,5 m** (saat kulesinin yarısı; v1 §7 kuralı).

| Kimlik | Tarif | Boyut (boy · taç Ø) | Üçgen | Palet | Referans notu | İhtiyaç | Dalga / durum |
|---|---|---|---|---|---|---|---|
| `veg_plane_a` | çınar: geniş yuvarlak taç, açık alacalı gövde | 14 · 10 | 72 / 32→≤12 [v1 LOD1 32 vardı; README §5 ≤ 12 ile hizalanmalı] | P2/P4 yaprak, P10 gövde (yeni) | 03 ZOOM 3 meydan ağaçları | meydan/avlu/cadde gölgesi | var; sayfada onay |
| `veg_palm_date_a` | kanarya hurması tipi: kalın gövde, geniş yıldız taç | 8–10 · 6–7 | 60 / 10 | P6 yaprak, P11 gövde | ZOOM 3/4 kıyı/meydan palmiyeleri | Kordon/meydan kimliği | `veg_palm` bunun yerine geçer mi? sor |
| `veg_palm_tall_a` | ince uzun gövde, küçük taç | 10–11,5 · 3,5 | 50 / 8 | P6, P11 | ZOOM 4 bulvar palmiyeleri | bulvar/promenad sırası (dikey ritim) | 2 |
| `veg_pine_brutia_a` | kızılçam: düzensiz konik-yuvarlak taç | 10–14 · 6 | 60 / 10 | P3/P7 | 02/03 yamaç ormanları | D5 yamaç, kent kenarı | mevcut `veg_pine` |
| `veg_pine_stone_a` | fıstık çamı: yalın gövde + düz şemsiye taç | 10–14 · 9–11 | 60 / 10 | P7, P1 | Ege kıyı/yamaç silüeti (tür) | Ege'ye özgü silüet; tepe/park | 2 |
| `veg_olive_a` | zeytin: alçak, geniş, gümüşi gri-yeşil, burgulu gövde | 5 · 5 | 50 / 8 | **P8 gümüşi** (yeni), P2 | 02 D4 ova | D4/D5 tarla kenarı, bahçe | var; P8'e geçiş önerisi |
| `veg_cypress_a` | servi: dar sütun | 10 · 2 | 20 / 6 | P7 | — | mezarlık/kamu/yamaç vurgusu (seyrek) | 2 |
| `veg_poplar_a` | kavak: dar uzun oval, tarla kenarı sırası | 16–20 · 4 | 30 / 6 | P2/P4 | — | D4 tarla sınırı ritmi (v1 §6) | 2 |
| `veg_shrub_a` | çalı/zakkum kümesi; varyant `b` çiçekli (P9 benek ≤ %15 çalılarda) | 1,5–2,5 · 2–3 | 24 / 6 | P2/P3, P9 | — | refüj, park kenarı, bahçe | 1 |
| `veg_hedge_a` | budanmış çit (uzun kutu) | 1,2 · 0,8 × uzunluk | 12 / 4 | P3 | — | bahçe/park sınırı | 2 |
| `veg_garden_a` | bahçe yaması: sebze sıraları veya çiçek tarhı (alçak düz plaka) | 4 × 6 × 0,4 | 20 / 2 | P2/P4/U9 | — | ev bahçesi, D4 köy | 2 |

Yeni palet satırları (alan "bitki"): P8 zeytin gümüşi #7E8A6A, P9 çiçek pembesi (benek) #B57A86, P10 çınar gövdesi açık #9C9580, P11 palmiye gövdesi #7D6A55; v1 Tur 2'den P6 #6B7D3E, P7 #3F5634.

### d.1 Kullanıcıya sorulacak (bitki)
1. Palmiye türü: kalın gövdeli geniş taçlı (hurma tipi), ince uzun (bulvar tipi) veya ikisi?
2. Fıstık çamı (şemsiye silüet) eklensin mi?
3. Çiçekli çalı (zakkum pembesi) gibi küçük renk vurguları istenir mi, yoksa bitki tamamen yeşil-gri mi kalsın?
4. Mevsim değişimi (çınar sonbaharı, çıplak dallar) olacak mı? (Mevsim kararı AÇIK; karar yoksa yaz görünümü sabit.)

---

## e) Kent zemini (`gnd_*`)

Kent zemini yol/arazi gölgelendiricisinin verisidir (`terrain_look.json` `urban`, `road_style.json`); kit mesh'i değildir. Bugünkü `terrain_look.json` urban tonları (konut #A39479 civarı, sanayi #918F85 civarı) bu tabloyla eşlenmelidir. Uzakta (metro) her zemin, bloğun baskın tonuna kaynar (v1 §8).

| Kimlik | Tarif | Ton | Hex | Nerede | Referans notu | İhtiyaç | Dalga |
|---|---|---|---|---|---|---|---|
| `gnd_asphalt_a` | yol asfaltı (sıcak nötr) | U2 | #5F5D5A | tüm taşıt yüzeyi | — | yolun koyu çizgi okunması | 1 |
| `gnd_asphalt_b` | koyu asfalt (arter/yeni) | U12 | #4A4845 | arter, bulvar | — | yol hiyerarşisi tonla | 1 |
| `gnd_sidewalk_a` | kaldırım döşemesi | U3 | #A69C8B | tüm kaldırımlar | ZOOM 4 açık kaldırım | yaya alanının ayrışması | 1 |
| `gnd_curb_a` | bordür taşı | U11 | #BDB6A8 | kaldırım kenarı (0,15 m) | — | yakında kesit netliği | 1 |
| `gnd_plaza_a` | meydan döşemesi (açık taş) | U1 | #B9AE9C | meydan, saat kulesi çevresi, promenad | ZOOM 3 meydan | meydanın "boşluk" olarak okunması (v0 §4) | 1 |
| `gnd_courtyard_a` | avlu: toprak-döşeme karışık | U4 | #8A7D68 | yapılı blok içi, han avlusu | v1 §0.3 "çim üstüne serpilmiş kent" kusuru | yapı arası zeminin kent olması | 1 |
| `gnd_park_lawn_a` | park çimi (kuru Ege yeşili) | U5 | #7D8551 | park, promenad çim şeridi, refüj | — | yeşil alanın arazi çiminden ayrı okunması | 1 |
| `gnd_park_path_a` | park yolu / stabilize | U6 | #A39478 | park içi, köy yolu | — | park iç düzeni | 2 |
| `gnd_ind_concrete_a` | sanayi betonu (açık) | U7 | #A8A7A1 | sanayi avlusu | 02 D3 | sanayi avlusunun kentsel zeminden ayrışması | 1 |
| `gnd_port_apron_a` | liman sahası (koyu beton + sarı çizgi MK2) | U8 | #7F7E79 | rıhtım, konteyner sahası | 02 D3 | limanın okunması (VIS-04) | 2 |
| `gnd_vacant_a` | boş arsa / şantiye toprağı | U9 | #8F7558 | boş parsel, inşaat | — | **boş parsel ve inşaatın görünür olması** (oyun bilgisi) | 1 |
| `gnd_sand_a` | kum/kıyı | U10 (= arazi TS) | #B8A77F | plaj, kıyı şeridi | arazi paleti TS | kıyı sürekliliği | var (arazi) |

Hesaplanan HSV: asfalt s ≤ 0,07, v 0,29–0,37; döşemeler v 0,54–0,74, s ≤ 0,26; park çimi s 0,39 — README §2.2 içinde.

### e.1 Kullanıcıya sorulacak (zemin)
1. Meydan ve kaldırımlar **açık taş** (U1/U3) mu, daha sıcak/kırmızımsı döşeme mi?
2. Boş parsel/şantiye zemini toprak rengiyle belirgin olsun mu (oyun bilgisi olarak okunur), yoksa kentle karışsın mı?
3. Asfalt sıcak nötr gri (öneri) mi, bugünkü soğuk gri mi?

---

## f) Sokak donatısı (`fur_*`)

Donatı yoğunluğu yol kesitinden ve bölgeden türer (c.2 "ağaç/donatı" sütunu); "her yüzeye süs" yok. Yalnız LOD0 (< 250–400 m); uzakta çizilmez. Metal donatı koyu (FN1/FN2), yazı/logo yok, lamba ışık yaymaz.

| Kimlik | Tarif | Boyut | Üçgen | Palet | Referans notu | İhtiyaç | Dalga |
|---|---|---|---|---|---|---|---|
| `fur_lamp_street_a` | sokak direği, tek kol | 8,0 boy, kol 1,5 | 24 | FN1/FN2 | ZOOM 4 direkler (tür) | sokak ritmi, ölçek (insan ↔ direk ↔ kat) | 1 |
| `fur_lamp_double_a` | refüj çift kollu direk | 10,0 | 32 | FN2 | — | arter/bulvar | 2 |
| `fur_lamp_promenade_a` | promenad/meydan direği, tek başlık | 4,5 | 20 | FN1 | ZOOM 3/4 | kıyı ve meydan ölçeği | 1 |
| `fur_pole_catenary_a` | tramvay katener direği | 7,5 | 24 | FN2 | ZOOM 4 | yalnız tramvaylı kesitle | 3 |
| `fur_bench_a` | bank: ahşap oturak + metal ayak | 1,8 × 0,6 × 0,8 | 28 | FN3 + FN2 | ZOOM 3 meydan | durağan kamusal hayat | 1 |
| `fur_bus_stop_a` | otobüs durağı: arka cam panel (koyu) + düz çatı plakası + bank | 5,0 × 1,6 × 2,6 | 80 | FN6 çerçeve, VH13 cam, FN3 | — | **toplu ulaşım kararının sokakta görünmesi** | 1 |
| `fur_kiosk_a` | büfe/kiosk: küçük kutu, öne açılan kepenk, tente | 2,4 × 2,0 × 2,7 | 90 | FN4 veya A2; kepenk A8/R6 | İzmir sokak büfesi (tür) | meydan/iskele ticareti | 1 |
| `fur_simit_cart_a` | seyyar simit arabası: cam kutu + iki teker | 1,2 × 0,7 × 1,5 | 40 | FN5/FN1, VH13 cam | yerel sokak hayatı (tür) | "yaşayan şehir" ayrıntısı; satıcı ile | 2 |
| `fur_awning_cafe_a` | kafe tentesi/şemsiye + 2 masa | 3,0 × 2,5 × 2,6 | 60 | A1/A3/A6 (kit aksan), FN2 | ZOOM 3 kıyı kafeleri (ilişki) | kıyı/meydan hayatı | 2 |
| `fur_bin_a` | çöp kutusu | 0,5 × 0,5 × 0,9 | 16 | FN1 | — | belediye hizmeti ayrıntısı | 2 |
| `fur_bollard_a` | bariyer babası | 0,2 × 0,9 | 8 | FN2 | — | yaya alanı sınırı | 2 |
| `fur_planter_a` | beton saksı + çalı | 1,2 × 1,2 × 0,7 | 30 | FN5 + P2 | — | yaya sokağı/meydan | 2 |
| `fur_fountain_a` | taş çeşme (duvar çeşmesi veya serbest küçük) | 1,5 × 0,8 × 2,2 | 60 | W11/W8 (kit) | v0 §4 kule kaidesinde çeşme platformu | meydan/mahalle kimliği | 2 |
| `fur_traffic_light_a` | trafik lambası (ışık yaymaz) | 4,0 | 30 | FN2 | — | kavşak okunurluğu | 2 |
| `fur_fence_site_a` | şantiye panosu (3 m segment) | 3,0 × 0,1 × 2,0 | 8 | A3/FN5/W12 | — | **inşaatın görünür olması** (sim inşaat; Q-016 iskele/şantiye sorusu) | 1 |
| `fur_pier_bollard_a` | rıhtım babası | 0,5 × 0,6 | 12 | FN2 | — | iskele/rıhtım ölçeği | 2 |

Yeni palet satırları (alan "donatı"): FN1 koyu yeşil-gri metal #3D4A4A, FN2 kısık siyah metal #2E3236, FN3 ahşap #8B6A4A, FN4 büfe yeşili #5E6E52, FN5 beton #C9C3B5, FN6 durak çerçevesi petrol #4C6C78. (Hesaplanan s ≤ 0,47, v 0,21–0,79.)

### f.1 Kullanıcıya sorulacak (donatı)
1. Sokak metal donatısının rengi: koyu yeşil-gri (FN1), siyah (FN2) mi, belediye renk kimliğiyle (b.4 soru 3) mi?
2. Kiosk/büfe ve simit arabası gibi yerel ticaret öğeleri istenir mi (İzmir çağrışımı güçlü ama jenerik çizilir)?
3. Şantiye görünümü: inşaat sırasında parselde şantiye panosu + toprak zemin + mikser yeterli mi, yoksa iskele/vinç modülü de istenir mi (Q-016)?
4. Reklam panosu, tabela, bayrak gibi yazı/simge taşıyan öğeler olacak mı? (Öneri: dalga 1'de hiç yok.)
5. Gece aydınlatması (lamba ışığı) ileride olacak mı? (Bugün yok; olacaksa direklerde ışık noktası payı bırakılır.)

---

## g) Önerilen ilk kontak sayfası paketi (onay sırası README §10)
| Sayfa | İçerik |
|---|---|
| 0 — standart | mevcut `prop_human`, `veh_car`, `veg_plane`, `lmk_clocktower` + tüm palet alanlarının şeritleri (SK/HR/CL/VH/U/MK/FN/P), standart ışıkta |
| 1 — yol kesitleri | dalga 1 kesitleri: her biri kesit diyagramı (ölçülü) + 20 m'lik 3/4 parça (araç ve insan ölçeğiyle) + 400 m ve 2 km görünümü |
| 2 — kent zemini | dalga 1 zeminler yan yana, bir sokak kesiti ve bir bina ile |
| 3 — araç | dalga 1 araçlar yan yana + renk varyantları; 60 m ve 200 m panelleri |
| 4 — insan | a.1 seçenek A/B/C aynı boyda; seçimden sonra a.2 tipleri + renk setleri |
| 5 — donatı | dalga 1 donatı, ölçek insanı ve 3 katlı cephe önünde |
| 6 — bitki | mevcut 4 tür + dalga 1/2 önerileri, saat kulesi (23 m) ve 4 katlı cephe önünde |
