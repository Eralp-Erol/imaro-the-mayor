# ADR-0006 · Onaylı kütüphane varlıklarının oyuna entegrasyonu (T-062: A bina+zemin, B bitki, C donatı)

- Durum: önerildi · Tarih: 2026-10-27 · Karar veren: technical-director. Yaratıcı etkisi olan noktalar §8'de "kullanıcı kararı" olarak ayrıldı; bu ADR onları seçmez.
- Karşıladığı gereksinimler: WLD-01, TEK-01, TEK-02, TEK-03, SIM-01, VIS-01, VIS-02, VIS-03, VIS-05, CAN-03
- Dayanak: D-005 (60 approved / 45 rejected), `design/library/README.md` §0 (yalnız `approved` oyunda), ADR-0001/0004 (bütçe, profil), `design/specs/art/building-kit-v1.md` §7–§9, `production/qa/T-057-technical-review.md` Karar 4 §4.4 ve Karar 5.

## 1. Bugünkü mimari (doğrulandı: kod ve veri okundu)

- **Tek modül tablosu:** `KitLibrary.load_manifest()` → `assets/models/buildings/kit_manifest.json` (46 modül). Bu tablo hem `T0Settlement.generate_detailed` / `SettlementRules` (yerleşim: aile, kat, ayak izi) hem `SimBuildingPlacer` (sim yapıları + inşaat kademesi) hem de `BuildingKit.from_library` (render) için TEK kaynak. `BuildingColumns.module_idx` = manifest sırası.
- **Render:** `BuildingView` (`src/view/buildings/`): 1 km hücre → modül başına LOD0 ve LOD1 `MultiMeshInstance3D` (+ LOD1 yalnız-gölge düğümü, 700 m), hücre başına `HLOD1` (PROXY şablonları birleşik, köşe rengi palet satırından), 4×4 km `HLOD2` kütle kutuları. Tüm MMI'lar tek `mat_kit` ShaderMaterial (`material_override`, palet satırı INSTANCE_CUSTOM'da). `BuildingLod`: LOD0 < 1450 m, LOD1 < 2850 m, HLOD1 < 13 km — **hücre merkezine göre** (`visibility_range` AABB merkezi). `FarLod` yalnız arazi/yol için metroda tek mesh.
- **Oyun:** `src/game/playable.gd` `world_preview.gd`'yi genişletir; T0 görünümü + ikinci `BuildingView` ("SimBuildings", projector → pump). T0 sütunları sim'e başlangıç stoğu olarak gider (`PlayableStock.from_columns`: birim = kat). Kent zemini: `UrbanGroundMask` (RG8) arazi gölgelendiricisinde; yollar vertex-color unshaded `StandardMaterial3D`, UV yok.
- **Kullanımdaki kayıtlar:** oyunda çizilen 42 bina modülünün **tamamı D-005'te `rejected`**; `prop_chimney`, `prop_human`, `veh_car` de rejected (oyunda çizilmiyor, manifestte duruyor). `settlement.json` kimlik düzeyinde rejected kimliklere bağlı: `bld_lmk_clocktower` (tower), `bld_res_old_c(_gf)` (id_weights), `bld_ind_shed_b`. `veg_plane` (kit, approved) oyunda kullanılmıyor.
- **Onaylı varlıklar (katalog sayımı):** bina 21 hero (7 aile × a/b/c), zemin 14 doku, bitki 10 hero + `veg_plane`, donatı 8, insan 6.
- **Hero ↔ kit farkları (doğrulandı, katalog/manifest):**
  - LOD0 1.572–6.738 üçgen (kit ort. ≈ 261: 12,98 M / 49.735 yapı); hero LOD1 258–552 (kit LOD0 bandına denk), hero PROXY 30–80 (kit LOD1 22–60 bandına denk; kit PROXY ≤ 14).
  - Ayrı GLB'ler (`assets/hero/fam|lod/`), dokulu atlas materyali (`mat_hero_atlas`, 1024² atlas × 21, `compress/mode=0`), palet satırı yok.
  - Pivot cephe çizgisinde (+Z ön, bbox z ∈ [−derinlik, +1..4]); kit pivotu ayak izi merkezi. Temel eteği 0 (kit 2,5 m).
  - Aile başına tek kat sayısı/tek ayak izi (a/b/c yalnız stil). Kat sayısı katalogda yok; üreteçte `SPEC["NF"]`.
  - `lod_chain.distances_m` (100/300 m) "working-model-not-integrated".
  - Hero GLB import'u `generate_lods=true` (README §5.2 "otomatik mesh LOD kapalı" ile çelişir). Zemin dokuları `mipmaps/generate=false`.
- **Taban ölçüm (artifacts/perf, 2026-10-25, playable `--demo`):** street ort 7,62 / p95 16,43 ms, 178 dc, 262k üçgen; district 7,48 / 16,13 ms, 219 dc, 386k; metro 5,86 / 12,1 ms, 133 dc, 544k. **Street p95 bütçe sınırında (16,6 ms)**: pay yok denecek kadar az.

## 2. Karar — genel

1. **Tek kapı, iki katman:**
   - (a) Derleme zamanı: `tools/library/build_game_set.py` yalnız `approval == "approved"` VE güncel dosya hash'i `user_approved_sha256` ile eşleşen kayıtlardan oyun tablolarını üretir: `data/library/game_buildings.json` (kit manifest şemasında `modules[]`), `game_ground.json`, sonra `game_vegetation.json` ve `game_furniture.json`. Üretilen dosya `source_catalog_sha256` taşır; drift testi var.
   - (b) Çalışma zamanı: `LibraryGate` (`src/view/library/library_gate.gd`, saf `RefCounted`) `catalog.json`'u okur. Oyun yükleyicileri kimliği yalnız bu kapıdan alır. Onaysız kimlikte `push_error` olur, kimlik yüklenmez ve `stats["unapproved_ids"]` sayılır.
   - Hash denetimi çalışma zamanında YAPILMAZ: dışa aktarımda .glb kaynağı yoktur. Hash'i `verify full` içindeki `validate_catalog` denetler.
2. **Modül tablosu değişimi:** yerleşim ve render aynı tabloyu okur.
   - `KitLibrary.MANIFEST_PATH` yerine `game_buildings.json` gelir: kit şeması korunur, `lods.*.glb` seviye başına ayrı yol olur.
   - Sim→görünüm bağı (`BuildingColumns`, projector, pump, `PlayableStock`) **değişmez**. Değişen yalnız tablo verisi.
   - Kit dosyaları silinmez, yalnız oyundan kopar. Silme ayrı temizlik görevidir.
3. **Hero varyant seçimi (a/b/c):** her varyant ayrı modül kimliğidir. Seçimi mevcut seed'li `T0Settlement` aile ağırlıkları ve `_repair_neighbours` (komşu aynı modül olmasın) yapar; sim yapılarında `SimBuildingPlacer` aynı işi yapar. Yeni RNG akışı yok, deterministik.
4. **Pivot normalizasyonu tek yerde:** mesh yükleyici, LOD0/LOD1/PROXY köşelerini GLB'deki ayak izi merkezine (bbox XZ merkezi) kaydırır. Tablo `footprint_m` = bbox XZ (konservatif) ve `pivot_offset_m` yazar. `BuildingGround` (en düşük örnek − 0,2 m) değişmez.
5. **Bütçe biçimi:** kit v1 §9 / README §5.2'deki varlık başına üçgen tavanları (ÇM) onaylı hero varlıklarda **sahne bütçesiyle** değiştirilir. Sahne bütçesi: yerel evre ≤ 900k görünür üçgen, ort ≤ 8 ms, p95 ≤ 16,6 ms (masaüstü referans). Aşım varlığı kırparak değil, mesafe ya da yoğunlukla çözülür. Gevşetme yok. (T-057 §4.5'in istediği çelişki çözümü budur; art-director'a bilgi.)

## 3. Aşama A — bina + zemin (en küçük sağlam tasarım)

### 3.1 Kademe eşlemesi (hero LOD'ları mevcut 4 kademeye oturur)

| Bugünkü kademe | Hero temsili | Aralık (başlangıç = bugünkü değer, ölçümle değişir) |
|---|---|---|
| LOD0 MMI (1 km hücre) | **hero LOD1** (258–552 tri, aynı atlas) | 0 – 1450 m (merkez) |
| LOD1 MMI | **hero PROXY** (30–80 tri, 256² proxy atlası, dokulu) | 1450 – 2850 m |
| HLOD1 birleşik | PROXY şablonu; köşe rengi proxy atlasından üçgen merkez UV'sinde **yükleme anında pişirilir**. `config.hlod1_source = proxy\|box` | 2850 m – 13 km |
| HLOD2 kutular | renk modül başına pişirilmiş çatı/duvar ortalamasından (palet satırı yerine) | > 10,5 km |
| gölge | **PROXY** yalnız-gölge düğümü (`shadow_caster_lod = 2`), 700 m | — |

- Hero LOD0 (1,5–6,7k tri) A1'de **çizilmez**. Gerekçe: 1 km hücre merkezli `visibility_range` ile 100–150 m'lik bina başına geçiş yapılamaz. LOD0'ı 1450 m bandına koymak yapı üçgenini ~15× büyütür (hesap, ölçüm değil).
- **A2 (koşullu):** yakın kademe hero LOD0, yalnız şu iki koşul birlikte sağlanırsa eklenir:
  - art-director street preset'te (60 m, 12°) LOD1'i FAIL eder;
  - `experiments/t062-near-tier/` deneyi Compatibility'de MultiMesh örnek başına mesafe kesmesini doğrular. Kesme gölgelendiricide yapılır: `MODEL_MATRIX` örnek dönüşümünü içeriyor mu, `CAMERA_POSITION_WORLD` mevcut mu — ikisi de **DOĞRULANMADI**, engine-reference'ta yok.
  - Tasarım: LOD0 256 m alt hücrelerde, aralık sonu = R0 + yarım köşegen; gölgelendirici d ≥ R0'da örneği söndürür. Bu durumda LOD1 MMI'ı d < R0'da söner. R0, T-057 §4.4 kuralıyla ölçülür.
  - Deney düşerse A2 yapılmaz; LOD1 en yakın temsil kalır ve kullanıcıya bildirilir.
- Materyal:
  - Hero MMI'larda `material_override` YOK; GLB yüzey materyali (atlas) kullanılır. Bu yüzden `BuildingView._make_mmi` modül başına materyal alır.
  - Draw call modül × kademe × hücre olarak kalır. Modül sayısı 42 → 21 olduğundan MMI sayısının düşmesi beklenir (varsayım).
- Import ayarları (PNG/GLB hash'i değişmez, onay bozulmaz):
  - hero GLB `generate_lods=false`;
  - atlaslarda VRAM sıkıştırma kararı ölçümle verilir. 21 × 1024² RGBA, mip'li ≈ 117 MB VRAM (hesap); iPad için risk;
  - zemin dokularında mipmap açık.
  - Sıkıştırmanın görsel etkisi art-director kapısından geçer.

### 3.2 Yerleşim verisi (world-engineer)

- `settlement.json` aile adları hero ailelerine eşlenir. Eşleme veri olarak tutulur ve ÇM statüsündedir; art-director + systems-designer önerir. Önerilen başlangıç:
  - res_mid → hero_res_mid
  - res_late → hero_res_late
  - res_house → hero_res_house
  - res_old ve res_old_town → hero_old_core
  - civ_hall → hero_civ_hero
  - ind_shed ve ind_heritage → hero_ind_hero
  - ticari zemin kat (`_gf`) → hero_com_bazaar (kullanıcı onayına tabi, §8)
- Rejected kimliğe bağlı kurallar kaldırılır: `id_weights`, `tower.module`, `bld_ind_shed_b`.
- `SettlementRules`:
  - boş palet satırına izin verir (`wall/roof/accent = 0`, hero renk taşımaz);
  - onaylı landmark yoksa kule yerleştirmesini atlar ve bunu `stats["tower"] = "none-approved"` olarak raporlar.
- Kat sayısı: technical-artist üreteçten (`SPEC["NF"]`) `floors`, `eave_height_m`, `roof_type` ve `gf` alanlarını kataloğa / `game_buildings.json`'a aktarır. Bu alanlar uydurulmaz.
- **Sonuç:** T0 stoğu değişir (birim = kat; aile başına tek kat). Ekonomi taban değerleri ve demo nedensellik çıktıları yeniden ölçülür. Determinizm korunur: aynı seed → aynı stok.
- `sim_building_mapping.json` aileleri güncellenir.
- İnşaat kademesi: aile içinde daha az katlı modül yok. Bu yüzden mevcut geri düşüş çalışır: nihai modül inşaat başlarken görünür. Bu, görünür bir davranış değişikliğidir (§8).

### 3.3 Zemin (A-zemin; godot-engineer + technical-artist)

- `terrain_land.gdshader`, kapıdan geçen onaylı katmanlardan kurulan bir `sampler2DArray` örnekler. Desen `assets/ground/ground_lab.gdshader`'dan alınır; UV dünya xz / `tile_m`, yeni draw call yok.
  - Sınıf → katman eşlemesi `data/view/terrain_look.json` içinde tutulur (art-director önerir).
  - Kent maskesi: R → plaza_stone_a / dirt_courtyard, G (sanayi) → gravel.
  - Kıyı → beach_sand, eğim → rock_cliff, kırsal → grass_dry / scrub_maquis / olive_ground, tarla → field_*.
- Yollar: `RoadView` materyali dünya-xz örnekli bir ShaderMaterial olur. Asfalt new/worn seçimi yol sınıfına ve kenar kimliği hash'ine göre `road_style.json`'dan yapılır.
- `detail_far` ötesinde sınıf rengine solma uygulanır (metroda moiré yok).
- `gnd_macro.png` ve `gnd_lab_ctrl.png` katalogda olmadığı için oyunda **kullanılmaz**. Mevcut `noise_tex` kalır.
- Compatibility'de `sampler2DArray` için emsal `ground_lab` lab'ıdır. Oyunda doğrulanmadı.

### 3.4 Kabul / ret (A)

- **Kabul:**
  1. `playable.tscn --demo` içinde çizilen her modül/katman kimliği `LibraryGate`'ten `approved`. Test ve çalışma zamanı sayacında `unapproved_ids = 0`.
  2. Rejected kit yolu/kimliği `src/`, `scenes/game/`, `data/world/`, `data/view/`, `data/library/game_*.json`'da yok. İzinli liste: kit_lab ve tools.
  3. Sim deterministik: iki koşu aynı `state_hash`; save/load smoke OK.
  4. Windowed yakalamalar (street/district/metro + `--m2-advance` sim yapısı) ve art-director PASS.
  5. Perf §6'ya göre ölçülmüş.
- **Ret:** tek bir onaysız kimlik görünürse, sim hash'i koşular arasında değişirse, art-director FAIL verirse ya da masaüstü bütçe mesafe kısaltmasıyla da tutturulamazsa. Son durumda yama yığılmaz; A2/kademe kararı TD'ye geri gelir.

## 4. Aşama B — bitki (taslak)

- **Yerleşim (world-engineer):** `src/world/vegetation/vegetation_placement.gd` saf ve seed'lidir (dünya seed'i + "veg" etiketli alt akış). `VegetationColumns` (species, x, z, yaw, scale) üretir. Kaynaklar:
  - yol kenarı ağaç sırası (yol sınıfı + kaldırım);
  - meydan (`_find_plaza`);
  - parsel arka bahçe ve ev çiti (lot verisi);
  - arazi sınıfı ve eğim (maki/çam yamaç, zeytin D4/D5 tarla kenarı).
- Kurallar kit v1 §7'den gelir. Palmiye yalnız kıyı/meydan sırasında kullanılır.
- Sim'e girmez: görünüm süsüdür, sim hash'i değişmez.
- Q-018 açık: iki palmiye türü de veri ağırlığıyla (eşit, `data/view/vegetation_placement.json`) yerleştirilir. Bu bir seçim değildir.
- `veg_plane` (kit, mat_kit yolu) varsayılan olarak yerleştirilmez. Hero çınar aynı rolü taşır; tek materyal yolu korunur. Veri ile açılabilir.
- **Temsil (godot-engineer):** `VegetationView`, LOD0 → LOD1 → hücre lekesi (Karar 5).
  - Tek ortak atlas olduğundan tür başına MMI kullanılır.
  - LOD0/LOD1 için 256 m alt hücre: 1 km hücre merkezi 120/400 m bandını taşıyamaz.
  - Leke: 1 km hücre başına birleşik alçak disk/kutu, P3 tonu, köşe renkli, gölgesiz.
  - Palmiyeler mevcut PROXY'yi ara kademe olarak kullanır.
- **Eşik ölçüm kuralı (T-057 §4.4 aynen):**
  - 17 bakışta ε_m ölçülür.
  - `d* = ε_m·H_px / (2·tan(FOV/2)·e_max)`; e_max, art-director'ın kabul ettiği bir geçişin ölçülmüş e_px'idir.
  - Hücre MMI'ında `begin = d* + r_hücre` (256 m hücre için ≈ 181 m).
  - Profil başına ayrı hesaplanır. `d*`'dan yakına çekilmez.
  - 120/400 m yalnız başlangıç; ölçümle değişir ve dosyayla kaydedilir.
- **Ret koşulu:** street preset'te bitki draw call'ı + üçgeni bütçeyi aşar ve mesafe/yoğunlukla düzelmezse LOD1 tier'ı hücre başına birleşik mesh'e çevrilir (tek atlas sayesinde mümkün). Bu çeviri ayrı karardır.

## 5. Aşama C — sokak donatısı (taslak)

- **Yerleşim (world-engineer):** `src/world/furniture/furniture_placement.gd` saf ve seed'lidir. Kaynak yol kenarları ve kesişimlerdir: lamba aralığı, durak (arter/toplayıcı aralığı), bank/çöp/bisiklet park/kiosk (meydan, ticari cephe), bollard (meydan kenarı), saksı. Yoğunluk `data/view/street_furniture.json`'dan, yol sınıfı + bölge + T0 yoğunluğundan türer (README §1.4).
- **Temsil:** tek atlas, tip başına MMI, 256 m alt hücre. LOD0/LOD1 < ölçülen mesafe; README §5.2 başlangıç değerleri 250/400 m. Uzakta çizilmez.
- **İnsan:** bu ADR'de yerleştirilmez. CAN-03 + T-062: insan yalnız sim verisinden türer (nüfus/aktivite). Sim'de yaya/ajan verisi henüz yok; sahte kalabalık yok. Stil seçimi (Q-018) ve "insan nereden türer" ayrı kullanıcı kararı ve ayrı görevdir.

## 6. Test ve ölçüm planı

- **Perf tabanı:** A'ya başlamadan, aynı commit'te:
  - `tools/perf.sh t062-base-<preset> --scene res://scenes/game/playable.tscn -- --demo --preset=<metro|district:D1|street>`, preset başına 3 koşu (±%40 yük gürültüsü; ADR-0001), medyan alınır.
  - Her aşama ve alt adım (A1, A-zemin, A2, B, C) sonrasında aynı komut çalıştırılır.
  - Rapor alanları: ort/p95 kare, draw call, primitives, `build_stats.buildings` (lod tris, mmi_nodes), açılış süreleri (settlement_ms, view_ms, GLB yükleme), video belleği.
  - iPad: ölçülmedi diye yazılır; geçti denmez.
- **Yeni testler:**
  - `library_gate_test` (approved geçer; proposed/rejected/eksik/boş-hash reddedilir);
  - `game_set_drift` (python, üretilen = commit'li);
  - `no_rejected_reference_scan`;
  - `hero_pivot_test` (yüklenen mesh AABB XZ merkezi ≈ 0);
  - `building_lod_test` genişler (`problems()` boş, kademe çakışması);
  - `playable_approved_only` (başsız: `BuildingKit.ids` ⊂ approved, `unapproved_ids = 0`);
  - B/C için yerleşim determinizmi ve yasak alan (yol/su/yapı) testleri.
- **Değişecek testler:**
  - `tests/world/settlement/*` (sayılar/hash'ler yeni tabloyla yeniden tabanlanır; gerekçe görev dosyasına);
  - `tests/view/buildings/{building_kit,building_view,building_chunk_builder,building_hlod2,building_test_support,sim_building_placer*,dev_building_source}_test`;
  - `tests/game/m2_*` (T0 stoğuna bağlı beklenen sonuçlar: önce yeniden ölçülür, sonra güncellenir; zayıflatma yok);
  - `terrain_look_test`, `road_view_test` (materyal);
  - `urban_ground_mask_test` (sayım).
- **Korunacak (değişmemeli):** `tests/sim/**` (fixture tabanlı; varsayım: T0'a bağlı değil, ilk koşuda doğrulanır), `tests/contracts/**`, `can03_guard_test`, `honest_zoning_test`, kamera testleri, `tests/library/*` (onay/katalog), `tests/art/kit_*` (kit dosyaları silinene dek).

## 7. Alternatifler ve neden reddedildi

| Seçenek | Artı | Eksi |
|---|---|---|
| Görünüm-yalnız ikame (kit sütunlarını koru, render'da kit modülü → hero) | Yerleşim/sim değişmez | Ayak izleri uyuşmaz (çakışma, yola taşma); rejected tablo gizli bağımlılık olarak kalır; ölçeklemek dokuyu bozar |
| Hero LOD0'ı mevcut LOD0 bandına (1450 m) koymak | Kod değişikliği en az | Yapı üçgeni ~15× (hesap); street p95 zaten sınırda |
| Godot otomatik mesh LOD | Kodsuz | README §5.2 yasaklıyor; onaylı LOD zinciri yerine motor üretimi geometri (onaysız görünüm) |
| Her bina ayrı `MeshInstance3D` + kendi `visibility_range` | Bina başına doğru LOD | 49.735 düğüm; draw call patlaması (Compatibility ~15–20 µs/çağrı) |
| HLOD1'de proxy atlasından birleşik doku | Uzakta doku | 21 atlası tek atlasa paketleme işi; 2,85 km+ mesafede piksel kazancı yok |

## 8. Kullanıcı kararı gerektirenler (bu ADR seçmez)

1. **Landmark:** saat kulesi rejected. T0'da landmark olmadan mı kalınsın, yoksa yeni landmark önerisi mi istenir? (Kit v0 S4 açık.)
2. **İnşaat kademesi görünümü:** hero aileleri tek boy. Yapı inşaat başında tam boy görünür (mevcut geri düşüş). Alternatif bir temsil (kat kademesi için ailede kısa varyant ya da iskele varlığı) yeni varlık üretimi ve onayı ister.
3. **Ticari zemin kat:** `_gf` (dükkânlı cephe) rolü yalnız hero_com_bazaar ile mi taşınsın? Yoksa konut ailelerine dükkânlı varyant mı üretilsin (yeni varlık → onay)?
4. **Çeşitlilik:** 7 aile × 3 stil ≈ 50k yapı. Tekrar riski art-director yakalamasıyla gösterilir; ek aile üretimi kullanıcı kararıdır.
5. **İnsan:** stil (Q-018) ve sim'den türeme kuralı; C'de yerleştirilmez.
6. **Rejected kit dosyalarının repodan silinmesi:** A kabulünden sonra ayrı temizlik görevi.
- Q-018 bu ADR'de seçilmiş sayılmaz. Palmiye eşit ağırlık bir veri varsayılanıdır.

## 9. Kanıt

- **Doğrulanan (okundu):**
  - `playable.gd`, `world_preview.gd`, `building_view|kit|lod|chunk_builder|ground|view_config.gd`, `kit_library.gd`, `sim_building_mapping(.json)`, `sim_building_placer.gd` (başlık + kademe), `t0_settlement.gd` (imza/aile kullanımı);
  - `catalog.json` (sayım, lod_chain, bbox), `kit_manifest.json` (modüller, pivot), `settlement.json` (kimlik referansları);
  - import dosyaları, atlas boyutları;
  - perf JSON'ları (2026-10-25); ADR-0001/0004, kit v1 §7–9, README §0/§5, T-057 Karar 4–5.
- **Hesap (ölçüm değil):** ~15× üçgen, 117 MB VRAM, 256 m hücre yarım köşegeni.
- **Varsayılan / doğrulanmadı:**
  - MultiMesh `MODEL_MATRIX` örnek dönüşümü ve `CAMERA_POSITION_WORLD` (Compatibility);
  - oyunda `sampler2DArray`;
  - MMI sayısının düşeceği;
  - `tests/sim/**`'ın T0'dan bağımsız olduğu;
  - hero GLB'lerin tek yüzey/tek materyal olduğu.
- **Ölçülmedi:** bu planın hiçbir perf etkisi, iPad, hero LOD1'in 60 m'de sanat kabulü, bitki eşikleri.
- **Yeniden açma tetikleyicisi:**
  - A1 sonrası masaüstü bütçe mesafe kısaltmasıyla tutmazsa;
  - A2 deneyi düşerse ve art-director LOD1'i FAIL ederse;
  - iPad ölçümü 117 MB atlas belleğini taşımazsa.
