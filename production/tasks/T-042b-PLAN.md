# T-042b planı · yol yapılı bloktan geçer: kamulaştırma, bina kaldırma, tepki (technical-director, 2026-10-30)
REQ: CAN-03, CAN-04, CAN-05, SIM-03, SIM-05, SIM-12, WLD-01, WLD-09, TEK-01/02/03/05 · Karar: D-008, D-009 · AÇIK: Q-017, Q-003, Q-022 (commit'siz), T-014.
Sözleşme: ADR-0005 Ek F (ÖNERİLDİ, v1.4). [okundu] = kodu okudum; [ölçülmedi] / [çıkarım] ayrı yazıldı. Godot çalıştırılmadı. Ön koşul: T-042 adım 3-4 commit'li.

## 1. "Parsel kümesi sabit" varsayımı nerede [okundu] ve nasıl gevşer
- Sim: `parcel_source.gd:9-11,19-30` (statik şablon, kayda girmez) · `list_parcel_source.gd:14-32` (kimlikler kurulumda bir kez sıralanır) · `sim_facade_impl.gd:84-85`
  (`world.parcel_count` duruma yazılır), `:369-377` (`import_save` `world_mismatch` + `EconomyState.validate_data(n)`) · `economy_system.gd:125-146` (`_cache_static`:
  `_ids/_area/_base_land/_base_zone/_region_of` indeksle), `:149-197` (`_ensure_state`: 11 sütun n boyunda), `:350` (tarama n üzerinden), `:37-43,231-251` (T0 stoku)
  · `economy_state.gd:38-46,176-192` (sütun boy denetimi; `SPARSE_KEYS` ilk kurulumda yaratılır: yeni anahtar t0 hash'ini değiştirir) · `parcel_regions.gd:10-27`
  (bsearch dizini, `politics_context.gd:18`).
- Oyun/görünüm: `playable.gd:353-402` (`_start_sim`, `_parcel_views`; commit'siz değişiklik var, satırlar kayabilir), `:227-228` (`_t0_occupied`), `:239` (T0 sütunları
  bir kez) · `sim_building_projector.gd:345` (tam eşitleme `facade.parcel_ids()`).
- Dünya: `world_network.gd:518-534` (`refresh_blocks`), `:589-591` (`keep_parcels_on_delta` → yeni yüz `KIND_OPEN`), `:602-664` (yeniden parselleme, `_next_parcel_id`),
  `:684-708` (`_remove_block` parselleri siler) · `network_local_refresh.gd:4-5` (**yerel ve tam yenilemede kimlik atama sırası farklı olabilir; kimlik hash'e girmez**)
  · `road_draft_check.gd:87-90,114-120` (`crosses_parcels` reddi + `parcels_changed` geri alma) · `public_work_road_handler.gd:60` (op başına tam `graph_hash()`).
- **A · Sabit küme + "alındı" bayrağı (ÖNERİLEN).** Sim kümesi ve kimlikleri hiç değişmez. Yolun koridoruna giren parsel BÜTÜNÜYLE alınır: sütunda yeni aşama değeri
  `STAGE_TAKEN = 5`, kökeni `public_works.taken {parcel_id: work_id}`. Dünya bölünen bloğu yeniden PARSELLEMEZ: alınmayan parseller kimlikleriyle yeni yüzlere taşınır,
  alınanlar emekliye ayrılır (journal'a yazılır). Yeni kimlik yok.
- **B · Değişken küme / yeniden numaralama (RET).** Ekonomi indeksleri, `ParcelRegions`, gerekçelerdeki `parcel.N`, değişim halkası, projector hepsi kırılır; dünya
  kimlikleri yenileme yoluna bağlı ve hash dışı (`network_local_refresh.gd:5`) → kimlik determinizmi sim'e taşınamaz; kayıt dünya tanımını taşımak zorunda kalır.
- **C · Delta parsel katmanı (SONRA).** Taban sabit + yalnız sona eklenen parseller (sim sayacından kimlik), silme = A'nın bayrağı. A'nın üst kümesidir; "yeni yolun
  boyunca YENİ arsa" gerektiğinde (D-008 yeni yüzde bina) ayrı görev. T-042b'ye gerekmiyor; `parcel_count` kuralı ve sütun büyümesi büyük iş.
- A neden: **determinizm** (alınan küme yalnız geometri + op + korunan küme; yenileme yolundan bağımsız) · **altın hash'ler** (yeni durum yalnız `public_works` bölümünde ve
  yalnız yazıldığında; `STAGE_TAKEN` yolsuz koşuda yazılmaz; `SPARSE_KEYS/PARCEL_COLUMNS` değişmez → t0 hash, GOLDEN_A/B aynı) · **kayıt** (`parcel_count` aynı;
  `public_works` v1 kaydı v2'ye kayıpsız yükselir, `taken` boş) · **geri alma** (journal alınan parsel nesnelerini kimliğiyle geri koyar; mekanizma var, `parcels_removed`).
  Bedel: kısmi kamulaştırma yok (köşesi kesilen parsel bütün alınır); C ile açılır.

## 2. Sim modeli (kamulaştırma ve yıkım)
- Komut: `public_work.road` + isteğe bağlı `expropriate: bool` (yok/false = bugünkü davranış, `crosses_parcels`). Ret args'ı `expropriation` önizlemesini taşır; UI
  "Kamulaştırarak geç?" teklifini sim'in sayısıyla yapar. Yeni komut türü yok (CAN-03 önekleri aynı).
- Önizleme args (sim hesabı): `parcels, built_parcels, res_units, com_units, households, regions, protected`, `cost_available:false`. İmleçte yaklaşık koridor testi
  (~1 ms); `validate_command`'de KESİN önizleme = sessiz kuru koşu (uygula + geri al, değişim günlüğüne/`graph_version`'a yazmadan) [ölçülmedi, ~20 ms tahmini].
- Yeni ret: `protected_structure` (T0 `FLAG_HERITAGE/LANDMARK/CIVIC`, veri `protect_flags`; Q-017 cevabına dek muhafazakâr: ret; WLD-09), `expropriation_disabled`
  (veri bayrağı), `expropriation_changed` (tick'te alınan küme önizlemeden farklı → `command.rejected`, durum bozulmaz).
- Tick sırası (tek işleyici, parsel kimliği artan): ağ op'u → dünya raporu `removed_parcels` == hesaplanan küme (değilse geri al + ret) → parsel başına `stage=TAKEN`,
  `units/use/owner=0`, `res_built/com_built` ve boru hattı düşümü (inşaattaki proje iptal), bekleyen imar temizlenir, `ParcelChangeLog.note` → hane politikası → olaylar.
- Olaylar: `public_work.expropriated` (subjects `command.N`, `parcel.N…`, `region.<kod>`; args sayımlar) → `public_work.built` → `command.applied`. Parsel başına gerekçe
  `decision.municipal.expropriate` (SIM-12; denetçi "Kamulaştırıldı ← Yol (gün N)").
- Tepki (D-008, SIM-05): `public_works.displaced {bölge: [[tick, hane]…]}` → `BlocSignals` yeni sinyal `displacement` (pm, sönümlü) → hangi kesimin nasıl tepki verdiği
  `data/politics/blocs.json` verisi (systems-designer). Yolsuz koşuda sinyal 0 ve durumda saklanmaz (altın hash koruması; aksi halde yalnız bölüm varken eklenir).
- **Q-017'ye BAĞLI (uydurulmaz; hepsi veri bayrağı, varsayılanı systems-designer ÇM önerir, kullanıcı cevabı yalnız veriyi değiştirir):** (i) binalı parsel alınabilir mi
  (`allow_built`); (ii) yerinden edilen hane: `return_to_latent` (bölge talebine döner) / `leave_region` / `rehouse_queue`; (iii) işletme kaybının etkisi; (iv) sahibe bedel ve
  kim öder (Q-017 §3, Q-022, T-014): HUD'da "Bedel: henüz kurulmadı", para yok (Q-003); (v) süre/itiraz (`delay_days`, v1'de 0); (vi) tarihî yapı kuralı; (vii) sahibin
  yatırımcı duyarlılığına etkisi (varsayılan kapalı).
- **Q-017'den bağımsız (D-009 kullanıcı kararı):** yolun binalı bloktan geçebilmesi, yıkımın dünyada görünmesi, olay + gerekçe + tepki üretilmesi.
- Geri alma: teknik olarak iki yol da mümkün. Kalıcı seçilirse `undo_last` → `irreversible` (altındaki eski yollar da LIFO gereği kilitlenir). Geri alınabilir seçilirse
  `works[]` alınan satırların anlık görüntüsünü taşır, tepki olayı geri alınmaz. Ürün sorusu 2.

## 3. Dünya ve görünüm
- Dünya: `player_roads.crossing_parcels: "expropriate"` + op'ta `expropriate: true`. Yenileme sırası: etkilenen blokların parselleri önce havuza, sonra yüzler kurulur; yeni
  yüz merkezi içinde kalan havuz parsellerini kimliğiyle alır (cephe yeniden atanır, `_update_matched_block` mantığı), koridorla kesişen ya da sliver/su yüzüne düşen
  parsel emekliye ayrılır. Tam ve yerel yenileme AYNI fonksiyonu kullanır. Değişmez: `added_parcels` boş, `removed_parcels` == `RoadDraftCheck.taken_parcels(...)`.
- Korunan küme oyun katmanından gelir (T0 `BuildingColumns.flags` → `PublicWorksContext.protected_parcels`). T0 kütüphane onayına bağlı olduğundan alınan kimlikler op'ta
  da saklanır; yüklemede yeniden üretilen küme farklıysa `network_mismatch` (sessiz sapma yok).
- Bina kaldırma: T0 yapıları değişmez `_t0_columns`tan alınan kümeyle süzülür → `BuildingView.set_columns` yalnız hash'i değişen hücreyi + süper hücreyi (HLOD2) kurar
  (`building_view.gd:91-108`). `BuildingChunkPlan.build` tüm satırları tarar [ölçülmedi]: > 8 ms ise artımlı `BuildingView.remove_parcels(ids)`. Sim yapıları projector
  feed'iyle düşer (`STAGE_TAKEN` → satır yok). Kent zemini maskesi (`apply_urban_ground`, bir kez) yerel güncellenir ya da yol örter [varsayım, görselde bakılır].
  Seçim: alınan parsel ızgaradan çıkar (`parcel_id_at` bulmaz); denetçi gerekçeyi kimlikle gösterir. Yükleme: epoch → projector tam eşitleme, T0 maskesi yeniden.
- Performans: tick'te yol uygulaması ~62 ms (çağırandan) ≈ yeniden denetim ~1 + `add_road` 17-22 + op başına tam `graph_hash` 31-34 ms [çıkarım: ölçüm günlüğü + handler:60].
  Düşürme: (1) `WorldNetwork`'te artımlı, sıra bağımsız graf özeti (düğüm/kenar başına 64-bit karma toplamı, journal ile O(Δ), geri almada da); `hashes[i]` bu özet, tam
  SHA yalnız taban/kayıt/yükleme/testte (`public_works` v2; v1 kaydı SHA yoluyla doğrulanır) → ~-33 ms. (2) Gönderimdeki denetim `graph_version` aynıysa tick'te yeniden
  kullanılır. (3) `add_road` kırılımı (planarize / `extract_local` / eşleme) ölçülür, en büyük kalem düşürülür. (4) Kamulaştırma eki O(k) ≤ 3 ms hedef.
  **Hedef:** kamulaştırmalı tek yolda tick sim işi ≤ 25 ms (dev Mac; oyuncu onaylı tek seferlik takılma, birleşik kapı T-074), görünüm işi karelere dilimli ≤ 8 ms/kare.
  iPad ölçülmedi.

## 4. Aşamalı teslim (aynı dosyaya iki yazıcı yok; adımda yalnız hedefli `tools/lane.sh verify <hat>`, sonda bir kez `verify full`)
1. **world-engineer** (`src/world/network/`, `data/world/ismeral/network.json`, `tests/world/network/`, `experiments/t042b-probe/`): expropriate modu, `taken_parcels`,
   havuzlu yenileme, artımlı graf özeti, sessiz kuru koşu. Kabul: 500 tohumlu özellik testi (ekle → `added_parcels` boş, removed == taken, kalan parsellerin kimlik +
   çokgeni aynı; geri al → taban graf özeti + `parcel_set_hash`; yerel == tam; yeniden oynatma bit-eşit); rastgele op zincirinde artımlı özet == baştan hesap; ölçüm
   tablosu (D1/D6'da ret oranı mod açıkken, `add_road` kırılımı, `BuildingChunkPlan.build` süresi).
2. **simulation-engineer** (önce Ek F + mock + fixture, `src/contracts/`, `tests/contracts|fixtures`; sonra `src/sim/public_works/`, `src/sim/economy/`, `src/sim/politics/
   bloc_signals.gd`, `data/sim/public_works/`, `data/politics/blocs.json`, `tests/sim/`): 1'e bağlı (sözleşme + mock 1'e paralel yazılabilir). Kabul: t0 hash + GOLDEN_A/B
   değişmez; v1 kaydı yüklenir; kamulaştırmalı yolla kaydet → yükle → N tick hash eşit; aynı komut dizisi → aynı sim hash + graf özeti (5 tohum); çift senaryo: binalı
   blokta yol → bölge `res_built` düşer, `displacement` > 0, gerekçe kaydı, olay sırası; olumsuz: korunan yapı, `expropriate` yok, tick'te küme değişti → durum aynı;
   tick süresi ölçümü ≤ 25 ms.
3. **godot-engineer** (`src/game/`, `src/view/buildings/`, `src/view/overlay/road_draft_preview.gd`, `tests/game|view`): 2'ye bağlı. Kabul: gerçek viewport girdi
   testi (binalı bloktan yol → onay → tick → yalnız beklenen hücre/süper hücre kuruldu, bina yok, seçim alınan parseli bulmuyor); yükleme sonrası aynı sütun hash'i;
   `m2-t042b-*` yakalamaları; kare ölçümü (dilim ≤ 8 ms).
4. **ui-engineer** (`src/ui/`, `data/ui/strings.tr.json`, `tests/ui`): mock ile 3'e paralel. Kabul: önizleme "N bina yıkılacak, M hane yerinden edilecek, Bedel: henüz
   kurulmadı" (sayılar sim args'ından), iki adımlı onay, yeni ret metinleri, denetçide "Kamulaştırıldı ← Yol (gün N)", tepki bildirimi gerçek olaydan.
5. **qa-engineer** + art-director + technical-director: tek `verify full`, bağımsız QA (`production/qa/T-042b-qa.md`), görüntü kapısı, inceleme.
- Paralel: 1 ∥ 2'nin sözleşme/mock kısmı → 2 → (3 ∥ 4) → 5.

## 5. Riskler
- R1: havuzlu yenileme `_build_block/_remove_block` sırasını değiştirir; T-042 v0 yolları ve taban üretimi bozulmamalı (v0 özellik testleri aynen geçmeli).
- R2: kuru koşu paylaşılan ağı geçici değiştirir; iş parçacıklı okuyucular (`RoadView` ≥4 chunk, bitki) için `busy` koruması şart; günlük/`graph_version` kirlenmemeli.
- R3: `STAGE_TAKEN` her `stage` tüketicisinde (ParcelView, projector, UI, `SimContractChecks`) ele alınmalı; unutulan yer "vacant" gösterir (sahte HUD riski).
- R4: kısmi kamulaştırma yok: kırsalda büyük parselin köşesini kesen yol bütün parseli alır; ölçümde sıklığı raporlanır, gerekirse C.
- R5: Q-022 cevabı "önce bütçe" çıkarsa T-042b sırası T-014'ün arkasına kayar; mimari etkilenmez.

## Kullanıcıya ürün soruları (en fazla 2)
1. **Kamulaştırmanın ilk sürümü?** (a, Önerilen) Yol geçtiği arsayı bütün alır, bina hemen yıkılır, sakinler bölgede yeniden ev arar, mahalle tepki verir; tarihî yapılar
   korunur, bedel "henüz kurulmadı". (b) Önce yalnız boş arsalardan geçsin (yıkım yok), binalı arsalar bütçe gelince. (c) Bedel + süre + itirazla tam süreç (T-014 şart, en uzun).
2. **Yıkım içeren yol geri alınabilsin mi?** (a, Önerilen) Hayır: onaydan önce iptal edilir, onaydan sonra kalıcıdır. (b) Evet, son yol geri alınır ve binalar geri gelir
   (halkın tepkisi geri alınmaz).
