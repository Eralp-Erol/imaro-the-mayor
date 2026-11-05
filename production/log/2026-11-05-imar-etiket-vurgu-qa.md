# İmar listesi etiketi + harita vurgusu — pencereli QA (2026-11-05)

- B-031 (parsel etiketleri): pencereli karelerde ÇALIŞIYOR, ham numara yok (1600x900 ve 1024x768).
- B-032 (harita vurgusu): ilk turda belediye arazisi akışında halka YOKTU (H1: yıkımdan sonra parseller `net.parcels`ta değil, `_undo_stack` arşivinde). B-033 düzeltmesi sonrası yeniden çekimde 15/15 halka (masaüstü ve dokunmatik, 230-6000 m). H2 (hardal zeminde kontrast, B-034) ve H3 (kırmızı satır, B-035) gözle çözüldü; kontrast ÖLÇÜLMEDİ.
- H5 KISMEN: dokunmatik 1024x768'de "Planı sun" hiçbir senaryoda ilk ekranda değil, 3 parselde kullanım düğmeleri de ekran dışı. Bu, art-director'ün "dokunmatik HUD şehrin ~%60'ını örtüyor" bulgusuyla aynı kök: panel yeri (sağ tam boy mu, alttan çekmece mi) SAHİP ZEVK/ÜRÜN KARARI; panel yeri kararı gelmeden daha fazla sıkıştırma yapılmaz.
- Bilinen sınırlar: metro bandında halka yok; 40+ parselde fazlası çizilmez; ~2500 m'de 15 halka yumak. Haritadan tıklayarak parsel ekleme zinciri bu turda gerçek girdiyle sınanmadı (`open_zoning(ids)` çağrıldı). Fiziksel iPad denenmedi.
- Kareler: `artifacts/qa/imar-etiket-vurgu/` (önce), `imar-etiket-vurgu-2/` (sonra), yerel/takipsiz.
