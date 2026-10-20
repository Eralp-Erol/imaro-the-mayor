# Yol haritası

Kaynak: foundation F03 "Oyun hissi için doğrulanması gereken kabul ölçütleri" ve F01 sütunları. Milestone'lar dikey dilimdir: her biri gerçek 3D dünyada gözlemlenebilir bir sonuçla biter. Sayılar/takvim çalışma tahminidir; AÇIK kararlara bağlı milestone'lar işaretlidir.

| M | Ad | Amaç (çıkış ölçütü özeti) | Ana REQ | Karar bağımlılığı |
|---|---|---|---|---|
| M0 | Stüdyo kurulumu | Harness, araçlar, kapılar, ADR'lar, doğrulanmış iş akışı | TEK-* | — (tamam, bkz. `docs/STUDIO.md`) |
| M1 | Tek dünya iskeleti + platform temeli | Ismeral'in arazi/kıyı/körfez/ova/yamaç ve D1–D6 bölge verisi tek koordinat sisteminde; metro ve ilçe ölçeğinde aynı veriden render; T0 yerleşim yoğunluğu kaba düzeyde (D1+D6 çekirdek, diğerleri küçük merkezler, liman ana karada); kamera metro↔sokak kesintisiz; sim çekirdeği iskeleti (tick, durum, RNG, kayıt, determinizm testleri); dünya-kanon testleri. Platform temeli: profil katmanı, macOS + Windows export hattı, çapraz platform determinizm testi altyapısı. Görsel kapı: "boş grid üzerinde 4 blok" değil, yaşayan körfez kenti silueti. | WLD-01..05, WLD-08, TEK-01..04, PLT-01..06, VIS-01, VIS-04 | Windows cihazı (yalnız çalıştırma testi için) |
| M2 | İlk nedensel döngü (dikey dilim) | Geliştirme test alanı Orven'de (D2 — stüdyonun teknik seçimi, D-002; oyuncu başlangıcı veri parametresi ve en az iki ilçe kimliğiyle başlatma testi) sokak ölçeği; oyuncu yol/kamusal alan çizer ve imar değiştirir → yatırımcı kendi koşullarıyla karar verir (gerekçeli; olumlu + olumsuz senaryo) → inşaat zamanla ilerler → hane/işyeri, bütçe, ≥2 grup tepkisi + küçük meclis → oyuncu aynı alanı farklı zoom'larda inceler. Masaüstü profiliyle kabul; iPad'de aynı dilim cihazda oynanır (dokunmatik profil, ölçüm). F03 kabul ölçütlerinin tamamı. | CAN-03..06, CAN-08, SIM-01..05, SIM-07..09, SIM-12, WLD-01, WLD-12, VIS-02..03, PLT-02 | — |
| M3 | Yaşayan metropol | Diğer ilçeler oyuncu bakmıyorken evrilir (toplu model); makro koşullar; ulaşım/trafik sorunu ve hava (yağmur) görünür; altyapı kapasite/bakım maliyeti; farklı politikalarla ayrışan şehirler (SIM-10). Ortam sesi başlangıcı. | WLD-11, SIM-04, SIM-06, SIM-10, SIM-11 | — |
| M4 | Siyasi kariyer katmanı | Seçim, itibar, medya, çıkar grupları, kaybetme sonucu; kampanya akışı ilçe dönemi. | CAN-07, CAN-10 | **Parti/seçim/başlangıç senaryosu kararları (F05-D)** |
| M5 | Metropol yönetimi | Aynı karakter metropol başkanlığına yükselir; ilçeler arası projeler, alt belediyeler paydaş; dünya sıfırlanmaz. | CAN-07, CAN-11, WLD-09 | Yetki modeli (F05-D) |
| M6 | Ulusal mücadele ve final | Anderva ölçeği (aynı dünya), diğer metropoller soyut; cumhurbaşkanlığı seçim zaferi finali. | CAN-07, CAN-09, WLD-10 | Diğer metropol adları/karakterler (F05-D) |
| M7 | Üretim cilası ve yayın | İçerik genişletme (birden çok oynanabilir ilçe — D-002), ses, anlatı içeriği, performans, Windows/macOS yayın paketleri ve iPadOS, cihaz testleri. | CAN-08, TEK-04, TEK-05, PLT-01..06 | Monetizasyon (F05-D) |

## Önerilen ilk üretim dikey dilimi
**M1 + M2 = "Tek dünya, tek ilçe, ilk nedensel döngü."** Ismeral'i bütün olarak kaba ama doğru coğrafyayla kurar, sonra bir ilçede imar → yatırım → inşaat → ekonomi → siyasi tepki zincirini gerçek 3D dünyada kanıtlar. Bu, foundation'ın "oyunun ana vaadini gösterme" şartını (F06) ve F03 kabul ölçütlerini en küçük kapsamda karşılar.

## Platform test hedefleri
ADR-0004 § Platform test hedefleri. Özet: macOS (geliştirme Mac'i) her görevde; macOS + Windows export M1'den itibaren her milestone'da; Windows **çalıştırma** testi cihaz sağlanınca; iPadOS (iPad Pro M serisi, D-004) M1'de: önce boş sahneyle zincir (T-007), ilk grafik + girdi prototipinden sonra duman testi (T-008); renderer/kalite profili karşılaştırması T-010; çapraz platform `StateHash` tekrar oynatma testi her yeni cihazda.

## M1 görevleri
| ID | Başlık | Sahip | Bağımlı | Paralel |
|---|---|---|---|---|
| T-001 | Ismeral dünya verisi iskeleti + metro ölçeğinde render + dünya-kanon testleri | world-engineer (+ godot-engineer render) | — | A |
| T-002 | Sim çekirdeği iskeleti: tick sürücüsü, GameState, RNG akışları, komut kuyruğu, kayıt/yükleme, determinizm testleri | simulation-engineer | T-900 ✓ | A |
| T-007 | Platform temeli: profil katmanı (`platform_profile`), export şablonları (4.7.2, sağlama toplamıyla), macOS + Windows export preset'leri, `tools/export.sh`, macOS export duman testi | godot-engineer | — | A |
| T-003 | Çok ölçekli kamera rig'i (metro↔sokak): masaüstü girdi profili birincil + dokunmatik profil; origin rebasing; standart capture preset'leri | godot-engineer | T-001, T-007 | B |
| T-004 | Low-poly yapı kiti v0 (3–4 dönem apartman, zemin kat dükkân, depo/sanayi, sivil yapı) + HLOD proxy'leri | technical-artist | art spec (art-director) | B |
| T-009 | Çapraz platform determinizm: senaryo tekrar oynatıcı + `StateHash` karşılaştırması; macOS'ta koşu, Windows/iPad için hazır | simulation-engineer + qa-engineer | T-002, T-007 | B |
| T-005 | T0 yerleşim üreteci v0: bölgelere göre yoğunluk/kullanım, D1+D6 çekirdek, ana kara limanı/sanayi | world-engineer | T-001, T-004 | C |
| T-008 | iPad duman testi: T-001 dünya önizlemesi + T-003 kamera/dokunmatik profil cihazda; kare süresi, girdi, güvenli alan; ekran görüntüsü/video | qa-engineer + godot-engineer | T-003, T-007 | C |
| T-010 | Renderer ve kalite profili karşılaştırması: Compatibility / Mobile / Forward+ — macOS Intel ve iPad (Metal); scale-bench + gerçek sahne; sonuç ADR-0004 profillerine | godot-engineer + technical-director | T-007 (iPad için T-008 sonrası tekrar) | B |
| T-006 | M1 kapısı: metro/ilçe/sokak capture'ları, macOS export'unda ve iPad'de ölçüm (render / sim / birleşik ayrı), Windows export'u (cihaz varsa çalıştırma), art + design + technical director incelemesi | qa-engineer + directors | T-003, T-005, T-008, T-009, T-010 | — |

T-001'i bloklayan platform işi yoktur: T-007/T-010 paralel ilerler, T-008 ilk görüntü+girdi prototipini bekler.

## Paralel üretim (2026-10-20 · kullanıcı kararı: T-001 diğer hatları bloke etmez)
Departmanlar, hat sahipliği, çalışma kuralları ve kayıt defteri: `production/LANES.md` (araç: `tools/lane.sh`). Eklenen görevler (M1/M2 yolu; ayrıntılı dosya yalnız başlayınca açılır):
| ID | Başlık | Hat / sahip | Bağımlı | REQ |
|---|---|---|---|---|
| T-023 | ADR-0005 Sim↔View↔UI sözleşmeleri + MockSimFacade + WorldFixture | contracts / technical-director | — | TEK-01..03, SIM-12 |
| T-025 | Sanat spec v0: yapı kiti kuralları + arazi paleti | art / art-director | — | VIS-01..07 |
| T-015 | Karakter/NPC/siyasi olay spec v0 (canon-safe) | chars / systems-designer | — | CAN-06/07/10, SIM-05/11/12 |
| T-018 | UX spec v0: IA, akışlar, girdi profilleri, Türkçe metin sistemi | ux / ui-engineer | — | SIM-09/12, TEK-04, PLT-02 |
| T-027 | `SimFacadeImpl`: gerçek sim → sözleşme adaptörü | sim / simulation-engineer | T-002, T-023 | TEK-01, SIM-12 |
| T-016 | Aktör modeli + karar/gerekçe çatısı | actors / simulation-engineer | T-002, T-023, T-015 | SIM-02, SIM-05, SIM-12 |
| T-017 | Siyasi aktörler v0: ≥2 grup tepkisi + küçük meclis + medya tonu | actors / simulation-engineer | T-016, T-013 | CAN-06, SIM-05 |
| T-026 | NPC/karakter profil verisi + olay/diyalog iskeleti (yer tutucu içerik) | actors / simulation-engineer | T-015, T-023 | CAN-07, SIM-11 |
| T-013 | Ekonomi çekirdeği v0: parsel/mülkiyet/imar, hane, yatırımcı kararı (gerekçeli) | sim / simulation-engineer (+systems-designer spec) | T-002, T-023 | SIM-01..03, SIM-07, CAN-03 |
| T-014 | Belediye bütçesi + altyapı kapasitesi v0 | sim / simulation-engineer | T-013 | CAN-06, SIM-04 |
| T-011 | Yol/parsel/blok veri modeli (`WorldNetwork`) | world / world-engineer | T-001 ✓ | WLD-01, CAN-04, CAN-05 |
| T-012 | Yapı MultiMesh + HLOD render | render / godot-engineer | T-004, T-011 | VIS-02..04 |
| T-019 | UI temeli: tema, ölçek, merkezi metin, platform-duyarlı yerleşim, `ui_lab` (mock facade) | ux / ui-engineer | T-018, T-023 | TEK-04, PLT-02 |
| T-020 | HUD + zaman kontrolü + parsel denetçisi | ux / ui-engineer | T-019 | SIM-08, SIM-12 |
| T-021 | Nedensellik paneli (SIM-12) | ux / ui-engineer | T-019 | SIM-12 |
| T-022 | Karar akışları: imar önerisi, meclis oylaması, bütçe | ux / ui-engineer | T-019, T-017 (mock ile başlar) | CAN-05, CAN-06 |
T-001 takipleri: T-001a (render: ışık, harbor dikiş deliği), T-001b (world: ada tepeleri, iç körfez batimetrisi), T-001c (world+render: alt-hücre kıyı), T-001d (= T-025 arazi paleti).
Gerçek `WorldData` koordinatına bağlı işler yalnız: T-003, T-005, T-011, T-012; geri kalan hatlar coğrafyadan bağımsızdır (fixture/mock).

### M1 kapısı (T-006) için taşınan AÇIK kabul koşulları (commit ≠ kabul)
- T-012: K8 LOD0↔LOD1 ≤%5 (şu an %9,5); yerel evrede yapı üçgeni ≤900k (şu an ~1,27M); low-key ışık onayı (arazi V bandı); HLOD2/HLOD1 kararları; gerçek T0 verisiyle görsel kapı (VIS-04).
- T-001: yaratıcı coğrafya onayı (Q-015, kullanıcı). T-007: Windows çalıştırma + iPad zinciri cihazda (T-008). T-011: bellek (+~95 MB), üretim süresi sessiz makinede. T-009/T-010 henüz yok.
