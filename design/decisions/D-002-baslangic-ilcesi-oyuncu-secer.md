# D-002 · Başlangıç ilçesini oyuncu seçer

- Tarih: 2026-10-20 · Kaynak: kullanıcının sohbetteki kararı (Q-002 cevabı)
- Kullanıcı: "Oyuncu oyuna başlayacağı ilçeyi kendisi seçebilecek. Orven zorunlu başlangıç ilçesi değildir. İlk vertical slice veya teknik geliştirme için belirli bir ilçeyi test alanı olarak seçebilirsin. Ancak bu teknik tercih, oyuncunun başlangıç özgürlüğünü kısıtlayan bir oyun tasarımı kararına dönüşmemeli."
- Pekiştirdiği kanon: CAN-08, WLD-12 (F01, F05-A, F05-E).
- Stüdyo yorumu (teknik, kanon değil):
  - Başlangıç ilçesi veri parametresidir (`start_district_id`); kodda hiçbir ilçe sabitlenmez.
  - Geliştirme test alanı (M2 dikey dilimi): **Orven (D2)** — stüdyonun teknik seçimi: karma kullanımı ve büyüme alanı sayesinde imar → yatırım → inşaat döngüsü en net burada gözlenir (ROADMAP M2). "Test alanı" etiketi oyuncuya gösterilmez ve oyun tasarımı varsayımı değildir.
  - Koruma testi: önyükleme en az iki farklı ilçe kimliğiyle başlatılabilmeli (ikincisi kaba düzeyde olsa bile) — M2 kabul ölçütü.
  - CAN-08 gereği seçim ekranı yalnız gerçekten geliştirilmiş ilçeleri gösterir; yayın öncesinde (M7) birden çok oynanabilir ilçe bulunmalıdır.
- Kapanan soru: Q-002.
