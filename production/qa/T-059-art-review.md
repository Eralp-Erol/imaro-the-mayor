# T-059 · Sanat kapısı (art-director) · 2026-10-27

**Hüküm: PASS-with-conditions.** Bu bir kullanıcı onayı değildir. Q-018 stil seçimi kullanıcıda kalır; bu inceleme hiçbir stili seçmez.
Kapsam: 6 öneri (`hum_hero_{pawn,block,facet}_{neutral,broad}_a`, LOD0/LOD1). Bağımsız inceleme: kod, asset ve Godot'a dokunulmadı; yalnız PNG'ler açıldı. Kırpımlar `magick` ile `/private/tmp/claude-501/t059ad/` altına çıkarıldı.
REQ: VIS-01, VIS-02, VIS-03, VIS-05, WLD-01 · görev kabul ölçütü 2 ("A/B/C eşit kıyaslanır"), 4 ve 5.

## Gördüklerim (doğrudan gözlem)
1. **Silüet/anatomi.**
   - B ve C'de baş, boyun, gövde, iki kol, el, iki bacak ve ayak 12 m'de ve 1:1 yakın karede açıkça okunuyor. Ön ortografik karede (`context-compare-lod0.png`) parmak ucu ≈ 0,65 m'de duruyor; bu, 1,75 m boy için doğru oran.
   - A'da kol, el, bacak ve ayak yok: omuz rafı + sütun + baş. Sokak karesinde A, hemen yanındaki T-058 bollard'ıyla aynı dilde okunuyor (koyu taban bandı, prizma gövde) ve "oyun taşı / direk" izlenimi veriyor.
   - Yüz, logo, yazı, sembol, kültürel/dini giyim ve üniforma yok. Kural sağlanmış.
   - Boş yüz ve tek tip kıyafet, yakında manken izlenimi veriyor.
2. **C etek kusuru (gerçek geometri hatası).**
   - C nötr: ceket eteğinin iki yanında pantolon kalça kütlesi eteği delip dışarı çıkıyor. Ham ön karede ≈ 0,06 m'lik mavi basamaklar görünüyor (kırpım `cn_hem.png`). Kusur sokak bağlam karesinde ve 12 m karesinde de görülüyor.
   - C geniş: aynı yerlerde iki küçük mavi iğne deliği var (`cb_hem.png`).
   - Kaynak (çıkarım, kodu okuyarak): `art/blender/human/assets.py` `facet()` içinde bacak dış kenarı `lgx+lg` = 0,160 m (nötr), kalça halkası `hp` = 0,16 m. Kenarlar flush. Genişte bu değerler 0,198 / 0,20 m; boşluk yalnız 2 mm.
3. **Kıyas adilliği.**
   - Ön ortografik kıyas (`style-compare.png` üst sol ve sağ) ile model başına sayfalar aynı kamera, ışık, duruş ve paletle çekilmiş. Bunlar adil.
   - **Adil olmayan 1 — 3/4 kıyas.** `context-compare-3q.png`, yani `style-compare.png` alt paneli: sıra kameraya çapraz duruyor. C geniş kameraya en yakın, A en uzak; C ≈ 1,45 kat büyük görünüyor (baş-ayak 340 px'e 235 px).
   - **Adil olmayan 2 — kostüm farkı.** C'de A ve B'de olmayan beyaz yaka, manşet, ceket eteği ve taban var. Kıyas stil yerine kostüm detayını da ölçüyor.
   - **Başarısız kanıt.** `context-compare-side.png` kameranın baktığı eksende dizili; altı figür birbirini örtüyor ve tek figür görünüyor.
   - Sokak bağlamında (`context-street.png`) etiket yok. B geniş diğerlerinden 1 m geride duruyor.
4. **Ölçek ve kalite çıtası.**
   - `context-scale.png` tahmini: figür ≈ 88 px, kapı ≈ 120 px; figür kapının ≈ 3/4'ü. Bank ve bollard oranı makul. VIS-03 açısından sorun görmedim (ölçüm değil, piksel tahmini).
   - Figürler düz renk + ince grenaj. Hero cephe, bank ahşabı ve saksı taşı dokulu (`hero-res_mid.png`, `furniture-hero/context-street.png`, `vegetation-hero/context-street.png` ile karşılaştırıldı).
   - Fark gerçek, ama oyunun insan ölçeğinde (60 m'de ≈ 40 px, 120 m'de ≈ 17 px) doku okunmaz. Mat, düz gölgeli insan VIS-01'e uygun. Bu fark **kabul edilebilir**.
   - Asıl "ucuz" görünüm 12 m'deki tek tip gri-mavi kıyafet ile boş yüzden geliyor. Bu bir renk ve tip çeşitliliği konusu; Q-018 sonrası kalabalık setine ait.
5. **LOD sürekliliği.**
   - B: LOD0→LOD1 silüeti korunuyor.
   - C: LOD1 B ile birebir aynı. Yaka, manşet, taban ve faset baş kayboluyor; 30 m üstünde kabul edilebilir.
   - A: LOD1 gövdesi omuz rafından bele doğru daralan dolu bir trapez; LOD0'da raf + ince sütun var. Kütle büyüyor ve geçişte görünür pop riski var.
   - B ve C LOD1'de eller ten rengini kaybediyor; kol uca kadar gri.
   - 60 m (`far_all.png`): A ayırt ediliyor (bacak arası yok), B ve C ayırt edilemiyor. Uygulayıcının "üç stil ayırt edilemiyor" ifadesi kısmen yanlış.
6. **Küçük gözlemler.**
   - B yan karede omuz önünde küçük yumuşak koyu leke var. Nedeni doğrulanmadı (gölge/AO olabilir).
   - Üst karelerde figür kadraj merkezinde değil; baş, paralaks nedeniyle kayık görünüyor.

## Koşullar (engelleyici — kullanıcıya sunmadan önce)
- **K1 · C etek delinmesi.**
  - Düzeltme: `facet()` içinde z 0,80 ve 0,90'daki gövde halkalarında `hp` → `hp+0.02` (alternatif: z 0,86 bacak halkası `lg*0.85`).
  - İki C modelini yeniden üret. Ön/3q/yakın kareleri yeniden çek; hash ve determinism'i tekrarla.
  - Gerekçe: görünür geometri hatası, C'yi kıyasta haksız biçimde cezalandırıyor (kabul 2 ve 5: "çıtayı tutmayan örnek düzeltilir").
- **K2 · 3/4 kıyas yanlılığı.**
  - Düzeltme: altı figürü kameraya eşit uzaklıkta yerleştir (yay üzerinde veya sırayı görüş yönüne dik çevirerek). Ya da `style-compare.png` alt panelini model başına 3q karelerinin yan yana montajıyla değiştir.
- **K3 · Başarısız yan kare.** `context-compare-side.png`'yi z'de kaydırılmış dizilimle yeniden çek ya da sayfalardan çıkar.
- **K4 · Dürüst rapor.** `design/library/human-hero.md` içinde şunları düzelt:
  - C'nin ek kostüm detayı taşıdığını ve stilden ayrı değerlendirilmesi gerektiğini yaz.
  - 60 m cümlesini düzelt: A ayırt edilir, B=C.
  - C etek kusurunun durumunu yaz.

## Devredilebilir (engelleyici değil — entegrasyon veya Q-018 sonrası)
- A LOD1: omuz rafı genişliğini koru, raf altına bir halka ekleyip sütuna daralt (66 → ≈ 82 üçgen, bütçe 100).
- B/C LOD1 ten rengi el: yalnız bütçe nötrse yap (ör. kolu 3 kenara indirip uç yüzü SK2'ye ata); 100 üçgen sınırı aşılmaz.
- Manken izlenimi ve tek tip kıyafet: Q-018 kararından sonra palet/tip varyasyonu gelmeli. Yüz detayı eklenmesin.
- A'nın bollard/direkle karışma riski: kullanıcıya stil kararı notu olarak iletilsin; teknik düzeltme değil.
- Sokak bağlamına Label3D ekle; dört figürü aynı derinliğe koy.
- B omuz lekesi: entegrasyonda gölge/AO ayarıyla kontrol et.

## Açılan dosyalar
- Kontak sayfaları:
  - `design/library/sheets/human-hero/style-compare.png`
  - `design/library/sheets/human-hero/hum_hero_{pawn_neutral,pawn_broad,block_neutral,block_broad,facet_neutral,facet_broad}_a.png`
  - `design/library/sheets/human-hero/context-{compare-lod0,compare-lod1,compare-3q,compare-side,street,scale}.png`
  - `design/library/sheets/human-hero/index.json`
- Ham kareler (`artifacts/screenshots/captures/`):
  - `20261027-203443-t059-facet_neutral-front_lod0.png`, `20261027-203524-t059-facet_broad-front_lod0.png`
  - `20261027-203448-t059-facet_neutral-side_lod0.png`, `20261027-203325-t059-block_neutral-side_lod0.png`, `20261027-203203-t059-pawn_neutral-side_lod0.png`
  - `20261027-203626-t059-context-street.png`, `20261027-203631-t059-context-scale.png`
  - Altı modelin `*-far_lod1.png` ve `*-near_lod0.png` kareleri (index.json yolları)
- Çıta:
  - `design/library/sheets/hero-res_mid.png`
  - `design/library/sheets/furniture-hero/context-street.png`
  - `design/library/sheets/vegetation-hero/context-street.png`
- Kırpımlar: `/private/tmp/claude-501/t059ad/{c_fronts,cn_hem,cb_hem,sides,street_fig,scale_fig,far_all,near_all}.png`
- Kod (yalnız okundu): `design/library/human-hero.md`, `production/tasks/T-059.md`, `assets/hero/human/human_lab.gd` (60–123), `art/blender/human/assets.py` (14–30, 94–110)

## Yeniden inceleme (K1–K4 sonrası, commit 6aa0585) — hüküm: PASS (koşullar yalnız devredilebilir)
Kullanıcı onayı değildir; A/B/C seçilmiş sayılmaz (Q-018 açık).
- **K1 kapandı (gördüm):** `hem_facet_{neutral,broad}_{front,side,back}.png` altı kırpımda etek kenarı kesintisiz, pantolon mavisi etekten taşmıyor. `hum_hero_facet_{neutral,broad}_a.png` ön/yan/arka/3q/12 m karelerinde ve `context-compare-3q.png` 4x kırpımında (`/private/tmp/claude-501/t059ad2/c3q_hem.png`) çentik yok. Hareket/animasyon test edilmedi.
- **K2/K3 kapandı (gördüm):** `context-compare-3q.png` ve `context-compare-side.png`'de altı figürün boyu eşit, baş hizası aynı, örtüşme yok; `style-compare.png` 3/4 paneli yeni kareyi kullanıyor. Kod: `human_lab.gd` sırayı kamera eksenine dik kuruyor.
- **K4 kapandı (okudum):** `human-hero.md` kostüm adilliği uyarısı, 60 m cümlesi (A ayrı, B=C), etek durumu (hp+0,02 ve hd+0,02, kapsam sınırı) doğru.
- **Yan etki yok:** git'e göre e279f6f'den beri yalnız iki C LOD0 GLB değişti; A/B GLB'leri değişmedi. C'de yeni kusur görmedim. Ön ortografik görünümde C kalçası hafif kloş; stil notu, kusur değil.
- **Devredilebilir (yeni, küçük):** `human-hero.md` "figürler düz renkli (dokusuz)" cümlesi tam doğru değil; kırpımlarda hafif gren dokusu görünüyor. Entegrasyonda düzeltilsin. Önceki "Devredilebilir" listesi aynen geçerli.
