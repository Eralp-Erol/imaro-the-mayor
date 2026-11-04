# Yol gönderim denetimi ve geri alma maliyeti (gerçek Ismeral, 40 493 parsel) · 2026-10-31

Kaynak: `production/log/2026-10-31-blok-cikarimi-ilk-tick.md` "Kalanlar" 1-2. Dal: `worktree-agent-aed3ebe1c83843370` (commit hash'i aşağıda). `src/view/**`, `src/ui/**`, `src/game/playable.gd` değişmedi.
REQ: WLD-01 (tek dünya verisi; çıktı değişmedi), TEK-01/02 (sim saflığı, determinizm), CAN-04 (oyuncu yolu; denetim sonucu aynı). Kanon/D-kararları değişmedi.
Not: worktree başlangıçta `main`'de idi ve önceki iki logun işi yoktu; `git merge --ff-only agent/handover-imaro-m01-349562fb` ile (yalnız ileri sarma, b8a1f8c) o dalın üstüne alındı.

## Sonuç (önce -> sonra, ms)

Ölçüm: gerçek Ismeral ağı (4 267 düğüm / 7 366 kenar / 40 493 parsel), başsız, duvar saati, aynı betik iki ağaçta (HEAD `git archive` kopyası ve bu dal), her ölçüm 7 tekrar, min / medyan.
Makine ölçüm sırasında YÜKLÜYDÜ (load average ~10-12, başka ajanların Godot koşuları): mutlak sayılar sessiz makineden kötü, "önce/sonra" aynı koşullarda alındı. Kabul kararı değildir.
Aday yollar `t043b_real_world_probe.gd --list` rank 0 (108 m) ve rank 1 (248 m).

| Metrik | Önce (min / medyan) | Sonra (min / medyan) | Hedef |
|---|---|---|---|
| `RoadDraftCheck.check`, rank 0 (108 m) | 4,81 / 5,19 | **1,15 / 1,20** | <= 8 ULAŞILDI |
| `RoadDraftCheck.check`, rank 1 (248 m) | 15,23 / 17,00 | **0,87 / 0,89** | <= 8 ULAŞILDI |
| Bileşen sorgusu, geri almadan sonra (arada sorgu var) rank 0 / 1 | 30,50 / 34,54 ; 30,15 / 31,90 | **0,01 / 0,01** ; **0,01 / 0,01** | <= 5 ULAŞILDI |
| Bileşen sorgusu, ekle + geri al (arada sorgu YOK) rank 0 / 1 | 30,72 / 35,17 ; 31,97 / 32,93 | **0,01 / 0,01** ; **0,01 / 0,01** | <= 5 ULAŞILDI |
| `net.add_road` (apply_checked) rank 0 / 1 | 2,79 / 3,69 ; 4,30 / 5,47 | 2,50 / 2,84 ; 4,18 / 4,79 | (kötüleşme yok) |
| `undo_last_op` rank 0 / 1 | 1,71 / 1,88 ; 3,28 / 3,83 | 0,35 / 0,38 ; 2,10 / 2,42 | |
| Bileşen sorgusu, ekle sonrası (yama) | 0,39 - 0,55 | 0,40 - 0,42 | |
| Probe `road_submit_ms` (`submit_command`, yük altında, sessiz makinede önce: 4,9 / 14,7) | | 2,28 / 1,63 | |

Sim sonucu AYNI (probe `--queue=1 --order=road_first --days=260 --profile`, bu dalda yeniden koşuldu): rank 0 son durum hash'i `04fc00b292e2664ff24bd7604a15e23686174bf9d390311d796d5c7b89907c94`, rank 1 `686b1a8d6d15db265fdd90ef48031327a4ba21ff475b48455f82f2f3196e483c`
(önceki logdaki değerlerle birebir). Probe tick sürelerini (ortalama 3,6 / 4,6 ms, 16,6 ms'yi aşan tick rank 1'de 6) yük nedeniyle KARŞILAŞTIRMAYA KATMADIM (kurulum 28 s yerine 47-83 s sürdü).

## Kök nedenler ve değişiklikler

### 1) Gönderim denetimi: `first_parcel_hit`
Profil (`tmp` betiği, aşama aşama): `check` süresinin neredeyse hepsi `first_parcel_hit` (rank 0: 5,7 / 6,2; rank 1: 18,5 ms); diğer aşamalar (örnekleme, su, bölge, eğim, kopya, bağlantı sayımı) toplam < 1 ms.
Rank 1 taslağı için 375 örnek; her biri `_in_parcelized_block` -> `block_at`: ızgara sorgusu (2,6 ms) + büyük, parselsiz blokların çokgen içinde-mi sınaması (~9 ms); 375 örneğin 375'i bir bloğun İÇİNDE, yalnız 3'ü parselli blokta.
- Yeni `src/world/network/road_draft_parcel_scan.gd` (`RoadDraftParcelScan`): özgün denetim "örneği içeren İLK blok parselli mi" diye sorar; hiçbir PARSELLİ blok örneği içermiyorsa o blok (varsa) parselsizdir ve sonuç zaten false.
  Bu yüzden taslağın kutusuyla (köşeler + yarı genişlik + 1 m) çakışan PARSELLİ blokların ızgara kutuları ve (küçük) çokgenleri bir kez toplanır; örnek önce bunlara sorulur. Hiçbiri içermiyorsa `block_at`/`_on_road_strip` hiç çağrılmaz.
  Biri içeriyorsa (nadir) özgün `_in_parcelized_block` AYNEN çalışır => `found` ve `at` değişmez. Kutu sınaması `NetworkSpatialHash.query_point` ile aynı çağrı (`Rect2.intersects(..., true)`), blok sırası aynı (kimlik sırası).
- `RoadDraftCheck.first_parcel_hit`: yukarıdaki ön eleme (+ tek noktalı taslakta erken çıkış, özgün döngüyle aynı sonuç). Genel API ve sonuç biçimi değişmedi.

### 2) Geri alma sonrası bileşenler: önceki önbelleği geri koy
Kök neden: `undo_last_op` -> `_touch()` işaretsiz çağrılıyor => `_component_cache.clear()` => sonraki sorgu tam hesap (~30-35 ms). Yama düğüm silmeyi bilerek reddeder (geri almada eklenen düğümler siliniyor); yamayı silmeye genişletmek ayrık bileşenleri bölebildiği için (köprü yolu geri alma) güvenilir değil.
Seçilen çözüm: önceki önbelleği geri yükle (ağ geri almadan sonra işlemden önceki ile BİREBİR aynı: kimlikler, kenarlar, hash).
- `NetworkComponents` (`network_components.gd`): `of` ve `memo` Dictionary'den `PackedInt32Array`e çevrildi (`of`: düğüm -> indeks, -1 yok; `memo`: kenar başına (a, b, açık)). Nedeni: Dictionary kopyası 2-3,4 ms, Packed kopyası 0,005 ms (ölçüldü).
  Bulgu: Godot 4.7'de Packed*Array atama ve argüman geçirmede PAYLAŞILIR (yerel değişken değişince sözlükteki de değişir; küçük sınama betiğiyle doğrulandı) => anlık görüntü açıkça `duplicate()` ister.
  `remember(net, journal)`: işlem başında (`NetworkOpJournal.begin`) her kipin `of`/`memo`/bekleyen işaretlerini kopyalar (`list` yerinde değiştirilmediği için paylaşılır), `journal.components`a yazar (~0,03 ms). `restore(net, saved)`: `undo_last_op`ta `_touch()` sonrası sözlüğü YERİNDE doldurur (`NetworkHashCache` aynı sözlük nesnesini tutar).
  Bellek sınırı: yalnız son `UNDO_SNAPSHOTS` = 8 işlemin günlüğünde kopya tutulur (işlem başına ~0,1 MB / kip, en çok ~1-2 MB; hesap, ölçülmedi); daha eski bir işlem geri alınırsa kopya yoktur => eski davranış (önbellek temizlenir, tam hesap; doğru ama yavaş).
- `world_network.gd`: `undo_last_op` +1 satır (`NetworkComponents.restore`), `component_of` 1 satır değişti (`NetworkComponents.index_of`); dosya 973 -> 974 satır. `network_op_journal.gd`: `components` alanı + `begin`de `remember` (+3 satır).

Yama/derleme mantığı (`_patch`, `_scan`, `_reindex`) aynı kaldı, yalnız veri yapısı Packed oldu (çıktı bit-bit aynı: testler).

## Değişen dosyalar
Yeni: `src/world/network/road_draft_parcel_scan.gd` (+ `.gd.uid`), `tests/world/network/road_draft_parcel_scan_test.gd` (+ `.gd.uid`), bu log.
Değişen: `src/world/network/{network_components,network_op_journal,road_draft_check,world_network}.gd`, `tests/world/network/network_derived_cache_test.gd` (+4 test).
`tools/verify-areas.tsv` değişmedi (yeni dizin yok; `tools/verify-scope.sh check`: area-map tamam).

## Doğrulanmış (koşturuldu, bu dalda)
- Artımlı == tam eşdeğerlik (`network_derived_cache_test`, 9/9; 5 eski + 4 yeni): geri alma sonrası `components()` ve `component_of()` taze referans DFS'ye eşit (liste, sıra, indeksler), hem arada sorgu VARKEN hem YOKKEN (ardışık işlemler); yol ekleme + ayrık parçayı bağlayan köprü yolunun geri alınması (bileşen ikiye bölünür); `set_open` ve `remove_edge` geri alma;
  kopya penceresinden (8) derin yığın (12 işlem) tamamen geri alma (pencere dışı tam hesaba düşer, yine eşit, `restored` sayacı tam 8); geri al + yeniden çiz aynı bileşenler. Geri almalarda `rebuilt` sayacı ARTMIYOR (tam hesap yok) ve `restored` işlem sayısı kadar artıyor. Tüm eski dizi/rastgele (4 tohum x 30 adım) testleri geçiyor (her adımda eşitlik, geri alma dahil).
- `first_parcel_hit` eşdeğerliği (`road_draft_parcel_scan_test`, 4/4): el yapımı parselli ızgarada 120 rastgele taslak (bulundu > 10, temiz > 10) + tek nokta + sıfır uzunluk; hafif Ismeral ağında 150 taslak; yalnız yan örneklerin (±30 m) bloğa girdiği özel durum: yeni == özgün (`found`, `at`).
- Gerçek ağda ek eşdeğerlik (tek seferlik betik, `tmp`/scratchpad, git'e girmez): `first_parcel_hit` 600 rastgele taslak x 3 yarı genişlik = 1 800 karşılaştırma (1 621 "bulundu", 179 "temiz"), 0 uyuşmazlık; 40 adımlık rastgele dizi (geçerli taslak ekle 17, geri al, aç-kapa; her adımda `components()`/`component_of()` == taze `NetworkComponents.build`, `graph_hash()` == `graph_hash_full()`): 0 uyuşmazlık, tüm geri alma sonunda `graph_hash == base_hash`.
- Kırmızı-yeşil (mutasyon): `restore` çağrısı kapatılınca 3 yeni geri alma testi KIRMIZI (7 başarısızlık); anlık görüntüde `of` kopyalanmayıp paylaşılınca KIRMIZI (282 başarısızlık + script hatası); `covers` bir bloğu atlayınca `road_draft_parcel_scan_test` KIRMIZI (107); örnek kutusunun yarı genişlik payı kaldırılınca (`grow(0)`) önce test YEŞİL kaldı (boşluk), yan-örnek testi eklendi ve KIRMIZI oldu. Hepsi geri alındı, yeşil doğrulandı.
- Suite'ler (GdUnit, 0 hata / 0 başarısızlık / 0 yetim): `tests/world` + `tests/view/roads` + `tests/contracts` 535 (GOLDEN uyumlu ağ/blok/parsel testleri, hash önbellek testi, undo/yerel yenileme dahil); `tests/sim` (recursive, GOLDEN_A/B `m2_query_test` dahil) + `tests/world/network` + `tests/game` + `tests/unit` + `tests/app` 1 080; `tests/ui/road_draw_panel_test` 12.
  `tests/view` + `tests/ui` + `tests/art` toplu: 792 test, 0 hata / 0 başarısızlık, 10 yetim düğüm uyarısı (GdUnit çıkış 101 = yalnız uyarı; bu işin dosyalarına değil sahne/UI testlerine ait, HEAD'de ayrıca karşılaştırılmadı).
- Probe: iki aday için durum hash'i HEAD ile birebir aynı (yukarıda).
- gdlint (`uvx --from gdtoolkit==4.5.0 gdlint src/world/network tests/world/network`): temiz. `tools/verify-scope.sh check`: tamam.

## Varsayılan / test edilmemiş
- `verify quick/full` KOŞTURULMADI (talimat); yukarıdaki GdUnit kümeleri verify'ın yerini tutmaz. GOLDEN_A/B ve world-hash testleri `tests/sim` / `tests/world` içinde geçti.
- Ölçümler yalnız D2, tohum 1467, başsız, YÜKLÜ makine; yalnız iki aday (rank 0/1). Render, `RoadEditSync`, gerçek pencere kare süresi, UI iş parçacığındaki toplam gönderim yolu (UI -> komut kuyruğu) ölçülmedi. Dış sınıra yakın / yoğun kentsel taslaklar için `check` maliyeti: parselli bloğa giren taslakta (`crosses_parcels` reddi) özgün yol bir kez `_in_parcelized_block` çalıştırır (ilk isabetten çıkar); ölçülmedi, gerçek ağda 1 621 bulundu karşılaştırması doğruluğu kanıtlar, süresi değil.
- Geri alma kopya penceresi 8 işlem. Daha eski işlemler yavaş yola (~30 ms) düşer; oyuncu için nadir varsayıldı, ölçülmedi. Bellek tahmini (işlem başına ~0,2 MB) hesap, ölçülmedi.
- Yama/geri yükleme yalnız `WorldNetwork` API'si ve geri alma yardımcıları üzerinden değişen ağlarda geçerli (önceki loglarla aynı bayatlama koşulu): mühürlü ağda düğüm/kenarı bu yollar dışında yazan yeni kod bileşen önbelleğini bayatlatır; yeni op türü eklenirse `NetworkOpJournal.begin` zaten kopyayı alır (ek iş gerekmez) ama test dizisine eklenmeli.
- Mühürde ~0,25 s ısınma (kalan 3) bu işte DEĞİŞTİRİLMEDİ (`build` Packed olduğu için bir miktar hızlanmış olabilir; ölçülmedi).
- `ADR`/kanon değişikliği yok; `HashCache`, `graph_hash`, blok/parsel çıktıları koda dokunulmadı (yalnız bileşen önbelleği ve yalnız-okur denetim).

## Kalanlar / öneriler
1. Penceredeki gerçek gönderim kare süresi (UI -> `submit_command` -> `RoadEditSync`) hâlâ ölçülmedi; `check` artık ~1 ms, kalan maliyet başka yerde olabilir.
2. Mühür ısınması (0,25 s) için tembel ısıtma.
3. `economy_system.gd` 993 satır (sınır 1000) ve `world_network.gd` 974: yeni mantık ayrı dosyaya.

Geçici betikler `/private/tmp/...` scratchpad (git'e girmez); yaptığım hiçbir araçlandırma kaynakta kalmadı.
