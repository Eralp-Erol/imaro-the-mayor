# Sözleşme 1.6 (P5) + GOLDEN_X (P3) · T-065 Aşama 1 ön koşulları (2026-11-01, simulation-engineer)

Taban: `943f92c` (ADR-0009 + T-065 P1-P4, `agent/handover-imaro-m01-349562fb` `4997bbf` üstüne). İki ayrı commit.

## Commit 1 · P5 · sözleşme 1.5 -> 1.6 (ADR-0005 Ek H)

- `SimContract.VERSION_MINOR = 6`, `VERSION = "1.6"`, sürüm notu (`src/contracts/sim_contract.gd`). Yolu yık / klasik geri al
  yüzeyi (`public_work.demolish`, `public_work.demolished`, `undo_available()`, `demolish_cost()`) kaynak yorumlarında
  "v1.6" oldu (`sim_command.gd`, `sim_event.gd`, `sim_facade.gd`, mock, `sim_facade_impl.gd`). `agenda.respond` ve
  `agenda_items()` 1.5 kalır (yorumlara dokunulmadı). Davranış/durum/hash değişmedi.
- Kilitli sürüm testleri `"1.5"` -> `"1.6"`: `m2_contract_extension_test`, `agenda_respond_contract_test`,
  `agenda_item_contract_test`, `expropriation_contract_test`, `plan_query_contract_test` (listeye "1.6").
- Yeni: `tests/contracts/demolish_contract_test.gd` (sürüm, komut kataloğu/şekil, olay türü, varsayılan sorgular).
  Kırmızı önce: sürüm sabiti değişmeden 7 başarısızlık (yalnız sürüm); sonra yeşil.
- ADR-0005 Ek H başlığı "KOD UYGULANDI" olarak güncellendi. Yeniden iskân 1.7 (yapılmadı).

## Commit 2 · P3 · GOLDEN_X

`tests/sim/public_works/golden_expropriation_undo_test.gd`, sabit
`GOLDEN_X = 9b935788d5c04ce69d1dd22ddcde55e0d350c454c33e06f14fcd6f4678772289` (tick 60 `state_hash()`).

Senaryo (ADR-0009 planı, sahte kamulaştırma dünyası + gerçek siyaset/bütçe verisi):
1. Kamulaştırmalı yol A (köşegen, parsel 1-3) -> `undo_last` (ilk tarama öncesi).
2. Aynı noktalara A' -> 21+1 gün (3 haftalık tarama; pencere kapanır, PE-01 öğesi açılır).
3. Düz yol B (`spur_a`) -> `public_work.demolish` B -> tick 30'a, sonra 60'a.

- **Varsayım doğrulandı:** adım 2'deki ikinci kamulaştırmalı yol KABUL EDİLİR (komutlar `is_rejected() == false`; olay
  dizisi `expropriated, built, restored, removed, expropriated, built, built, demolished` testle kilitli).
- Düzeltme: `attach_budget` yalnız tick 0'da takılır; bu yüzden `ReactionWorldBase._world` yardımcısına isteğe bağlı
  `with_budget` parametresi eklendi (varsayılan kapalı, mevcut testler değişmez).
- "Boş senaryo değil" testi: bütçe defterinde `road_cost/road_refund/road_demolish`, A' için tepki defteri satırı, >= 3
  haftalık tarama, `reaction_local.opened == 1`.
- Hash 6 ayrı Godot sürecinde aynı çıktı (sabitlemeden önce 3 art arda, sonra 3 koşu daha). İkinci koşu ve tick 30
  kaydet/yükle aynı hash (testte).
- GOLDEN_A/B (`tests/sim/m2_query_test.gd`) bit-bit aynı: 19 test, 0 başarısızlık (bayraklar kapalı; src değişmedi).

## Doğrulama (komut çıktıları)

- `tests/contracts`: 145 test, 0 hata/başarısızlık.
- `tests/sim` (tamamı bir kez): 969 test, 0 hata, 0 başarısızlık.
- `gdlint` (gdtoolkit 4.5.0): `src/contracts tests/contracts src/sim/facade/sim_facade_impl.gd tests/sim/public_works
  tests/sim/politics/reaction_world_base.gd` temiz; `verify quick` içinde 67 dosya temiz.
- `tools/verify.sh quick`: PASS (canon-check, studio-check, area-map, gdlint, import, unit-gdunit 228 suite / 2190 test,
  0 hata, 0 başarısızlık, 22 orphan uyarısı). **KISMİ:** atlanan 42 suite (tests/app, art, view, world) ve canon-guard.

## Test edilmemiş / not

- `full` koşmadı. tests/world, tests/app, tests/art, tests/view quick'te atlandı.
- Farklı tohum -> farklı GOLDEN_X sınanmadı (`ReactionWorldBase` tohumu sabit).
- 22 orphan uyarısı quick'te raporlandı; bu işten mi önceden mi geldiği ayrıştırılmadı.
