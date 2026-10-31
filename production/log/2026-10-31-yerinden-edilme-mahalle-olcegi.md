# Yerinden edilme tepkisi · MAHALLE ölçeği (sim) — 2026-10-31

REQ: CAN-03, SIM-05, SIM-12, TEK-01/02 · Karar: D-008 ("halk tepki versin"), D-011 · Kaynak sorun: `2026-10-31-meclis-tepki-gercek-olcum.md` §5, §7 (gerçek D2'de yıkımlı yolda halk tepkisi SIFIR).
Dal: `worktree-agent-abf79b4298303d2a1` (WIP 7cb8275 + taban 60453b3 birleşimi, çatışmasız).

## Kök neden ve çözüm
Bölge ölçekli iki kapı D2'de (8686 hane) hiç açılmıyordu: kesim payı kapısı (%7-7,9 < `min_share_pm` %10) ve gündem eşiği (yerinden edilen / BÖLGE hanesi >= 20 pm = 174 hane; en büyük yol 72 hane = 8 pm). Ek bulgu (bu işte): `PlayablePolitics.config()` `reactions.json`ı HİÇ okumuyordu; oynanabilir oyun bu bölümü kod varsayılanıyla çalıştırıyordu.
Çözüm: yolun (komutun) KENDİ yerinden ettiği hane, `reactions.json` `local.neighborhood_households` (mahalle büyüklüğü) ile oranlanır; `>= min_displacement_pm` ise komut başına BİR PE-01 öğesi (`ReactionAgenda._scan_local`), nedeni `ReactionCause.record_local` (komut + alınan parseller + gerçek hane sayısı). Yerinden edilen 0 ise sessiz (yakınlık tek başına açmaz, yalnız baskıyı artırır). Aynı yol için yeniden açılmaz (`politics.reaction_local.opened`); durum yalnız ilk öğe açılınca yaratılır (kamulaştırmasız hash değişmez).

## Bayrak / değişmezler
- Bayrak `reactions.local.enabled`. KOD varsayılanı KAPALI (`ReactionConfig.defaults`); yalnız `data/politics/reactions.json` açar (opsiyonel dosya, digest dışı). Dosyasız koşular etkilenmez.
- `data/politics/blocs.json`, kanon klasörü, `src/contracts`, SimFacade sözleşme sürümü DEĞİŞMEDİ.
- `PlayablePolitics.config()` artık `reactions.json`ı okur (yalnız oynanabilir yapılandırma; sim bu sınıfı bilmez).
- Tüm sayılar VARSAYILAN ÇALIŞMA DEĞERİ (F05-C), kanon DEĞİL: `neighborhood_households` 200, `min_displacement_pm` 20 (= 4 hane), `full_displacement_pm` 200, `proximity_share_pm` 250.

## Önce / sonra: gerçek Ismeral D2 (tohum 1467, 400 gün, `tests/sim/perf/expropriation_reaction_real_probe.gd`; `--no-local` = önce)
| Yol | Yerinden edilen hane | Önce: PE-01 / PE-04 | Sonra: PE-01 (gün, baskı) / PE-04 | `group.reacted` |
|---|---|---|---|---|
| q10 | 0 (3 bina) | 0 / 0 | 0 / 0 (sessiz) | 0 / 0 |
| q50 | 6 | 0 / 0 | 1 (gün 5, baskı 170) / 1 | 0 / 0 |
| q90 | 38 | 0 / 0 | 1 (gün 5, baskı 975) / 1 | 0 / 0 |
| maks | 72 | 0 / 0 | 1 (gün 5, baskı 1000 = tavan) / 1 | 0 / 0 |

Her koşuda yol başına tek PE-01, 400 günde yağmur yok. Neden zinciri (q50): `decision.event.fire` <- `decision.bloc.expropriation_cause` (yerinden edilen etkeni 29, yakınlık 21, hane sayısı 6).
Not: "önce" sütunu `--no-local` ile, `reactions.json` artık yüklü iken alındı (eski rapordaki sayılarla uyumlu: 0 gündem).

## Doğrulama (çalıştırıldı)
- `tests/sim/politics/expropriation_local_scale_test.gd`: 20/20 (19 WIP + 1 yeni: kod varsayılanı kapalı). İlk koşuda 2 başarısızlık: oynanabilir yapılandırma `reactions.json`ı okumuyordu (düzeltildi) ve yanlış digest karşılaştırması (kaldırıldı; digest dışılığı `test_the_local_section_lives_outside_the_config_digest` ile).
- `tests/sim/politics` (dizin): 218 test, 0 hata/başarısızlık.
- GOLDEN_A/B (`tests/sim/m2_query_test.gd`) + `state_hash_test`, `sim_purity_test`, `sim_facade_determinism_test`, `save_slot_test`, `sim_save_test`, `app/sim_isolation_test`, `tests/contracts`, `tests/game/playable_politics*_test`, `tests/ui/agenda_real_sim_test`, `tests/sim/public_works`: 356 test, 0 hata/başarısızlık.
- `gdlint` (gdtoolkit 4.5.0): `src/sim/politics`, `src/game/playable_politics.gd`, `tests/sim/politics`, probe: temiz. Yasak API taraması (reaction_*.gd): boş.

## Doğrulanmadı / varsayıldı
- `tools/verify.sh quick/full` ÇALIŞTIRILMADI (görev gereği). Diğer alanlar (view/ui/world/game, `tests/ui` kalanı) koşulmadı.
- Mahalle büyüklüğü 200 bir tahmindir (gerçek mahalle verisi yok); eşik/ölçek sahip/systems-designer kararına açık.
- Kamulaştırmalı yolun oyunda çizilebilmesi (`playable_roads.gd` köprüsü) bu işin dışı; sim probu köprüyü kendisi kurar.
- UI'da PE-01 öğesinin görünümü/his testi yok. Tek dünya tohumu (1467), tek bölge (D2).
