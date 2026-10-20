# D-004 · iPad test cihazı mevcut; iPad'de erken duman testi; renderer sabit değil

- Tarih: 2026-10-20 · Kaynak: kullanıcının sohbetteki kararı
- Kullanıcı: "Elimde M serisi çipli bir iPad Pro var. Ayrıca Apple Developer hesabım da mevcut. … Desktop-primary / iPadOS-secondary kararı aynen korunacak. iPad üzerinde gerçek testleri M2 sonuna kadar tamamen ertelemeyelim. İlk anlamlı grafik ve input prototipinden itibaren erken smoke test planla. … GL Compatibility renderer'ını bütün platformlar için değişmez karar olarak görme. Gerekirse platforma uygun renderer ve kalite profillerini karşılaştır. Bunlar T-001'i gereksiz yere bloke etmemeli."
- Düzelttiği: ADR-0004'teki "iPad yok" varsayımı; ROADMAP'te iPad testinin M2 sonuna bırakılması; ADR-0001'deki Compatibility'nin her platform için varsayılan sayılması.
- Uygulama: T-007 iOS export zincirini cihazda boş sahneyle dener; T-008 (iPad duman testi) M1'e, ilk grafik + girdi prototipinin (T-003) hemen ardına taşındı; T-010 renderer/kalite profili karşılaştırması (macOS Intel, iPad M serisi Metal; Windows cihaz gelince). Hiçbiri T-001'i bloklamaz.
- D-003 (masaüstü birincil, iPadOS ikincil) aynen geçerlidir.
