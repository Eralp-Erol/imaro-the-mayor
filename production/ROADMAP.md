# Yol haritası

Kaynak: foundation F03 "Oyun hissi için doğrulanması gereken kabul ölçütleri" ve F01 sütunları. Milestone'lar dikey dilimdir: her biri gerçek 3D dünyada gözlemlenebilir bir sonuçla biter. Sayılar/takvim çalışma tahminidir; AÇIK kararlara bağlı milestone'lar işaretlidir.

| M | Ad | Amaç (çıkış ölçütü özeti) | Ana REQ | Karar bağımlılığı |
|---|---|---|---|---|
| M0 | Stüdyo kurulumu | Harness, araçlar, kapılar, ADR'lar, doğrulanmış iş akışı | TEK-* | — (tamam, bkz. `docs/STUDIO.md`) |
| M1 | Tek dünya iskeleti | Ismeral'in arazi/kıyı/körfez/ova/yamaç ve D1–D6 bölge verisi tek koordinat sisteminde; metro ve ilçe ölçeğinde aynı veriden render; T0 yerleşim yoğunluğu kaba düzeyde (D1+D6 çekirdek, diğerleri küçük merkezler, liman ana karada); kamera metro↔sokak kesintisiz; sim çekirdeği iskeleti (tick, durum, RNG, kayıt, determinizm testleri); dünya-kanon testleri. Görsel kapı: "boş grid üzerinde 4 blok" değil, yaşayan körfez kenti silueti. | WLD-01..05, WLD-08, TEK-01..03, VIS-01, VIS-04 | Q-004 (bütçe) — geri alınabilir varsayımla ilerler |
| M2 | İlk nedensel döngü (dikey dilim) | Seçilen ilçede sokak ölçeği; oyuncu yol/kamusal alan çizer ve imar değiştirir → yatırımcı kendi koşullarıyla karar verir (gerekçeli; olumlu + olumsuz senaryo) → inşaat zamanla ilerler → hane/işyeri, bütçe, ≥2 grup tepkisi + küçük meclis → oyuncu aynı alanı farklı zoom'larda inceler. F03 kabul ölçütlerinin tamamı. | CAN-03..06, SIM-01..05, SIM-07..09, SIM-12, WLD-01, WLD-12, VIS-02..03 | **Q-002 (ilçe)**, Q-003 (para/dil) |
| M3 | Yaşayan metropol | Diğer ilçeler oyuncu bakmıyorken evrilir (toplu model); makro koşullar; ulaşım/trafik sorunu ve hava (yağmur) görünür; altyapı kapasite/bakım maliyeti; farklı politikalarla ayrışan şehirler (SIM-10). Ortam sesi başlangıcı. | WLD-11, SIM-04, SIM-06, SIM-10, SIM-11 | — |
| M4 | Siyasi kariyer katmanı | Seçim, itibar, medya, çıkar grupları, kaybetme sonucu; kampanya akışı ilçe dönemi. | CAN-07, CAN-10 | **Parti/seçim/başlangıç senaryosu kararları (F05-D)** |
| M5 | Metropol yönetimi | Aynı karakter metropol başkanlığına yükselir; ilçeler arası projeler, alt belediyeler paydaş; dünya sıfırlanmaz. | CAN-07, CAN-11, WLD-09 | Yetki modeli (F05-D) |
| M6 | Ulusal mücadele ve final | Anderva ölçeği (aynı dünya), diğer metropoller soyut; cumhurbaşkanlığı seçim zaferi finali. | CAN-07, CAN-09, WLD-10 | Diğer metropol adları/karakterler (F05-D) |
| M7 | Üretim cilası ve yayın | İçerik genişletme (ek ilçeler — Orven'in fiilî zorunlu başlangıç olmaması için ≥2 oynanabilir ilçe), ses, anlatı içeriği, performans, platform export ve cihaz testleri, yayın. | CAN-08, TEK-04, TEK-05 | Q-004, monetizasyon (F05-D) |

## Önerilen ilk üretim dikey dilimi
**M1 + M2 = "Tek dünya, tek ilçe, ilk nedensel döngü."** Ismeral'i bütün olarak kaba ama doğru coğrafyayla kurar, sonra bir ilçede imar → yatırım → inşaat → ekonomi → siyasi tepki zincirini gerçek 3D dünyada kanıtlar. Bu, foundation'ın "oyunun ana vaadini gösterme" şartını (F06) ve F03 kabul ölçütlerini en küçük kapsamda karşılar.

## M1 görevleri
| ID | Başlık | Sahip | Bağımlı | Paralel |
|---|---|---|---|---|
| T-001 | Ismeral dünya verisi iskeleti + metro ölçeğinde render + dünya-kanon testleri | world-engineer (+ godot-engineer render) | — | A |
| T-002 | Sim çekirdeği iskeleti: tick sürücüsü, GameState, RNG akışları, komut kuyruğu, kayıt/yükleme, determinizm testleri | simulation-engineer | — | A |
| T-003 | Çok ölçekli kamera rig'i (metro↔sokak, dokunmatik + fare), origin rebasing, standart capture preset'leri | godot-engineer | T-001 | B |
| T-004 | Low-poly yapı kiti v0 (3–4 dönem apartman, zemin kat dükkân, depo/sanayi, sivil yapı) + HLOD proxy'leri | technical-artist | art spec (art-director) | B |
| T-005 | T0 yerleşim üreteci v0: bölgelere göre yoğunluk/kullanım, D1+D6 çekirdek, ana kara limanı/sanayi | world-engineer | T-001, T-004 | C |
| T-006 | M1 görsel ve mimari kapı: metro/ilçe/sokak capture'ları, art-director + design-director + technical-director incelemesi | qa-engineer + directors | T-003, T-005 | — |
