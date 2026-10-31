# 2026-10-31 · Meclis ret/kabul NEDENLERİ (SIM-12) · sim kaydı

Kaynak sorun: `production/log/2026-10-31-meclis-tepki-gercek-olcum.md` §3 ("Neden metni YOK"). Statü: sim + sözleşme + metin anahtarları TAMAM; UI tüketicisi (panel satırı) ui-engineer işi (aşağıda).

## Bulgu (kök neden)
- Sim aslında her üyenin 7 etkenini + gürültüyü zaten `ReasonLog`a yazıyordu (`council.vote`: stance_distance, trust_in_player, resentment, bloc_pressure, lobby_pressure, budget_realism, obligation). Eksik olan: (a) oylama düzeyinde "hangi etken oyları ne kadar kaydırdı" özeti, (b) 6 etkenin Türkçe etiketi (`reason.factor.trust_in_player` dışında yoktu; `reason_panel` ham anahtar gösteriyordu).
- Plan büyüklüğü oy hesabında bir etken DEĞİL (yalnız meclise gitme kapısında); bu yüzden nedene eklenmedi (yeni etken uydurulmadı). Altyapı baskısı `budget_realism` etkeninin girdisidir ve gerçek yük değeri nedene yazılır.

## Değişiklikler
| Yol | Ne |
|---|---|
| `src/sim/politics/council_why.gd` (yeni) | Oylama çözülürken üyelerin KAYITLI gerekçelerinden etken başına `net` (Σ katkı), `for`/`against` üye sayısı; |net| azalan sıralı; sıfır etkili etken yazılmaz; imar oylamasında `infra_load_pm` + `infra_region`. Yeni sayı/eşik YOK. |
| `src/sim/politics/council_engine.gd` | `_resolve`: `unplanned_land_enabled == 1` iken `vote["why"]` yazılır. `realism_of` aynı davranışla `peak_infra()` kullanır (altyapı yükü + bölge ikinci hesap değil, aynı girdi). |
| `src/sim/politics/politics_query.gd` | `vote_view` -> `CouncilVoteView.why_factors/infra_*`. |
| `src/contracts/council_why_factor.gd` (yeni), `council_vote_view.gd` | İSTEĞE BAĞLI alanlar (`why_factors`, `infra_load_pm` = -1, `infra_region`); eksik veride varsayılan. **Sözleşme sürümü (1.5) DEĞİŞMEDİ.** |
| `data/ui/strings.tr.json` | 6 etken etiketi (`reason.factor.stance_distance/resentment/bloc_pressure/lobby_pressure/budget_realism/obligation`) + `council.why.title/against/for/members/infra/none`. Kod içinde sabit metin yok. |
| `tests/sim/politics/council_why_test.gd` (yeni) | 10 test. |
| `tests/sim/perf/council_real_probe.gd` | Anlık görüntü çıktısına `why` eklendi (yalnız ölçüm). |

Değişmezler: `data/politics/blocs.json` ve `council.json` DEĞİŞMEDİ; `playable.gd`, `world_network.gd`, `economy_system.gd` DOKUNULMADI. Bayrak kapalıyken oylama kaydına yeni anahtar yazılmaz (test: `test_flag_off_writes_no_why_and_the_view_is_empty`), GOLDEN_A/B bit-bit aynı (council yolunu zaten kullanmıyorlar).

## Gerçek D2 örneği (Ismeral, tohum 1467, yol rank 0 + 12 parsel; probe `--days=40`)
`net` birimi = üye skorlarının toplamı (5 üye); eksi = hayıra çeker.

| Etken | Doğal oylama (3-2 KABUL) net / lehine / aleyhine | ZORLANMIŞ düşman duruş (0-5 RET) |
|---|---|---|
| Üyenin duruşuyla uyum (stance_distance) | +591 / 5 / 0 | -892 / 0 / 5 |
| Uygulanabilirlik (budget_realism) | -494 / 0 / 5 | -494 / 0 / 5 |
| Kesim beklentisi (bloc_pressure) | +64 / 3 / 2 | +64 / 3 / 2 |
| Rastlantı (noise) | -24 / 2 / 3 | -24 / 2 / 3 |
| Kırgınlık | -11 / 0 / 1 | -11 / 0 / 1 |
| Başkana güven | +3 / 1 / 1 | +3 / 1 / 1 |
| Altyapı | D2 bölgesi, yük binde 998 | aynı |

Okuma: `budget_realism` her oylamada beş üyenin beşini hayıra çekiyor (tablo 5-0 aleyhe, -99/üye); önceki ölçümün (§2.1) bulgusuyla uyumlu. Zorlanmış satır gerçek veri davranışı DEĞİL, yalnız ret yolunda nedenin görünüşünü gösterir.

## UI için kalan iş (ui-engineer; bu görevde YAPILMADI)
- `src/ui/flows/council_panel.gd` `_add_result` altında `v.why_factors` gösterilmeli (başlık `council.why.title`; eksi `net` -> `council.why.against`, artı -> `council.why.for`; etiket `UiText.t(name_key)`; altyapı `council.why.infra` {region, load}; `why_factors` boşsa `council.why.none`). Etiketler `reason_panel` üye gerekçelerini zaten düzeltir (artık ham anahtar yok).
- Reddedilen parsel -> oylama eşlemesi: `PlanStateView.source_ref` (`command.N`) = `CouncilVoteView.subject_ref`.
- `council.why.members` `{against_n}`/`{for_n}` yer tutucularını kullanır.
- Not: bir etkenin `against_members` > 0 iken `net` > 0 olabilir (karışık); UI `net` işaretine göre sınıflamalı, üye sayılarını ek bilgi olarak göstermeli.

## Doğrulama / varsayılan / test edilmemiş
Bkz. görev raporu (komut çıktıları orada). Sıfırdan yeni "varsayılan çalışma değeri" sayı eklenmedi.
