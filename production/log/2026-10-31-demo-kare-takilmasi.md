# Demo kare takılması · kök neden + düzeltme (2026-10-31)

Belirti (kullanıcının gerçek demosu, `playable.tscn --demo`, PLAYABLE_SMOKE): (a) plan teklifi/parsel seçimi sonrası tick
~176-339 avg 19-24 ms (max ~150); (b) tick ~1103-1495, 16 gün/sn, 120 karelik pencerelerde avg 93-111 ms; (c) tick
1582-1670 avg 36-46 ms; normal kare ~9 ms.

## Sonuç (tek cümle)

Kök neden: **gerekçe paneli (`ReasonPanel`) açıkken her sim tick'inde tüm liste düğümleri baştan kuruluyordu**
(`M2Results._on_refreshed` -> `rp.refresh()` -> `_render()`; sonuç/denetçi panellerinin aksine ne üst sınır ne imza
vardı). Panel açıkken tick'li kare ~45 ms (ölçüm), kayıt sayısı arttıkça daha fazla; hızda (16 tick/sn) neredeyse her kare
tick'li olduğu için kare süresi kalıcı yükselir. Düzeltildi; tick'li kare 45 -> 14,6 ms.

## Yöntem

`tests/sim/perf/demo_frame_probe.gd` (yeni): gerçek `playable.tscn` (gerçek dünya, HUD, sim, projector, yol görünümü) yüklenir,
sahnenin `_process`'i sabit dt (1/60) ile BU betikten çağrılır (tick sayısı deterministik), demo senaryosu sürülür: ısınma ->
yol çiz (`public_work.road`, 35 boş parsel yakında) -> imar teklifi (12 parsel, `zone.mixed`) -> hız "en hızlı" (16 gün/sn)
-> 1700 tick. Kare başına evreler `sim_stats` farklarından okunur (sim sürüşü / `hud.poll` / projector senkronu / görünüm
kurulumu / yol), kare toplamı (engine payı dahil) bir sonraki karenin başlangıcından. Seçenekler: `--panel=results|inspector|
reason|none`, `--legacy-reason` (düzeltme ÖNCESİ gerekçe paneli davranışının taklidi: her `refreshed`te koşulsuz `_render`),
`--speed`, `--ticks`, `--dt`. Çalıştırma:

    tools/godot.sh --path . --script res://tests/sim/perf/demo_frame_probe.gd -- --ticks=1700 --panel=reason [--legacy-reason]
    (başsız için `--headless` eklenir; çizim maliyeti yalnız pencereli koşuda vardır)

Donanım: Intel Mac, AMD Radeon Pro 560X, OpenGL (Compatibility). **iPad sayısı DEĞİL.**

## Ölçümler (tick'li kareler = 1701 kare; ms)

| Senaryo | hud.poll ort / maks | sim sürüşü ort | kare toplamı ort (engine dahil) |
|---|---|---|---|
| pencereli · gerekçe paneli, ESKİ (taklit) | **29,7 / 294** | 4,3 | **45,2** |
| pencereli · gerekçe paneli, DÜZELTİLMİŞ | **3,5 / 45** | 4,2 | **14,6** |
| pencereli · sonuç paneli (taban) | 3,3 / 28 | 4,3 | 13,6 |
| pencereli · denetçi paneli | 3,7 / 39 | 4,2 | 15,3 |
| başsız · panel yok | 3,2 / 5,5 | 4,7 | 9,2 |
| başsız · gerekçe paneli ESKİ (düzeltme öncesi kod) | 26,5 / 39,9 | 4,6 | - |
| başsız · gerekçe paneli DÜZELTİLMİŞ | 3,7 / 43,7 | 4,7 | 11,4 |

Tek çağrı (başsız/pencereli): gerekçe paneli yeniden kurma 34-38 ms (19 kayıt, 35 düğüm), düzeltmeden sonra aynı kayıt
kümesinde yenileme 0 ms (sığ kontrol: `reasons_for` ~6,8 ms, 250 ms'de bir). `hud.refresh` panelsiz 1,6 ms.
İdle (tick'siz) kare: `_process` ~1,0 ms, toplam ~9 ms (kamera/HUD/çizim dahil).

### Aday listesi: ölçülen etki

- **Gerekçe paneli koşulsuz yeniden kurma: KÖK NEDEN** (yukarıda; yeniden üretildi, düzeltildi, geri-yeşil doğrulandı).
- Sim tick catch-up: **kök neden DEĞİL.** `max_ticks_per_advance` 64; 16 tick/sn'de 60 fps karede 0,27 tick/kare. Tick
  başına sim ort 4,2-4,7 ms. AMA katlayıcı: panel açıkken tick'li kare 45 ms olunca kare uzar, aynı karede daha çok tick
  işlenir (`drive_usec` borcu öder), kare daha da uzar. Kullanıcıdaki 93-111 ms büyük olasılıkla bu + daha uzun liste (benim
  senaryomda 19 kayıt; kullanıcıda tick 1100+ ve daha çok kayıt olabilir: **doğrulanmadı**, yalnız kayıt sayısıyla arttığı
  görüldü).
- **Ay sınırı tick'i (ARTA KALAN, düzeltilmedi):** sim 26-39 ms, 30 tick'te bir (başsız, 40 493 parsel). 16 tick/sn'de ~1,9 sn'de
  bir kare 16,6 ms bütçesini aşar; 4 tick/sn'de 7,5 sn'de bir. T-043B probu 10 000 parselde ~14 ms demişti; gerçek dünya
  4 kat parsel. `simulation-engineer` konusu (sim saflığı/GOLDEN'a dokunulmadı).
- İlk tick ~105-112 ms ve yol tick'i (tick 6) ~70 ms: bilinen, pencereli akışta ısınma örtüsü altında (ilk tick); yol
  komutu tick'i sim (ağ/yol maliyeti). Yol görünümü yerel yenilemesi 155-175 ms arka thread; ana iş parçacığında benimseme
  karesi ~52 ms (bitki koridoru 7,1 ms dahil). Bunlar tek seferlik, (a)'daki maks ~150 ms ile uyumlu.
- Bina görünümü (HLOD hücre) yeniden kurulumu: bu senaryoda 6 görünüm kurulumu / 1700 tick, her biri <= 3,3 ms; projector
  senkronu kare ort 0,6 ms. Kök neden değil (sınırlı: yalnız 2-12 satırlık yeni gelişim; çok bina bitirilen uzun oyunda
  **ölçülmedi**).
- Bildirim şeridi + olay projeksiyonu: panelsiz `hud.poll` ort 3,2 ms (şerit, üst çubuk, snapshot dahil), maks 5,5.
- Sonuç paneli: ort etkisi küçük (3,3), `M2ResultModel.build` 1,3 ms, 250 ms'de bir.
- Denetçi paneli: model kurma ~8,9 ms + yeniden çizim ~10,5 ms (250 ms üst sınırı var); ay sınırı tick'lerinde `hud.poll`
  35-39 ms'ye çıkıyor (imza değişir). Ortalamayı bozmaz, ama ay sınırı sim hitch'iyle üst üste biner (tek karede ~65-95 ms).
  Taban maliyet `reasons_for(parsel)` ~6,6 ms/çağrı (32 kayıt): `ui-engineer`/`simulation-engineer` için öneri (indeks).
- Plan/parsel overlay yenilemesi (a için): bu senaryoda ayrı bir maliyet göstermedi; (a)'nın 19-24 ms ortalamasının tam
  kaynağı **doğrulanmadı** (muhtemelen o aralıkta açık olan gerekçe/denetçi paneli + ay sınırı tick'leri; kullanıcının hangi
  paneli açtığını bilmiyorum).

## Düzeltme (düşük riskli, yalnız UI; sim/GOLDEN'a dokunulmadı, `playable.gd` değişmedi)

1. `src/ui/flows/m2_results.gd`: gerekçe paneli de sonuç panelinin mevcut 250 ms üst sınırını (`default_interval_msec`) ve
   tek kuyruklu son-durum yenilemesini kullanır (`_refresh_panel` ikisini de yeniler; `_build_reason` zamanı işaretler).
   Testler `default_interval_msec = 0` ile eskisi gibi anında yeniler.
2. `src/ui/panels/reason_panel.gd`: liste görünümünde kayıt kimlikleri son çizimdekiyle aynıysa düğümler yeniden kurulmaz
   (gerekçe kayıtları yalnız eklenir, değişmez). Yeni kayıt gelince liste yeniden çizilir; ayrıntı/ret/iş görünümleri eskisi
   gibi yeniden okunur. Yan fayda: yenilemede odak ve kaydırma kaybolmaz.
3. Test: `tests/ui/reason_panel_refresh_test.gd` (3 test: aynı kayıt -> aynı düğümler; yeni kayıt -> liste büyür; ayrıntı hâlâ
   yeniden kurulur). Geri-yeşil: `if _list_unchanged()` kapatıldığında ilk test KIRMIZI (düğüm kimlikleri değişti), geri alınca yeşil.

## Doğrulama durumu

DOĞRULANMIŞ (bu oturumda çalıştırıldı):
- Probe: yukarıdaki tabloda tüm satırlar (pencereli = Intel Mac/Radeon 560X/OpenGL; başsız = çizimsiz CPU).
- `uvx --from gdtoolkit==4.5.0 gdlint src/ui/panels/reason_panel.gd src/ui/flows/m2_results.gd tests/sim/perf/demo_frame_probe.gd`:
  temiz.
- `tools/verify.sh quick`: PASS, 1290 test, 0 hata/0 başarısızlık (kısmi: tests/app, art, library, view, world ve canon-guard
  ATLANDI; tam doğrulama DEĞİL). Kapsama yeni test dahil (3/3). Çalışma ağacında BAŞKA bir oturumun değişiklikleri de vardı
  (`data/game/playable_economy.json`, `src/game/playable_economy.gd`, `tests/game/m2_render_support.gd`,
  `tests/game/playable_infra_capacity_test.gd`); onlar bu işin dosyası değil.

VARSAYILAN / DOĞRULANMAMIŞ:
- Kullanıcının 93-111 ms ortalamasının TAMAMI bu nedenle mi: bu makinede aynı panel/senaryoyla 45 ms (kayıt sayısı 19)
  yeniden üretildi; daha uzun listede artışı mantıksal olarak bekliyorum ama ölçmedim. Kullanıcının hangi paneli açık
  tuttuğunu varsayıyorum (gerekçe paneli).
- (a) penceresinin 19-24 ms ortalaması ve ~150 ms maksimumu tam açıklanmadı (yukarıda).
- Kullanıcının kendi demosunda düzeltme sonrası kare süresi (gerçek fare/kamera, GPU yükü, bitki görünümü açık) ölçülmedi;
  probe kamera hareket ettirmez. Başsız bitki koşusu (`--veg-force`) sim/HUD maliyetinde fark göstermedi (aynı ort).
- iPad: ölçüm yok.

TEST EDİLMEMİŞ:
- Gerçek fare/dokunma ile panel açıp uzun süre hızlı oynama (kullanıcı demosu), çok bina tamamlanan uzun oyunda HLOD yeniden
  kurulum maliyeti, `tools/verify.sh full`.

## Artan öneriler (yapılmadı)

1. Ay sınırı tick'i 26-39 ms (gerçek dünya): sistem bazında profil (`t043b_real_world_probe.gd --profile`) ile ayrılıp
   gün-içi dilimlenebilir mi diye `simulation-engineer`e (determinizm riski: sim değişimi, ayrı görev).
2. Yeni gerekçe kaydı geldiğinde liste hâlâ baştan kuruluyor (~35 ms, seyrek): yalnız yeni satırları ekleyen artımlı çizim.
3. `reasons_for` / denetçi `InspectorModel.build` ~6,6-8,9 ms: facade'de konu indeksi.
4. `playable.gd` PLAYABLE_SMOKE satırına `hud.poll` ve sim ms ayrımı eklenebilir (dosya 1000 satır sınırında; ayrı dosyaya
   çıkarılmalı). Şimdilik `demo_frame_probe.gd` bu ayrımı veriyor.

## Değişen dosyalar

- `src/ui/flows/m2_results.gd` (gerekçe paneli yenileme üst sınırı)
- `src/ui/panels/reason_panel.gd` (liste imzası)
- `tests/ui/reason_panel_refresh_test.gd` (yeni)
- `tests/sim/perf/demo_frame_probe.gd` (yeni ölçüm aracı)
- `production/log/2026-10-31-demo-kare-takilmasi.md` (bu kayıt)
