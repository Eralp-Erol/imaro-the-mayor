# 2026-11-01 · QA: doğal meclis RED + yıkım tepkisi (D2 dışı, 2 tohum) + yol zinciri · GERÇEK Ismeral, başsız

Bağımsız doğrulama; oyun/sim kodu, `data/` ve kanon DEĞİŞMEDİ. Yeni: 3 probe (`tests/sim/perf/qa_*.gd`), 3 hata kaydı (`production/bugs/B-006..B-008`), ham çıktılar (`production/log/2026-11-01-qa-ham/`).
Dal `worktree-agent-a056f505a9cb85b7f` (taban: `agent/handover-imaro-m01-349562fb` @ 3fdecb6, ff). Donanım: macOS, Intel (perf ölçülmedi). Başsız = ekran görüntüsü YOK; panel sınaması gerçek `CouncilPanel`/`ReasonPanel`/`AgendaPanel` düğümlerinin metnidir, piksel değil.

## 1. Doğal meclis RED (D2) ve `vote["why"]`

**Üretildi.** Kurulum: gerçek Ismeral D2, dünya tohumu 1467, oyunun siyaset/ekonomi yapılandırması, 108 m yol + yola en yakın 12 boş parsel, üye duruşları DEĞİŞTİRİLMEDİ (`--hostile` yok).

| Senaryo (sim tohumu) | Sonuç | Gün (plandan) | Parsel durumu |
|---|---|---|---|
| imar `zone.green`, yol 0 (1467) | **RED 2-3** | 11 | 12/12 `plan_rejected` |
| aynı, tekrar (1467) | RED 2-3, `why` ve durum özeti bit-bit aynı | 11 | 12/12 |
| `zone.green`, yol 1 (1467) | RED 2-3 | 11 | 12/12 |
| `zone.green`, yol 0 (3) | RED 2-3 | 11 | 12/12 |
| `zone.green`, yol 0 (2) | kabul 3-2 | 11 | 12 `proposed` |
| `zone.mixed` / `residential` / `commercial` (1467) | kabul 3-2 / 5-0 / 4-1 | 11 | `proposed` |

Ret koşulu: D2 altyapı doluluğu binde 998 (her üyeden -99, 5/5 aleyhe) + yeşil imarın kesim baskısı negatif (-29; karma +64) + oy gürültüsü; duruş uyumu (+597) tek başına yetmiyor. Sınırda: aynı teklif tohum 2'de geçiyor (oy gürültüsü). `zone.green` oyunun demo varsayılan imarıdır (`playable.gd` `--demo-zone`), yani doğal bir oyuncu seçimi.

`why` doğrulaması (probe bağımsız yeniden hesaplar; RED örneği `green_r0`, 102 kontrol, 100 geçti, 2 başarısız = B-006):
- Σ `net` = Σ üye gerekçe skoru (tam eşitlik); etken başına `net`/`for`/`against` üye kayıtlarından yeniden hesapla aynı; sıra |net| azalan; kayıtlı her aktif etken listede; `members` = 5 = koltuk.
- RED: hayır 3 = pozisyonlardan 3; 12 parselin tümü `plan_rejected`; `vote_failed` ve `plan_rejected` olayı birer kez.
- `infra_region` D2, `infra_load_pm` 998 = çözülme günü D2 yükü. `SimSnapshot.council` görünümü kayıtla birebir.
- Panel (`CouncilPanel`, gerçek sim): "Reddedildi", "Evet 2 · Hayır 3 · Çekimser 0", "Hayıra çeken etkenler: Uygulanabilirlik (altyapı yükü) 5 üye aleyhine, 0 lehine; Temsil ettiği kesimlerin beklentisi 3/2; Rastlantı payı 3/2", "Evete çeken: Üyenin duruşuyla uyum 0/5; Başkana güven 1/1", "En yüklü bölge D2: altyapı doluluğu binde 998". Ham anahtar yok, yasak sözcük yok, eksik metin anahtarı yok, `refresh()` kararlı. Olay metinleri ve reddedilen parsel durumu ("Teklif reddedildi (gün 42)...") Türkçe.
- 200 gün sonra: 5 üye gerekçesi budanmış (0/5), panel `why`yi hâlâ gösteriyor ve "Oylamanın gerekçeleri" düğmesini dürüstçe gizliyor.
- **HATA B-006:** "Oylamanın gerekçeleri" ReasonPanel'inde 5 satırın 5'inde ham `decision.council.vote` görünüyor (ayrıntıda da).
- UYARI (hata değil): "Rastlantı payı" (oy gürültüsü) neden olarak listeleniyor; dürüst ama oyuncuya "neden"in parçası gibi okunabilir.

## 2. Yıkım/kamulaştırma tepkisi · D2 dışı, iki dünya tohumu (1467, 2026)

**Önemli kısıt:** oyunun verisinde yol yetki alanı yalnız D2 (`data/world/ismeral/network.json` `jurisdiction_regions ["D2"]`); D1/D3/D6'da yol çizilemez (`outside_jurisdiction`, 60/60 aday reddedildi). Bu yüzden D2 dışı bölgeler "yetki alanı kaldırıldı" NE-OLUR koşusudur (CAN-08, başlangıç bölgesini oyuncu seçer). Oyunun gerçek kuralıyla D2 sınırında komşu bölge parseli alan yol aranadı: 416 geçerli D2 yolunda (iki tohum) 0 çok bölgeli yol.
Gerçek köprü (`PlayableExpropriation.attach_port`), 100 gün, yol komutları `expropriate: true`.

| Tohum / bölge | Geçerli yol (örnek) | 0 hane | 1-4 hane | >= 5 hane | En büyük yol | Sonuç |
|---|---|---|---|---|---|---|
| 1467 D1 | 95 | 9 | 2 | 84 | 136 hane | 5+ hane: 1 PE-01 (+5 gün) |
| 1467 D6 | 97 | 6 | 0 | 91 | 138 | aynı |
| 1467 D3 | 103 | 51 | 10 | 42 | 86 | aynı |
| 2026 D1 | 99 | 6 | 3 | 90 | 130 | aynı |
| 2026 D6 | 97 | 1 | 1 | 95 | 162 | aynı |
| 2026 D3 | 99 | 39 | 10 | 50 | 70 | aynı |
| (oyun kuralı) 1467 D2 | 213 | 64 | 44 | 105 | 84 | aynı |
| (oyun kuralı) 2026 D2 | 203 | 68 | 34 | 101 | 78 | aynı |

- 5 hane ve üstü her koşuda tam 1 PE-01, yol +5 günde, öğe bölgesi = yerinden edilen bölge, neden kaydındaki hane sayısı = defter = yol kaydı = `housed_hh` düşüşü, `AgendaPanel` "Yol yüzünden N hane yerinden edildi." (öğe açıkken). 0 hane (bina yıkan ticaret yolları dahil): PE-01 0, tepki 0 (doğru sessizlik).
- **Sessiz hane (B-007):** 1-4 hane yerinden eden yol PE-01 AÇMIYOR. 1-3 tasarım gereği; ama belge "20 pm = 4 hane" diyor ve tam 4 haneli yol dört hafta fazında (yol günü % 7 = 2, 5, 6, 0) ve iki tohumda da sessiz: etkin eşik 5. Gerçek D2'de hane yerinden eden yolların ~%25-30'u sessiz (44/149, 34/135).
- `group.reacted` (kesim tepkisi) tüm koşularda 0: D1/D6'da 130-162 hane yerinden edilse de bölge ölçekli kesim tepkisi yok; tepki yalnız gündemdedir (PE-01, bazı koşularda PE-04 medya; PE-04 tohum 1467'de büyük koşuların hepsinde, tohum 2026'da hiçbirinde: tohuma bağlı, nedeni araştırılmadı).
- Hata/çökme: yok (tüm koşularda motor `ERROR`/`SCRIPT ERROR` satırı 0; her senaryo sonunda yol geri alınınca ağ özeti tabana döndü, `net_restored` hep true).
- Determinizm yalnız meclis senaryosunda karşılaştırıldı (aynı senaryo iki kez: `why`, sayım ve durum özeti aynı). Yıkım koşularının `fingerprint`i ham çıktıda kayıtlı ama iki koşu karşılaştırılmadı.

## 3. Art arda iki yol (zincir)

A yolu (14 hane), B yolu A'nın UCUNDAN başlar (gerçek yol zinciri). İkisi de 1467 ve 2026, D2 (oyun kuralı) ve D1 (ne-olur); B, A'dan 1 gün ve 14 gün sonra.
Doğru çalışan: ikisi de kabul, ortak parsel 0 (`taken_registry` = A+B toplamı), her yol için `housed_hh` düşüşü = kendi yerinden edilen haneleri, defter satırları komut başına, komut başına tam 1 PE-01, B'nin nedeni A'yı suçlamıyor (`cause_refs`), LIFO geri alma (önce B, ağ özeti "A sonrası"na döner, sonra A, ağ özeti tabana döner, `taken` 0), tepki defteri ve gündem geri almadan sonra duruyor (D-011).
- **HATA B-008:** B'nin PE-01'i yol +26 (aralık 14) / +39 (aralık 1) günde açılıyor; her iki aralıkta aynı tick'te (70; A'nın öğesi tick 35'te açıldı) (mutex/bekleme: A'nın öğesi kapanana dek ikinci açılamaz). Tohum 1467 D1 aralık 1'de sıra TERS (B'nin öğesi +4, A'nın +40). Kayıp yok, gecikme var.
- Test edilmedi: 3+ yol zinciri (5 haneli üçüncü yolun sessiz kalma riski B-008'de varsayım), A ve B'nin aynı tick'te gönderimi (arayüz zaten A uygulanmadan B'nin başlangıç düğümünü vermez), görünüm tarafı `PlayableExpropriation` (parsel gizleme zinciri; pencereli/ayrı test).

## Doğrulanmış / varsayılan / test edilmemiş

**Doğrulanmış (çalıştırıldı):** yukarıdaki tüm tablolar; probe çıkışları `production/log/2026-11-01-qa-ham/`. `tools/verify.sh quick` PASS (102/257 suite, 1067 test, 0 hata; KISMİ doğrulama, `tests/ui` `tests/game` `tests/view` `tests/world` atlandı). gdlint temiz (3 yeni dosya).
**Varsayılan:** B-007 kök nedeni (kod okuma, sıralama koduna bakılmadı); B-008 kök nedeni (PE-01 mutex/öğe ömrü kod+veri okuması); `media.coverage`/`interest.lobby`/`remote.policy_move` için metin eksikliği (statik, gözlenmedi); D2 dışı bölgeler oyunda ulaşılamaz (yetki alanı) olduğundan o sonuçlar ne-olur.
**Test edilmedi:** gerçek viewport/ekran görüntüsü, dokunmatik düzen, insan hissi; 400 günlük ufuk (100 gün koştu; önceki rapor D2'de 400 gün); sim tohumu çeşitliliği yalnız meclis RED için (1467/2/3); çok bölgeli yol (0 örnek); SimBuildingProjector bağlı koşu (projector sim durumunu değiştirmez, takılmadı); perf (kapsam dışı).
Not: `council_8_senaryo_s1467.out` ve `react_1467_all_zincirli_eski_panel_kontrolu.out` probun ilk sürümüyle alındı (hatalı iki kontrol: gerekçe listesi etiket beklentisi ve panelin süresi dolmuş öğede okunması; ikisi de probe hatasıydı ve düzeltildi, `QA_FAIL` satırları o dosyalarda oyun hatası DEĞİL). Düzeltilmiş sürümle: `council_green_r0.out`, `react_1467_all.out`, `react_2026_all.out`, `react_*_d2game.out`.

## Komutlar
```
IMARO_GODOT=<Godot> tools/godot.sh --headless --path . --script res://tests/sim/perf/qa_council_reject_probe.gd -- [--only=green_r0] [--world-seed=N]
IMARO_GODOT=<Godot> tools/godot.sh --headless --path . --script res://tests/sim/perf/qa_reaction_regions_probe.gd -- [--world-seed=N] [--regions=D1,D6,D3 | --jurisdiction=game --regions=D2 --pool=250] [--days=100] [--only=chain|hh4_phaseA|...] [--no-chain]
```
Çıkış kodu 1 = en az bir `QA_FAIL` (bugünkü beklenen: council `--only=green_r0` 2 başarısız = B-006; reaction D2 koşusu 6 = B-007 x4 + B-008 x2). Süre: dünya kurulumu ~85-90 sn/tohum (ölçüldü); senaryo başına ek süre ölçülmedi (dakikalar).
