# `verify quick` hızlı mod (2026-10-30)

Neden: `verify quick` 20-23 dk sürüyordu (GdUnit'te 2031 testin hepsi). Profil: `production/log/2026-10-30-test-sure-profili.md`.

## Tasarım
- `quick` = canon-check + studio-check + **area-map** (eşleme tutarlılığı) + gdlint + import + GdUnit4'ün **koruma çekirdeği + değişen alanın** suite'leri.
- `full` = eskisi gibi tüm testler (+ canon-guard + runtime smoke). Yalnız GdUnit zaman aşımı 1500 -> 2400 sn (yük altında tam koşu 1415 sn; kalite eşiği değil, takılma koruması) ve `canon-guard` iki kez değil bir kez koşuyor.
- Eşleme verisi: `tools/verify-areas.tsv` (`core` / `map` / `slow` / `ignore`). Çözücü: `tools/verify-scope.sh` (`check`, `resolve`, `base`).
- Değişen dosyalar = `git diff` (son BAŞARILI doğrulamanın HEAD'ine göre; `artifacts/verify/quick-base`; yoksa `main` ayrışma noktası) + izlenmeyen dosyalar. Fail eden koşu tabanı ilerletmez. Aynı dosya commit'lenmemiş kaldıkça her quick'te yeniden çalışır (tutucu yön).
- En uzun önek kazanır. Eşlemesiz bir yol (tabloda ne `map` ne `ignore`) -> **tüm suite'ler** koşar ve uyarı basılır. `src/` ve `tests/` altındaki her .gd dizini bir kurala bağlı olmak zorunda (`area-map` adımı kırılır).
- Koruma çekirdeği (28 suite, ~288 test, yük altında ~40 sn): `tests/contracts` (hepsi), `state_hash` (GOLDEN), `sim_purity`, `actor_purity`, `politics_purity`, `save_slot_purity`, `sim_isolation`, determinizm (sim facade / ekonomi / siyaset), `economy_sim07_can03` + `can03_guard` (CAN-03), `honest_zoning`/`honest_ui`, kayıt gidiş-dönüş, RNG akışları, tik sürücüsü, koşucu duman testi.
- `slow`: bitki suite'leri (placement 227 sn, cache 111, invariants 72, cell_builder 32; yük altında) bitki kodu değişse bile quick'ten çıkar; `VERIFY_QUICK_SLOW=1` ya da `full` koşturur. Değişen test dosyasının kendisi her zaman koşar.
- `canon-guard` (C-07 hook savunma testi, 35-70 sn): quick'te YALNIZ `.claude/hooks`, `.claude/settings*`, `tools/canon-check.sh`, `tools/test-canon-guard.sh` ya da kanon dizini değişince ya da `VERIFY_QUICK_CANON_GUARD=1` ile koşar. **Kullanıcı isteğinden (her zaman çekirdekte) bilinçli sapma:** süre bütçesi; kanon bütünlüğü (`canon-check`) her koşuda var. Her koşuda isterseniz tek satır (verify.sh).
- Çıktı: başta `kapsam: değişen alan + koruma çekirdeği · alanlar: ... · taban ... · N/M suite`, sonda `ATLANDI: ... ; tam doğrulama: tools/verify.sh full`, `SONUÇ: pass · kapsam: değişen alan (TAM DOĞRULAMA DEĞİL)`. JSON: `scope: "changed-areas"`, `full_verification: false`, `areas`, `suites_run/total/skipped`, `tests_skipped_estimate`, `skipped`. `result` ve `fingerprint` alanları aynı (stop-verify-gate hook'u hiç değişmedi; quick PASS'ı yine "son başarılı doğrulama" sayar, ama kapsamı JSON'da ve çıktıda yazılı).
- gdlint: quick yalnız değişen .gd dosyalarını tarar (tüm ağaç ~50 sn; `gdlintrc` değişirse tümü); full tümünü tarar.

## Bilinen risk
- Hızlı PASS, değişmeyen alanlardaki dolaylı kırılmaları yakalamaz (ör. `src/sim/core` değişimi `tests/view` içindeki bir regresyonu). Tablodaki "doğrudan tüketici" eşlemesi class_name başvuru taramasından (2026-10-30) çıkarıldı; uzak/dolaylı tüketici yok sayılır. Teslim/milestone: `full`.
- Stop hook'u quick PASS'ı kabul ettiği için "kapsam dışı" bir alanın kırılması commit'e girebilir; `full` teslimde şart.
- `slow` suite'ler bitki değişiminde atlanır: bitki ajanları bunları `VERIFY_QUICK_SLOW=1` ya da doğrudan `-a` ile koşmalı.
- Tablo bakımı gerekir (yeni dizin -> kural); `area-map` adımı bunu zorlar.

## Ölçülen quick süreleri (2026-10-30, makine PAYLAŞIMLI: yük ort. 5-19; 12 çekirdek; sakin makinede daha kısa beklenir, ölçülmedi)
Değişen dosya listesi `VERIFY_QUICK_CHANGED_FILE` ile yapay verildi (önizleme koşusu `quick-preview-latest.json` yazar; hook'un okuduğu `quick-latest.json`a ve `quick-base`e dokunmaz).
| Senaryo | Suite | Test | Duvar süresi |
|---|---|---|---|
| Değişiklik yok (yalnız çekirdek) | 28/191 | 288 | 51 sn (yük 5-9); ilk ölçüm 123 sn (lint tüm ağaç, yük 10-13) |
| Yalnız `src/ui` | 58/190 | 618 | 131 sn (yük 12-15) |
| Yalnız `src/sim/economy` | 54/190 | 581 | 113 sn (yük 9-13) |
| Yalnız `src/view/roads` | 32/190 | 333 | 60 sn (yük 7-9) |
| Yalnız `src/sim/core` (en geniş sim) | 72/190 | 772 | 220 sn (yük 9) |
| Yalnız `src/view/vegetation` (yavaş 4 suite atlanır) | 36/191 | 341 | 110 sn (yük 5); atlamadan önce 605 sn |
| GERÇEK çalışma ağacı (başka ajanların `src/ui`+`src/game`+`src/view`+bitki değişikliği + benim), taban=HEAD | 110/191 | 1103 | 473 sn (yük 15-19; bir koşuda 900 sn zaman aşımı, yük 20-31) |
Hedef <= 5 dk makine sakinken: yapay tek-alan senaryolarının hepsi (en kötüsü sim/core 220 sn) hedefte; gerçek çok-alanlı ağaç yük altında hedefi aştı.
