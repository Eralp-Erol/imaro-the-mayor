# Kullanıcı kararı bekleyen sorular

Yalnızca kanondan çözülemeyen, gerçekten yaratıcı/ürün kararları. Gruplanmış tutulur; her biri için stüdyonun beklerken ne yaptığı yazılıdır. Cevaplar `design/decisions/` altına kullanıcının sözleriyle kaydedilir.

Durumlar:
- **open** — çözülmemiş tasarım kararı; izlenir ama hiçbir görevi engellemez (stüdyo yapılandırılabilir/geri alınabilir biçimde ilerler).
- **blocked** — en az bir görevi durduruyor; `Engellediği` satırında görev kimlikleri yazılır.
- **answered → D-NNN** — kullanıcı karar verdi.

| Q | Konu | Durum | Engellediği |
|---|---|---|---|
| Q-001 | Eski POC referans görselleri | answered → D-001 | — |
| Q-002 | Başlangıç ilçesi | answered → D-002 | — |
| Q-003 | Anderva para birimi | **open** | — (engellemiyor) |
| Q-004 | Platform önceliği | answered → D-003 (+ D-004) | — |

### Q-001 · Eski 8 POC referans görselinin statüsü  (status: answered → D-001)
- Kullanıcı eski POC'yi referans görselleriyle birlikte sildi; kullanılmaz.

### Q-002 · İlk geliştirilecek (dikey dilim) ilçe  (status: answered → D-002)
- Oyuncu başlangıç ilçesini kendisi seçer; Orven zorunlu değil. Stüdyo, M2 için teknik test alanı seçebilir (Orven/D2) ama bu oyun tasarımı varsayımına dönüşmez.

### Q-003 · Anderva'nın para birimi  (status: open — engellemiyor; kullanıcı 2026-10-20'de bilinçli olarak AÇIK bıraktı)
- Kullanıcı: "Anderva'nın para birimi henüz kararlaştırılmadı. Bu konu OPEN kalacak. Gerekli sistemlerde yapılandırılabilir parametreler kullan; para birimi adı veya sembolü hakkında kanon oluşturma."
- Studio kuralı: para birimi adı/simgesi yalnız yapılandırmadan okunur (`economy.currency_name`, `economy.currency_symbol`); geçici gösterim nötr `¤` simgesidir; hiçbir belge, test veya UI metni ₺ ya da başka bir adı kanon gibi kullanmaz. Simülasyon tutarları birimsiz tamsayıdır.
- Arayüz dili: bu soruda cevaplanmadı; çalışma varsayımı Türkçe varsayılan arayüz, tüm metinler merkezi (ÇM). Şimdilik yeniden sorulmuyor.

### Q-004 · Hedef platform önceliği  (status: answered → D-003, cihaz bilgisi D-004)
- Masaüstü (Windows + macOS) birincil, iPadOS ikincil ama ilk günden mimaride. Uygulama: ADR-0004.
