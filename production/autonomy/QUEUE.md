# Otonom görev kuyruğu (tek doğruluk kaynağı; oturumlar günceller)

Protokol: `production/autonomy/RUN-PROTOCOL.md` · Sözleşme: `production/M2-CONTRACT.md`. Durumlar: ready · in-progress · done · blocked.
"Deneme": başarısız/yarım bırakılan tur sayısı (3'te `blocked`).

| ID | Görev | Bağımlılık | Durum | Deneme | Not |
|---|---|---|---|---|---|
| T-040 | İlk nedensel döngü: imar → yatırımcı → inşaat → gerçek 3D yapı → ölçülebilir sonuç | — | **done** (2026-10-24) | 0 | QA tur 3 PASS · kapanış smoke SMOKE_OK (ort 6,86 / P95 13,01 ms) · açık kayıtlar: `production/tasks/T-040.md` KAPANIŞ |
| T-047 | **GÖRÜNÜR OYUN 1/4** Dürüst arayüz + çalışan işlevler | T-040 | **done** (2026-10-25) | 0 | koordinatör doğrulaması (ui 262 / game 49, gerçek yakalamalar); açık: 480 px düzeni (T-046), Q-017 yıkım/yeniden yapılaşma kararı |
| T-048 | **GÖRÜNÜR OYUN 2/4** Yolların çizimi (ağ verisi dünyada görünür) | T-047 | **done** (9ad8a5f + perf 12c0831/e7bad29) | 0 | yol kurulumu ~2,2 s; bağımsız smoke SMOKE_OK (ort 7,62 / P95 16,43 ms, 219 dc); AÇIK: art-director kapısı; `production/tasks/T-048.md` |
| T-049 | **GÖRÜNÜR OYUN 3/4** Arazi + şehir görünümü (piksel zemin, daire damgası) | T-048 | **done-with-open** (A eece1ac, A2 a9a82e8, A3 2d6a437, B 7cab448) | 0 | D6 çekirdeği hâlâ nispeten kare, D2–D5 A2 uygulanmadı; art-director kapısı açık; `production/tasks/T-049.md` |
| T-051 | **GÖRÜNÜR OYUN 5** Bina karakteri: Kit v1 (kiremit/dönem/kütle/cephe ritmi/yeşillik) | T-049 | **DURDU** (kullanıcı reddi 2026-10-25: kutu kiti referansa benzemiyor); kent zemini 9d149b8 kalır; kit üretimi T-053 sonucuna göre yeniden planlanır | 0 | spec: `design/specs/art/building-kit-v1.md` (fark analizi: mevcut oyun FAIL); sıradaki: Tur 1 üretimi (technical-artist) + art-director kapısı C1/C2/C4; `production/tasks/T-051.md` |
| T-052 | **TEMEL** Varlık kütüphanesi (design system) + kullanıcı ONAY kapısı | T-051 spec | in-progress (2026-10-25, kullanıcı kararı) | 0 | insan/araç/yol kesiti/bitki şablonları ÖNCE çizilir, kullanıcı onaylar; onaysız varlık dünyada görünmez. T-050 ve T-042 BU ONAYA BAĞLI; `production/tasks/T-052.md` |
| T-053 | **TEMEL** Kahraman bina kanıtı: dokulu cephe ile referans kalitesine ulaşılabilir mi (tek bina) | T-052 | in-progress (2026-10-25) | 0 | kullanıcı 2026-10-25: mevcut kit (46 varlık) REFERANSA BENZEMİYOR, hepsini reddetti. T-051 kalan kit üretimi DURDU; kullanıcı kahraman binayı onaylamadan ikinci bina çizilmez. Çıktı: design/specs/art/hero-building/ |
| T-054 | **TEMEL** Bina ailesi hero'ları batch 1 (kütüphane; OYUNA EKLENMEZ) | T-053 | in-progress (2026-10-25, kullanıcı: "bu stil iyi base; tüm assetler hero olarak; library tamamlanmadan oyuna ekleme yok") | 0 | çarşı evi, orta/geç apartman, müstakil/yamaç, sanayi, kamu+saat kulesi; ardından insan/araç/yol kesiti/bitki/zemin/donatı hero'ları |
| T-050 | **GÖRÜNÜR OYUN 4/4** Araç ve insan: ilk yaşam belirtisi (sim verisine bağlı) | T-048 | ready | 0 | `production/tasks/T-050.md` |
| T-041 | Parsel/bölge denetçisi + nedensellik zinciri (metro/ilçe/sokak zoom) | T-040 | ready | 0 | görev dosyası: `production/tasks/T-041.md` |
| T-042 | Oyuncu yol/kamusal alan çizimi → altyapı kapasitesi → yatırımcı kararı | T-040 | ready | 0 | `production/tasks/T-042.md` |
| T-043 | Orven (D2) başlangıcı + ≥2 ilçe kimliğiyle başlatma testi | T-040 | ready | 0 | `production/tasks/T-043.md` |
| T-045 | Olay saklama ufku yük altında: değişen parselleri güvenilir sorgulama (sim) | T-040 | **done** (3244bee + projector geçişi 4e5e26e) | 0 | `production/tasks/T-045.md` |
| T-046 | macOS dokunmatik profil pencereli HUD yerleşim hatası (güvenli alan) | T-040 | ready | 0 | `production/tasks/T-046.md`; T-040 HUD turunda bulundu |
| T-044 | M2 kapı raporu (F03 eşleme, bağımsız QA özeti, açık kullanıcı/cihaz kabulleri) | T-040..T-043, T-045, T-046 | ready | 0 | `production/tasks/T-044.md` dosyası henüz yazılmadı (ilk işi: bunu yazmak) |
| M3-1 | M3 kapsamı (yaşayan metropol) için görev tanımı | T-044 | ready | 0 | ROADMAP M3: yalnız T-044 `done` olunca; ilk iş görev dosyalarını `design-director` + `technical-director` ile yazmak |

**KULLANICI KARARI (2026-10-25, KESİN):** library (tasarım sistemi) TAMAMLANMADAN oyuna varlık EKLEME aşamasına geçilmez; tüm assetler T-053 tarzı hero olarak geliştirilir. Çalışma modeli: tek ajan, sıralı (kota koruma).

**KULLANICI KARARI (2026-10-25):** hiçbir yeni nesne (insan, araç, yol kesiti, bitki, donatı) onaysız dünyaya girmez; önce T-052 kütüphanesi + onay sayfaları. T-050 ve T-042, T-052'de ilgili şablonlar onaylanmadan başlamaz.

**SIRA (2026-10-25):** T-049 (şehir formu + arazi) → T-051 (Kit v1) → T-042 genişletilmiş (oyuncu yol çizimi → yeni parsel) + doğal büyüme tasarımı (soru/spec, karar kullanıcıda) → T-050 (araç/insan); sonra T-046, T-041, T-043, T-044.

**ÖNCELİK DEĞİŞİKLİĞİ (kullanıcı, 2026-10-25):** yeni sim sistemi eklemeden ÖNCE görünür oyun (T-047→T-050); T-041…T-046 ve T-044 bu dört iş bitince sürer. Her adımda gerçek ekran görüntüsü + dar QA (varsayılan rejim).

M2 bittiğinde ROADMAP'teki bir sonraki uygulanabilir milestone (M3) için aynı düzenle görev dosyaları açılır; M4+ **AÇIK karar bağımlılıkları**
(parti/seçim/başlangıç senaryosu: F05-D) yüzünden yalnız karar gerektirmeyen veri-odaklı kısımlarıyla ilerler, kararlar kullanıcıya bırakılır.
