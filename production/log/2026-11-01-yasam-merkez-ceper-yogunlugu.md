# Araç/yaya merkez-çeper yoğunluğu (D-014 §4, Q-026) — 2026-11-01

REQ: WLD-01/TEK-03 (tek dünya; sayı sim verisinden), SIM-12 (sahte sayı yok), TEK-01/02 (görünüm sim'e yazmaz) · Kullanıcı sözü: "2 kat kalabalik merkez bolgeleri olsun, ceperlere gidildikce seyreklessin."
Sim, `playable.gd`, kanon DEĞİŞMEDİ. Değişen: `src/view/life/life_edge_activity.gd`, `life_config.gd`, `life_host.gd` (yalnız `--life-flat` dev argümanı), `data/view/life.json`, `tools/godot/life_probe.gd`, testler.

## Seçilen veri ve neden
"Merkez" = kenarın çevresindeki **sim yapılaşma yoğunluğu**: kenarın hücresi + 8 komşu (3x3 x 256 m = 768 m kutu) içindeki faaliyet kütlesi (biten konut x w_res + ticaret x w_com + inşaat x w_con, cephe parsellerinin sim birimlerinden) / km2. Smoothstep(`density_lo` 1500, `density_hi` 7000) -> merkezilik 0..1 -> çarpan = lerp(çeper 0,8, merkez 2,0).
Neden tek ağırlık merkezi + uzaklık DEĞİL: gerçek Ismeral T0 çok merkezli (1 km kareli faaliyet haritasında en az 6 ayrı yoğun öbek; faaliyet ağırlıklı merkez (22,3 km; 20,9 km) boş araziye düşüyor). Yerel yoğunluk her öbeği ayrı merkez sayar, oyuncu yeni mahalle kurarsa orası da merkezleşir, koordinat uydurulmaz. Doluluk (occupancy) yoğunluğa katılmaz (yapılaşma yoğunluğu). Faaliyet 0 ise 0 x çarpan = 0 (sahte trafik yok). Eşikler T0 Ismeral dağılımından kalibre ÇALIŞMA DEĞERİ: lo altı = hücrelerin ~%35'i / faaliyetin ~%12'si; hi üstü = faaliyet ağırlıklı ~%75. yüzdelik.
Sınıf yoğunluk tavanı (`*_cap_per_100m`) çarpan > 1 iken aynı oranda yükselir (aksi halde 2x merkezdeki ~%30 kenarda tavana çarpıp kesilirdi: ölçülen). Profil tavanları (araç 1600 / insan 1400) DEĞİŞMEDİ.
Maliyet: kenar başına 3x3 komşuluk toplamı önbellekli (hücre başına bir kez); parsel değişince yalnız çevre 3x3 önbelleği silinir, merkezilik >0,02 değişen komşu hücreler kirlenir. Yerleşim deterministik (3 koşuda `LIFEPROBE_CENTRALITY` md5 aynı).

## Ölçüm (b): 100 m sokak başına medyan (T0 Ismeral, yoğunluk 1,0, `life_probe`, `--life-flat` = önce)
Bölgeler: merkez = merkezilik >= 0,9 (1531 kenar, 151 km), orta, çeper = <= 0,1 (3255 kenar, 387 km).
| | önce (düz) araç / yaya | sonra araç / yaya | oran |
|---|---|---|---|
| merkez (medyan) | 5,08 / 7,10 | 10,14 / 14,17 | x2,00 / x2,00 |
| orta | 3,59 / 4,95 | 4,73 / 6,54 | x1,32 |
| çeper | 0,70 / 0,96 | 0,56 / 0,77 | x0,80 |
Tüm kenar medyanı (önceki kalibrasyonla aynı): ana/toplayıcı/yerel araç 1,20 / 2,51 / 2,46 -> 0,96 / 2,45 / 2,45; yaya 0,96 / 3,51 / 3,45 -> 0,77 / 3,42 / 3,43. Dünya toplamı: 17,9 bin araç / 24,7 bin yaya -> 27,4 bin / 38,0 bin (merkez ağırlıklı).

## Profil tavanı etkisi (RAPOR)
Sokak pozunda (en yoğun kenar) insan tavanı (1400) ÖNCE de doluydu (1398); araç 1018 -> 1025. Tavan bağlı olduğu için örnek sayısı artmadı; bunun yerine bütçe daha dar yarıçapta doldu: kurulu hücre 18 -> 8, atlanan hücre (toplam) 41 -> 51. Yani merkezde ~450 m ötesindeki hücrelerin araçları kurulmuyor (araç menzili 900 m, uzakta küçük noktalar). Mahalle pozu (320 m, 2 hücre) tavan altında: araç 149 -> 297, insan 210 -> 416. Tavan aşılmadı. Bilinen kısıt/öneri: hücre atlanırken HEM araç HEM insan atılıyor ve insan sayısı menzil dışı (230 m ötesi, görünmeyen) hücreleri de bütçeye yazıyor; "yalnız görünür menzildeki insanı bütçeye say" ayrı iş olarak ele alınabilir (görsel kayıp olmadan yarıçapı genişletir). Yapılmadı (kapsam).

## Ölçüm (a): kare maliyeti — GÜVENİLMEZ, DÜRÜST NOT
Intel i7 Mac, iGPU; iPad DEĞİL. Makine ölçüm boyunca yük altındaydı (yük ort. 4-800, `CPU_Speed_Limit` 41-100, bir noktada disk dolu); pencere de bazı koşularda çizilmedi (draw call 231 sabit, render_cpu 0, 6,9 ms sabit = geçersiz). Geçerli (render_cpu > 0) koşular, medyan ms (cal_ms ile oran = ms / cal_ms):
- sokak (merkez): düz 11,26 (27,7) ; merkez 11,51 (32,5) / 12,28 (34,5) / 19,77 (34,6, aşırı yük). Sayılar tavanda olduğu için fark beklenmez; gürültü içinde.
- mahalle (320 m, sayılar 2x): düz 10,13 (19,95) ; merkez 10,69 / 10,43 / 10,10 (cal 0,99 / 0,46 / 1,19: yük dalgalı).
- çeper sokak: düz 8,47 ; merkez 8,23 / 8,29 (çeper seyrekleşti, 120 -> 285 araç değil: poz farkı, bkz. not).
n>=3 temiz düz/merkez çifti ALINAMADI. Sonuç: önemli bir kare maliyeti artışı GÖRÜLMEDİ ama kanıtlanmış da DEĞİL.
Not (çeper pozu): düz koşuda "rim" pozu bazı koşularda farklı hücre sayısı (9 / 16) gösterdi (kurulum zamanlaması); sayılar yalnız yönlü.

## Testler
`tests/view/life/life_centrality_test.gd` (12 yeni, somut değerli): varsayılan 2,0 / <=1,0; yoğun çevre -> çarpan 2,0 kesin, seyrek -> 0,8; aynı sim faaliyetinde merkez/düz = 2,000, çeper/düz = 0,800, merkez/çeper = 2,500; faaliyet 0 -> 0 (merkezde de); batıdan doğuya sönen yapılaşmada merkezilik tek yönlü azalır (>0,9 -> <0,05; çarpan >1,8 -> <=1,0); tavan çarpanla ölçeklenir ve aşırı yükte tavanda durur; kayıt boşalınca çeper çarpanı; yeniden kurulum = artımlı güncelleme; yerleşim deterministik; profil tavanı (max_cars/max_people = ceiling) görünümde aşılmaz + atlanan hücre > 0; varsayılan tavanlar 1600/1400; geçersiz config reddedilir. Mevcut `test_counts_never_exceed_the_class_cap` yeni sözleşmeye (tavan x merkez çarpanı) güncellendi. `tests/view/life` 48 test: 0 hata.

## Doğrulanmadı / AÇIK
Bu dalda `verify quick` disk dolduğu için geçmedi (gdlint elle temiz, bkz. birleşik koşu); `tests/view/life` ayrıca GdUnit ile koşuldu (48/48). Temiz kare maliyeti A/B (n>=3). Görsel kabul (kullanıcı/art-director): merkez 2 katı + çeper 0,8 değerlerinin hoş görünmesi; çarpan/eşik değerleri çalışma değeri (Q-026'ya kullanıcı sözüyle bağlandı, oran ayarı data/view/life.json). iPad/dokunmatik.
