# 2026-11-04 · İki ilçe / başka tohumla başlatma (M2-CLOSURE "Kapanış için yapılacaklar" madde 1)

REQ: WLD-01, WLD-12, CAN-03, CAN-08, TEK-01/02. Karar gerektirmez; sahip kararı uydurulmadı. Push/merge yok. `src/sim` değişmedi.

## Soru: "oyun iki ilçeyle başlatılabiliyor mu?" (dürüst cevap)
- Dünya TEK ve altı ilçeyi (D1-D6) birden üretir; sim hepsini birlikte yürütür (40 493 parsel). "Başlangıç ilçesi" bugün
  yalnız KAMERA açılışıdır: `scenes/dev/world_preview.gd:138` `--start-district=KOD` / `world.json start_district_id`
  (veride YOK, boşsa `core`) -> `CameraRig.home_district` -> `CameraPresets.start_view`. Sim'e, kayda, yetkiye geçmez.
- Kamera: 6 ilçenin hepsi için açılış odağı o ilçenin içinde (ölçüldü, test).
- Oyun kuralı: **yol yetki alanı `network.json jurisdiction_regions = ["D2"]` sabit veri**. D2 dışında her yol taslağı
  `outside_jurisdiction` ile reddedilir (D1, D3-D6: 80'de 0 geçerli; D2: 80'de 64). Yani D1'de başlayan oyuncu bugün
  yol çizemez, döngü başlamaz. Bu gerçek bir boşluk: **B-026** (AÇIK; T-043 hiç uygulanmadı).
- Yetki alanı başlangıç ilçesine ayarlanınca (aynı alan, veri parametresi) döngü 6 ilçenin hepsinde uçtan uca çalışıyor.

## Kanıt (hepsi başsız, gerçek Ismeral verisi; sahne yok)
`tests/game/m2_start_district_test.gd` (6 test, GdUnit, ≈4,5 dk): kurulum oyunun `_build_buildings`/`_start_sim` ile aynı
(dünya + ağ + T0 + PlayableEconomy/Politics + gerçek kamulaştırma köprüsü), `tests/sim/perf/qa_world_support.gd` üzerinden.
1. Kamera açılışı 6 ilçe, bilinmeyen kod -> `core`.
2. Çekirdek döngü, tohum 1467, **6 ilçe**: kamulaştırmalı yol (komut kabul, `road.built`, `road.expropriated`, alınan
   parseller `taken`) -> imar (`zoning.applied` = plan parsel sayısı) -> en az bir plan parselinde yatırımcı kararı,
   inşaat başladı ve bitti; olumlu gerekçe karar anında kayıtlı; sim'in geliştirdiği HER parsel plan parselidir (CAN-03,
   D-010); ağ her koşudan sonra taban grafına döner; 6 ilçenin 6 farklı durum hash'i.
3. Başka dünya tohumu (20261104; farklı ağ hash'i) **2 ilçe**: aynı döngü geçti.
4. Yol var, plan yok (2 ilçe, 200 gün): sıfır onay, sim'in geliştirdiği parsel yok (CAN-03).
5. Determinizm (2 ilçe): aynı ilçe+tohum -> aynı hash (iki koşu); farklı ilçe -> farklı hash; farklı sim tohumu -> farklı hash.
6. B-026 karakterizasyonu: gönderilen veriyle yetki dışı ilçede yol reddi `outside_jurisdiction` (boşluk kapanınca güncellenir).
Gdlint temiz. `tools/verify-areas.tsv`: bu suite `slow` listesine alındı (quick'i 4 dk şişirmesin; `verify full` koşturur);
`tools/verify-scope.sh check` geçti.

## Yan bulgu
- **B-027** (gözlem, AÇIK): `reason_log_capacity` 1000 + periyodik tarama (~9 olumsuz kayıt/gün) -> yapılan parselin
  yatırımcı gerekçesi ~100+ günde günlükten düşüyor (260. günde 6 ilçenin hepsinde `reasons_for` boş). Denetçide ne
  göründüğü ÖLÇÜLMEDİ; test bu yüzden gerekçeyi karar anında okur.

## Doğrulanmadı / varsayılan
- Pencereli oyunda `--start-district=D1` açılışı, HUD yol-ret metni, kamera kareleri GÖRÜLMEDİ (sahne yolu `world_preview`
  burada koşmadı). Kayıt/yükleme "ilçe parametresini korur" (T-043 ölçüt 4) uygulanamaz: parametre sim'de yok.
- T-043 ölçütleri 1 (veri-odaklı parametre), 3, 5 açık kalır; bu iş yalnız ölçüt 2'nin sim yarısını (+ B-026) kanıtlar.
- Yetki alanı testlerde elle başlangıç ilçesine ayarlandı: bu, planlanan bağın (B-026 çözümü) benzetimidir, bugünkü oyun davranışı değil.
- Hash/olay sayıları bu makinede (yükte) alındı; süre ölçümü kabul kararı değil.
