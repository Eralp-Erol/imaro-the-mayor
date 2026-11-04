# Erişilebilirlik temelleri ve hata/boş/yükleme durumları v0 (T-018 ölçüt 7)

Statü: ÇALIŞMA MODELİ. Metinler `strings.tr.json` (`state.*`, `a11y.*`, `settings.*`). Eşikler ÖNERİDİR; WCAG 2.2 AA hedef alınır ve oyun için mümkün olduğunca uyarlanır; resmi uyum iddiası yok (test edilmedi).

## 1. Erişilebilirlik temelleri
| Konu | Kural |
|---|---|
| Kontrast | Metin/arka plan ≥ 4.5:1 (büyük metin ≥ 3:1); etkileşimli sınır/ikon ≥ 3:1. Dünyanın üstündeki metin yarı saydam **panel zemini** üzerinde (dünya renklerine bağımlı kontrast yok). `settings.high_contrast` ayrı tema. |
| Renk tek başına anlam taşımaz | Lehte/aleyhte, uyarı, durum: **ikon + metin + biçim** (örn. ▲/▼ + `a11y.trend_*`). `settings.colorblind_safe`: harita katmanı paletleri CVD güvenli. |
| Ölçek | `settings.ui_scale` (0.8–1.6) ve `settings.text_size` ayrı; düzen metin büyüyünce taşmaz (konteyner/sarma), kırpma yok. Türkçe metin uzun olabilir (İngilizceye göre ~%25-35 pay bırak). |
| Hareket | `settings.reduce_motion`: panel/kamera geçişleri anlık, seçim gecesi animasyonu statik, titreme yok. Yanıp sönen öğe yok (3/s sınırı). |
| Girdi | Tüm fiiller klavye ile (masaüstü) ve görünür düğmeyle (dokunmatik) yapılabilir; odak sırası mantıksal; odak halkası her zaman görünür; jest/sürükleme tek erişim değil. |
| Zaman baskısı | Oyun duraklatılabilir; hiçbir karar fare hızına bağlı değil; bildirimler kendiliğinden kaybolmaz (kapanma süresi ayarlı veya geçmişte kalır). |
| Ekran okuyucu | Godot 4.7 ekran okuyucu/AccessKit desteği platforma göre değişir; **desteklenip desteklenmediği doğrulanmadı** → hedef: Control'lerde anlamlı `tooltip_text`/erişilebilirlik adı alanları doldurulur, destek test edilince iddia edilir. |
| Metin okunabilirliği | Sayılar birimiyle ve etiketiyle; kısaltma yok (bkz. `ux-text-system.md`); tarih/sayı Türkçe biçim. |
| Dokunmatik | ≥44 pt; komşu boşluk; kaza önleyici onay (geri alınamaz eylemlerde `common.confirm`). |

## 2. Durum envanteri
Her veri-bağımlı yüzey şu dört durumu tanımlar (T-019 bileşen kontratı): **yükleme, boş, hata, kurulmamış** + normal.

| Durum | Ne zaman | Gösterim | Anahtar |
|---|---|---|---|
| Yükleme | dünya/sim hazırlanıyor, panel verisi bekleniyor | iskelet/spinner + metin; ilerleme biliniyorsa yüzde, bilinmiyorsa yüzde gösterilmez; 300 ms'den kısa beklemede gösterme (titreme önleme) | `state.loading`, `state.loading_world`, `state.loading_progress` |
| Boş | veri var ama içerik yok (olay yok, seçim yok, gerekçe yok) | tek cümle + (varsa) sonraki adım | `state.empty.*`, `inspector.nothing_selected` |
| Hata (kurtarılabilir) | komut reddedildi, sim yanıtı yok, eski veri | ne oldu + **neden (sim gerekçesi varsa)** + ne yapılabilir (`common.retry`) | `state.error.command_rejected`, `state.error.sim_unavailable`, `state.error.stale_data` |
| Hata (kritik) | kayıt başarısız, sim çöktü | L5 diyalog: açıkla, kaydı korumayı dene | `state.error.save_failed`, `state.error.generic` |
| Kurulmamış | sistem henüz yok (meclis/bütçe/seçim) | **ya gizle ya dürüstçe etiketle**; sahte sekme, sahte sayı yok | `state.not_built`, `*.not_built` |
| Devre dışı | koşul sağlanmıyor (ölçek, bütçe, yetki) | düğme **neden** yanında/altında yazar; yalnız soluk renk yok | `state.disabled_reason`, `zoom.locked_here` |
| MOCK | gerçek sim bağlı değil | sabit rozet/banner (bkz. ux-layout §4) | `app.mock_*` |

## 3. Hata metni kuralları
- Sorumluluğu oyuncuya yüklemez; ne olduğunu, nedenini ve sonraki adımı söyler. Kodlar/yığın izi oyuncuya gösterilmez (günlüğe gider).
- Sim'in `ReasonRecord`'u varsa metin onu kullanır (SIM-12); UI neden **uydurmaz**.
- Ağ yok (oyun çevrimdışı); ağ hatası mesajı yok.

## 4. Yaşam döngüsü (iPad)
Uygulama arka plana gidince oyun otomatik duraklar ve yarım çizim taslağı korunur; geri dönüşte `menu.pause_title` değil, kaldığı yerde "Sürdür" (öneri; AÇIK SORU 6 ile ilişkili). Klavye açıldığında (ad girişi vb.) panel yukarı kayar, odaklı alan görünür kalır. **Doğrulanmadı** (cihaz yok).
