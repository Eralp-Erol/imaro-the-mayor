# D-007 · Masaüstü performans eşiği (yumuşatılmış) ve performans işlerinin askıya alınması

- Tarih: 2026-10-28 · Kaynak: kullanıcının sohbetteki sözleri ve soru kartı cevabı. Veri: `production/log/2026-10-28-T-070-ucgen-dagilimi.md`, `docs/adr/ADR-0008-gorunur-ucgen-ve-kare-butcesi.md`.
- Kullanıcının sözleri (sohbet): "benim ekranda gördüğüm fena değil açıkçası"; "bence performans iyi. Yani bunu daha çok yapmaya gerek yok." Soru kartı cevabı "Evet, yaz ve geç": "masaüstü için yumuşak eşiği (ort <=14 ms, tiksiz p95 <=20 ms) resmî yaz, katı bütçe iPad hedefi olarak kalsın. Sonra T-064 kamera sınırlarına geç."
- Karar (kullanıcının):
  1. **Masaüstü kabul eşiği:** ortalama kare <= 14 ms ve simülasyon tiksiz p95 <= 20 ms (bu makinede, yük altında ölçüm). ÇALIŞMA DEĞERİ olarak resmîleşti; ölçüm koşulu T-070'teki gibi 3 koşu medyanı.
  2. **Katı bütçe (ADR-0008: ort <= 8 ms, p95 <= 16,6 ms, <= 900k üçgen, <= 400 draw call) iPad / hedef cihaz sınıfı hedefi olarak kalır;** iPad ölçümü gelene kadar zorunlu kapı değildir.
  3. **Performans düzeltmeleri (T-071 bina kademe seçimi, T-072, T-074) iPad ölçümüne / yumuşak eşiğin aşıldığı ana kadar askıdadır.**
  4. **Sıradaki iş:** T-064 kamera sınırları (ADR-0007, D-006).
- Ajan notu (karar değil): T-070 çekirdekte yumuşak eşiği geçiyor (ort 11,2 ms; tiksiz p95 13,3 ms; makine yük altında); iPad, GPU süresi ve hareketli kamera taraması ölçülmedi.
