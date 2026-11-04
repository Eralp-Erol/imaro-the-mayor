# T-043B · öncelikli değerlendirme kuyruğu GERÇEK Ismeral dünyasında (2026-10-31)

Oyun kodu DEĞİŞMEDİ. Yeni dosya: `tests/sim/perf/t043b_real_world_probe.gd` (kalıcı sürücü; gdlint temiz). Commit yok.
Makine: Intel Core i7-8850H 2.6 GHz (12 iş parçacığı), 32 GB, macOS, Godot 4.7.2 başsız. Süreler duvar saatidir, makineye bağlıdır, kabul kararı değildir.

## Kurulum (playable.gd `_start_sim` ile aynı yol)
`WorldGenerator` (tohum 1467 = `world.json default_seed`) -> `NetworkGenerator` -> `T0Settlement.generate_detailed` -> `PlayableStock` ->
`PlayableEconomy.config_for` (`playable_economy.json`: `priority_review_enabled` 1, `unplanned_land_enabled` 1, `max_reviews_per_tick` 8) ->
`PoliticsBootstrap.create(..., PlayablePolitics.config())` -> `attach_public_works` (gerçek `RoadDraftRules`) -> `PlayableBudget.attach` ->
`SimBuildingProjector` + `SimBuildingPump` (görünümsüz). 40 493 parsel, 24 304 T0 stok parseli, 16 189 boş parsel.
Senaryo: 30 gün ısınma -> yol (`SimCommand.public_work_road`, D2, 108 m, 150 m içinde 38 boş parsel) -> `zoning.propose` (`zone.mixed`, yola en yakın 12 boş parsel)
-> plan yürürlüğe girene (3 gün) ve parsellerin hepsi bitene kadar günlük tick. "Gün" = plan yürürlüğe giriş tick'inden sayım (yol-önce: tick 34; plan-önce: tick 33).
Aday yollar `RoadDraftCheck` ile geçerli çıkanlardan, boş parsel sayısına göre sıralandı (yalnız D2'de >= 6 boş parsel yakınlıklı 4 aday çıktı).

## Doğrulanmış (koşturuldu, ölçüldü)

### Gün sayıları (plan yürürlüğünden sonra; 12 parselin planı)
| Senaryo | Kuyruk | İlk inşaat başlangıcı | İlk bina tamamlanması | 12 inşaat başlangıcı (gün) | 12 tamamlanma (gün) |
|---|---|---|---|---|---|
| yol -> plan (ana akış, D-008) | AÇIK (1) | **12** | **66** | 12,12,13,13,14,14,15,15,16,16,17,17 | 66..74, 86 |
| yol -> plan | KAPALI (0) | **12** | **66** | hepsi 12 | 66, 69 x10, 81 |
| plan -> yol | 1 ve 0 | 12 | 66 | hepsi 12 | 66, 69 x10, 81 (iki koşuda durum hash'i AYNI) |
| YALNIZ plan (yol hiç yok) | 1 ve 0 | **12** | **66** | hepsi 12 | 66, 69 x10, 81 (hash aynı) |
| YALNIZ yol (plan yok), 150 gün | 1 | inşaat yok | bina yok | - | - |
| yol -> plan, 30 parsel | 1 / 0 | 12 / 12 | 66 / 66 | q1: 12..18 yayılı / q0: hepsi 12 | son: 87 / 81 |

- Sim tohumu 1467, 2, 3 (yol-önce, rank 0): üçünde de aynı günler (12 / 66; q1 yayılımı ve son tamamlanma 86 aynı); yalnız durum hash'i değişir. Aday yol sırası 1 (248 m) ve 2 (208 m): 12 / 66, ve 12 / 69.
- 4 gün/sn: 1 sim günü = 0,25 gerçek sn. **İlk inşaat 12 gün = 3,0 sn; ilk bina 66 gün = 16,5 sn; 12 parselin sonuncusu 81-86 gün = 20-21,5 sn.** Yol çizildikten ilk inşaata: 16 gün = 4 sn (plan 1 gün sonra gönderilir, 3 gün yürürlük gecikmesi).
- Aynı koşular (tohum 1467): kuyruk açık/kapalı `plan -> yol` ve `yalnız plan` durumlarında durum hash'i AYNI, yani kuyruk bu akışlarda hiçbir şey değiştirmiyor. `yol -> plan`'da hash farklı (kuyruk çalışıyor, yalnız başlangıçları yayıyor).
- `--profile` adımı `Simulation.step` kopyasıdır: profilli ve profilsiz koşunun durum hash'i aynı (`df6745e706ac...`, 124 tick).

### Tick süresi (ms; sim `advance(1)` + projector dilimi ayrı; 105-125 tick/koşu, tohum 1467 ve diğerleri)
| Metrik | Değer |
|---|---|
| Ortalama tick (ilk tick hariç) | **3,8 - 4,6 ms** (ilk tick dahil 4,7 - 6,2); ortanca ~2,4 ms; p95 9 - 13 ms |
| İlk tick (tek seferlik başlatma) | **106 - 121 ms** |
| Yol onay tick'i (en kötü) | **62 - 74 ms** (rank 0, 108 m); rank 1 (248 m) **88 ms**; `submit_command` ayrıca 10 ms (rank 1: 32 ms) |
| Ay sınırı tick'leri (30/60/90/120) | **24 - 28 ms** |
| Siyaset günlük sıçraması (tick 105) | 13 - 16 ms |
| Plan tick'i (`zoning.propose` gönderimi) | 2 - 3,5 ms |
| Projector dilimi (tick + sonraki kare) | ort 1,6 - 1,8 ms, en çok 2,5 - 8,6 ms (30 parsellik planda 8,6) |
| 16,6 ms'yi aşan tick (ilk tick hariç) | 4 - 5 / koşu = yol tick'i + ay sınırları (kuyruk kapalıyken de aynı) |
- Kuyruk açık/kapalı tick maliyeti farkı gürültü içinde (ortalama 4,0 - 4,4 vs 4,1 - 4,5 ms; yol tick'i 62 - 74 ms her ikisinde).
- Kaynak dökümü (`--profile`, tek koşu tohum 1467): yol tick'i = `commands` 64 - 69 ms; ay sınırı = `economy.monthly` 23 ms; tick 105 = `politics.daily` 11 ms; `economy.daily` en çok 3 - 5 ms; `budget.monthly` < 1 ms. `WorldNetwork.graph_hash()` tek başına 32,7 ms ölçüldü; `PublicWorkRoadHandler` her yolda çağırıyor (`public_work_road_handler.gd:60`).
- Önceki sentetik ölçümle karşılaştırma (10 000 parsel): yol tick'i ~12 ms, ay sınırı 13,8 ms. Gerçek dünyada yol tick'i ~5-6 kat, ay sınırı ~1,8 kat yüksek.

## Bulgular (sorun adayı; oyun kodu değiştirilmedi)
1. **Gerçek oynanabilir veride yol gelişimi tetiklemiyor ve kuyruk fark yaratmıyor.** Yalnız plan: 12 / 66 gün; plan + yol: aynı; kuyruk kapalı: aynı. Sentetik testteki "kuyruk kapalı plan -> yol: 161 / 215 gün" farkı gerçek dünyada YOK. Yol-önce akışta kuyruk inşaat başlangıçlarını 12..17 güne YAYIYOR (kapalıyken 12 parselin hepsi 12. günde başlıyor) ve son tamamlanmayı 81 -> 86 (12 parsel) / 81 -> 87 (30 parsel) gün geciktiriyor. D-008 "yol çiz -> yatırımcılar bina yapsın" zinciri bu veriyle nedensel görünmüyor: bina planın sonucu, yolun değil.
   - Yol yokken planın inşaata dönüşmesi `playable_economy.json` `_unplanned_note`'taki bilinen açık iş ile uyumlu: bölge altyapı payı (`infra_headroom_pm` 300) yolun etkisini gizliyor. Bunu bu koşuda ayrıca ölçmedim (bölge boş kapasitesi okunmadı): **varsayım**.
   - Kuyruğun yayması muhtemelen kuyruk yolunun gün başı inşaat başlangıcı sınırından geçmesi, eski dikkat yolunun geçmemesi: **varsayım**, kod okunarak doğrulanmadı.
2. **Yol onay tick'i 62 - 88 ms** (16,6 ms bütçenin 4-5 katı; 4 gün/sn'de 250 ms'lik gün aralığına sığar ama 60 fps'te ~4-5 karelik takılma; 16 gün/sn'de 62,5 ms gün aralığını da aşar). Neden `commands` (yol işleyicisi); `graph_hash()` ~33 ms'lik kısım (yol ekleme + graf özeti): **varsayım**, işleyicinin içi ayrıca ölçülmedi.
3. **Ay sınırı tick'i 24 - 28 ms** (`economy.monthly` ~23 ms, 40 k parselle). Kuyruktan bağımsız taban maliyet; 4 gün/sn'de her 7,5 sn'de bir ~2 karelik takılma.
4. İlk tick 106 - 121 ms (tek seferlik; yükleme/ısınma sırasında olur, oyuncu görmez, görmeyebilir).

## Varsayılan / test edilmemiş
- **Yalnız D2'de ölçüldü** (4 geçerli aday); diğer bölgelerde yol-plan-bina süresi ölçülmedi.
- Tek dünya tohumu (1467). Sim tohumu 3 farklı; günler hepsinde aynı (ilk onay tohumdan bağımsız, önceki kayıtla uyumlu).
- 12 / 30 parselli plan denendi; daha büyük plan, çok yollu, ya da yol sonra ikinci plan zinciri denenmedi.
- Render / gerçek kare süresi ölçülmedi (başsız): yol tick'i + `RoadEditSync` + bina görünümü kurulumu bu rakamlara dahil değil.
- Oyun sahnesinin (`playable.tscn`) kendisi bu probe'da çalışmadı; `playable.gd` kurulumu taklit edildi (aynı sınıflar/aynı veri). Fark: görünüm düğümleri yok, yol komutu dev `submit_command` ile (UI çizim aracı yok).
- 4 gün/sn saniye karşılığı hesap (gün x 0,25), pencereli oyunda ölçülmedi; hız basamağı ve `max_ticks_per_advance` etkisi hesaba katılmadı.
- `verify quick/full` bu iş için çalıştırılmadı (oyun/test kodu değişmedi; yalnız yeni probe eklendi).
- Ham koşu çıktıları: `/private/tmp/claude-501/scratch_t043b/` (geçici, repoda yok).

## Yeniden üretme
`tools/godot.sh --headless --path . --script res://tests/sim/perf/t043b_real_world_probe.gd -- --queue=1 --rank=0 --order=road_first --days=260 [--profile]`
(`--order=plan_first|plan_only|road_only`, `--queue=0|1`, `--plan-n=N`, `--sim-seed=N`, `--list`). Kurulum ~30 sn, koşu başına ~35 sn.
