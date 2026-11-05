# 2026-11-05 · art-director · D-021 boş arazi ("kuru ot ve toprak") + çatı paleti ("kiremit ve düz çatı karışık")

Karar: **PASS WITH FIXES**. Kod değiştirilmedi. Taban `d9588e9` (dal `work/art-review`). Yalnız aşağıdaki gerçek
pencereli kareler açılıp bakıldı (Godot 4.7.2, Compatibility, AMD Radeon Pro 560X).

## Kareler nasıl alındı (tekrarlanabilir)
- Prob: `artifacts/qa/bos-arazi-cati/ad_probe.gd` (commit'lenmez; T-066 pencereli probunun yalın türevi). Gerçek
  `scenes/game/playable.tscn --demo`, gerçek girdi: yol çiz (D2, aday seed 7, 15 parsel alınır) -> "Kamulaştırarak geç"
  -> "Yıkımı onayla" -> "Son yolu yık" -> "Evet, yık" -> +30 gün. Önce (`r-*`, yol yok) / sonra (`v-*`, boş belediye
  arazisi) AYNI odak, uzaklık 120 / 230 / 500 / 1400 / 4500 m, heading 0; ayrıca 200 m heading 135.
- Masaüstü `--resolution 1600x900`; dokunmatik `--resolution 1024x768 --imaro-input-profile=touch`.
- world_preview: `tools/capture.sh wp-district-D2 --frames 400 --resolution 1600x900 --scene res://scenes/dev/world_preview.tscn -- --preset=district:D2` ve `--preset=core`.
- Eşdeğer önceki kare (aynı aday, aynı 230 m kamera): handover `artifacts/qa/t066-window/desk-06-after-demolish.png` (düz hardal).

## Bakılan kareler (klasör `artifacts/qa/bos-arazi-cati/`, PNG'ler <= 2,4 MB, commit'lenmez)
- Masaüstü (açılıp bakılan): `desk-00-home`, `desk-r-120`, `desk-r-230`, `desk-r-200-h135`, `desk-v-120`, `desk-v-230`,
  `desk-v-500`, `desk-v-1400`, `desk-v-4500`, `desk-v-200-h135`. Alınıp bakılmayan (karara girmedi): `desk-r-500/1400/4500`, `desk-a-230-yol`.
- Dokunmatik (açılıp bakılan): `touch-r-230`, `touch-r-500`, `touch-v-120`, `touch-v-230`, `touch-v-500`. Alınıp bakılmayan:
  `touch-00-home`, `touch-r-120/1400/4500`, `touch-r-200-h135`, `touch-a-230-yol`, `touch-v-1400/4500`, `touch-v-200-h135`.
  İlk dokunmatik koşuda yolun bitiş dokunuşu sağ panelin altına düştü ("Yol çok kısa"); ikinci koşu `--road-shift=90` ile odak doğuya kaydırıldı (aynı aday, aynı arsa).
- world_preview: `artifacts/screenshots/captures/20261105-160629-wp-district-D2.png`, `...160704-wp-core.png`
- Küçük kopyalar (JPEG, < 400 KB): `artifacts/qa/bos-arazi-cati/best-desk-v-230.jpg`, `best-desk-v-120.jpg`,
  `best-desk-r-200-h135.jpg`. Not: `artifacts/qa/` depoda `.git/info/exclude` ile dışlı; kareler ve prob commit'lenmez,
  yalnız bu worktree'de durur (`.claude/worktrees/agent-a1bc6ea59b8fd40b8/artifacts/qa/bos-arazi-cati/`).

## Gördüklerim

### Boş arazi (D-021 "kuru ot ve toprak") — KABUL, düzeltmeyle
- **Düzeldi:** `desk-v-230` vs eski `desk-06-after-demolish`: düz, doygun hardal tek renk leke gitti; yerinde saman /
  çıplak toprak / soluk ot yamaları var. 500 m (`desk-v-500`) ve 1400 m (`desk-v-1400`) karelerinde "kurumuş, terk
  edilmiş arsa" olarak okunuyor ve kent kenarındaki diğer boş parsellerle aynı dil; 1400 m'de neredeyse kaynaşıyor.
  Kırsal tarlalara sızma görmedim (`desk-v-1400` üst sağ tarla poligonları eski renkte; `wp-district-D2`, `wp-core`
  değişmemiş görünüyor).
- **F1 (yakın zoom, en önemli):** `desk-v-120`, `touch-v-120` (büyütülmüş kesitte açık): arsa yüzeyi kare piksel mozaiği; ~1-2 m'lik
  keskin kare taneler düzenli "labirent" deseniyle tekrar ediyor. Hemen yanındaki kent zemini (`desk-v-120` sağ alt) pürüzsüz.
  Sokak ölçeğinde "düşük çözünürlüklü doku / dijital kamuflaj" okunuyor (VIS-01 matte low-poly, VIS-03 yakın ölçek).
- **F2 (renk):** 230 m'de (`desk-v-230`, `touch-v-230`, `desk-v-200-h135`) arsa hâlâ karedeki en doygun sarı-zeytin yüzey; çevredeki
  bej kent zemininden bir ton daha sarı ve kahve lekeler yüksek kontrastlı (kamuflaj). D-021 kart metni "şehrin
  renkleriyle uyumlu, hafif" diyordu: yön doğru, şiddet fazla.
- **F3 (kenar):** arsa sınırı yer yer parsel/yol çizgisi yerine yuvarlak "damla" kontur (`desk-v-230` sağ alt, `desk-v-200-h135`
  üst); kent zemini arsanın içine yumuşak lob olarak giriyor. Okunurluk için kritik değil, ama "boyanmış maske" hissi veriyor.

### Çatı paleti (D-021 "kiremit ve düz çatı karışık") — GEÇTİ
- `desk-r-200-h135`, `desk-r-230`, `desk-v-500`, `touch-r-500`: kiremit hâlâ çoğunluk; yanında koyu kahve kiremit,
  mavi-gri çinko, gri beton eğimli, beyaz düz teras; açık (beyaz/krem/pembe) cepheler belirgin arttı. Yan yana aynı
  blok tekrarı kırılmış. "Tüm çatılar kırmızı kiremit" (VIS-05) riski artık yok; Ege karışık dokusu (VIS-02) daha iyi okunuyor.
- **F4:** `desk-r-120`: gri "beton" eğimli çatılar kiremit sıra çizgisini koruyor, yalnız rengi soluk; "rengi atmış
  kiremit / eksik doku" gibi okunuyor ve açık cepheli binada çatı-duvar değer ayrımı kayboluyor (silüet zayıflıyor).
- **F5 (küçük):** `desk-v-1400`: birkaç çatı/cephe somon-şeftali tonuna kayıyor, uzakta "pastel" noktalar; parlaklık oynaması fazla olabilir.

### Kapsam dışı ama karelerde hâlâ görünen (önceki rapordan)
- Kent zeminindeki koyu bulut lekeleri sürüyor (`desk-v-500`, `desk-r-230`; bina gölgesinden ayrı lekeler). Önceki madde 2.
- Ağaç LOD geçişinde nokta/dither deseni (`desk-v-500` alt kenar ağaçları). Önceki "dither" bulgusu.
- Uzak ölçekte (`desk-v-4500`, `wp-district-D2`) D2 kasabası büyük dama tahtası tarla içinde küçük; VIS-04 "tarım boş
  renk lekesi" riski (bu turun konusu değil).
- Dokunmatik: demo "Döngü sonucu" paneli sağda tam yükseklik (~%38 genişlik), altta "Gün N" şeridi, üst çubuğun
  üstünde ince şehir şeridi (`touch-r-230`). Çekmece değişikliği (B-100..102) imar paneli içindi; bu panel değil.

## Düzeltme listesi (technical-artist; hepsi `art/shaders/terrain_land.gdshader` ve `data/view/building_variety.json`)
1. **F1:** boş arazi ince tanesini yumuşat: 9 m gürültü okumasını filtreli/mip'li örnekle ya da genliğini 0,35 -> ~0,12
   indir; katman dokusu parlaklık tanesi (`lum` çarpanı 0,88-1,12) yakında bu kare deseni taşıyorsa bandı 0,95-1,05'e
   daralt. Kabul: `v-120` büyütülmüş kesitte kare desen görünmez, tane kent zemini kadar pürüzsüz.
2. **F2:** `vacant_straw` / `vacant_sage` doygunluğunu ~%25 düşür, değeri bej kent zemine yaklaştır (ör. straw
   ~(0.58,0.54,0.42)); `soil_w` en büyük ağırlığı 0,8 -> ~0,5 (lekeler daha az zıt). Kabul: `v-230`'da arsa karedeki en
   doygun yüzey olmasın; yine de bej zeminden ayırt edilsin.
3. **F3:** boş parsel sınırında yuvarlak lob yerine parsel/yol kenarına yaslanan geçiş (maske keskin mip'iyle sınır) ya da
   ince toprak kenar bandı. Düşük öncelik.
4. **F4:** beton eğimli çatıda kiremit sıra çizgilerini bastır (düz levha) ya da tonu cepheden en az ~%20 değer farkıyla
   ayır (biraz koyu, hafif sıcak gri). Kabul: `r-120`'de gri çatı açık cepheden net ayrılıyor.
5. **F5:** `brightness_jitter` 0,05 -> ~0,03 ve açık cephe karışımında pembe/şeftali payını kontrol et (yalnız uzak noktalar).
6. Düzeltmeden sonra aynı prob ile `v-120`, `v-230`, `r-120` yeniden çekilsin; `tools/visual-diff.sh` ile önce/sonra.

## SAHİBE SOR
Yok. D-021 kararları uygulanmış ve yönü doğru; düzeltmeler sanat ayarı (çalışma değeri), yeni karar gerektirmiyor.
