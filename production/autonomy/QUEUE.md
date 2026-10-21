# Otonom görev kuyruğu (tek doğruluk kaynağı; oturumlar günceller)

Protokol: `production/autonomy/RUN-PROTOCOL.md` · Sözleşme: `production/M2-CONTRACT.md`. Durumlar: ready · in-progress · done · blocked.
"Deneme": başarısız/yarım bırakılan tur sayısı (3'te `blocked`).

| ID | Görev | Bağımlılık | Durum | Deneme | Not |
|---|---|---|---|---|---|
| T-040 | İlk nedensel döngü: imar → yatırımcı → inşaat → gerçek 3D yapı → ölçülebilir sonuç | — | in-progress | 0 | sim ✓ `cc5bfbb` · render ✓ `93e5bc3` · HUD ✓ (commit'lenecek) · bağımsız QA sırada |
| T-041 | Parsel/bölge denetçisi + nedensellik zinciri (metro/ilçe/sokak zoom) | T-040 | ready | 0 | görev dosyası: `production/tasks/T-041.md` |
| T-042 | Oyuncu yol/kamusal alan çizimi → altyapı kapasitesi → yatırımcı kararı | T-040 | ready | 0 | `production/tasks/T-042.md` |
| T-043 | Orven (D2) başlangıcı + ≥2 ilçe kimliğiyle başlatma testi | T-040 | ready | 0 | `production/tasks/T-043.md` |
| T-045 | Olay saklama ufku yük altında: değişen parselleri güvenilir sorgulama (sim) | T-040 | ready | 0 | `production/tasks/T-045.md`; T-040 projector geçici çözümünü kalıcıya çevirir |
| T-046 | macOS dokunmatik profil pencereli HUD yerleşim hatası (güvenli alan) | T-040 | ready | 0 | `production/tasks/T-046.md`; T-040 HUD turunda bulundu |
| T-044 | M2 kapı raporu (F03 eşleme, bağımsız QA özeti, açık kullanıcı/cihaz kabulleri) | T-040..T-043, T-045, T-046 | ready | 0 | `production/tasks/T-044.md` dosyası henüz yazılmadı (ilk işi: bunu yazmak) |
| M3-1 | M3 kapsamı (yaşayan metropol) için görev tanımı | T-044 | ready | 0 | ROADMAP M3: yalnız T-044 `done` olunca; ilk iş görev dosyalarını `design-director` + `technical-director` ile yazmak |

M2 bittiğinde ROADMAP'teki bir sonraki uygulanabilir milestone (M3) için aynı düzenle görev dosyaları açılır; M4+ **AÇIK karar bağımlılıkları**
(parti/seçim/başlangıç senaryosu: F05-D) yüzünden yalnız karar gerektirmeyen veri-odaklı kısımlarıyla ilerler, kararlar kullanıcıya bırakılır.
