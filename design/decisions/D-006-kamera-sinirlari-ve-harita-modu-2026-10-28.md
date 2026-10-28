# D-006 · Kamera sınırları ve ayrı harita modu

- Tarih: 2026-10-28 · Kaynak: kullanıcının sohbetteki sözleri ve soru kartı cevapları (aşağıda). Öneri: `design/specs/ux/VIEW-MODES-AND-DESIGN-SYSTEM.md`, `production/QUESTIONS.md` Q-019.
- Kullanıcının sözü (sohbet): "bu kadar zoom out yapamamalısın ya, hani böyle sanki uzaydan görünüyormuşçasına. Bu dünyayı görememelisin ya. O başka bir mod olabilir mesela."
- Karar (kullanıcının, soru kartı cevabı "Evet (Önerilen)"):
  1. **Serbest 3D kamera uzaydan görünmez.** Üst sınır yaklaşık 18 km, en yakın bakış yaklaşık 50 m (ÇALIŞMA DEĞERİ; spec'te hesaplandı, çalışan oyunda ölçülmedi). Dünyanın tamamı tek karede görünmez.
  2. **Tüm dünya / ülke görünümü ayrı bir harita modudur**; aynı dünya verisinden türer (WLD-01 korunur).
  3. **İnsan, araç, sokak donatısı ve bina yakın detayı (LOD0) işleri M2 sonrasına atılır.** Yol kesiti (T-061) kalır.
  4. **Öncelik:** karar -> görünür sonuç (yol çiz, bina çıksın, halk tepki versin); görünüm cilası bunun üstüne.
- Ajan notu (karar değil): kesin sayılar, bant eşikleri ve dosya biçimleri teknik karardır; ADR-0007 (T-063) ile belirlenir. Q-019'un geri kalanı (harita görünüşü, 3D↔harita geçiş biçimi, Anderva ölçeğinin yeri, tavan alternatifleri) kullanıcıya sorulmadı: AÇIK kalır; spec'teki öneri yalnız ÇALIŞMA MODELİ olarak kullanılır.
