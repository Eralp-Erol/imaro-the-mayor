Imaro kütüphane pipeline'ını Codex'ten devral. Bu mesaj T-057 çalışmasını devralıp sürdürmen için açık devam talimatımdır. Önemli bir aşama tamamlandığında safe pause yap.

Doğru çalışma dizini:
/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb
Dal: agent/handover-imaro-m01-349562fb
Son çalışma WIP commit'i: 1c9c3c0; bunun ardından yalnız devir belgeleri commit'lendi. Ana imaro-the-mayor checkout'u eski dev/m1-parallel dalında; orada çalışma.

Önce sırayla oku:
1. CLAUDE.md
2. production/STATE.md
3. docs/agent-handoff/T057_CODEX_TO_CLAUDE_2026-10-27.md
4. production/tasks/T-057.md
5. production/qa/T-057-art-review.md ve T-057-technical-review.md

T-056 tamam. T-057'de 10 bitkinin yakın modelleri korunuyor; görev tamamlanmadı. Sorun palmiye dışı uzak temsil. Üç çapraz kart, doğru kaynak normal verisi ve ortak F(P,C) alanına rağmen 150m'de dikiş/panel/ton kaybı yaptı. Ayrı 36 üçgen kapalı taç deneyi teknik olarak doğru ve deterministik; fakat 150m'de ve 120m LOD1 geçişinde yapraklı çınarı koyu, dolu geometrik hacme dönüştürdü. Bağımsız sanat FAIL verdi.

experiments/t057-proxy-shell/comparison.png ve frames.json'daki 10 SON DÜZELTİLMİŞ gerçek PNG'yi aç. invalid-white-frames.json ilk import hatasına ait geçersiz görüntülerdir. Sonra normal deneyinin FPC-REPORT.md ve fpc-comparison-150m.png kanıtını incele. Teknik testlerin geçmesini sanat kabulü sayma.

40 üçgen sınırı ve 50/120m LOD mesafeleri kullanıcı kanonu değil, çalışma tercihleridir. Bunları değişmez sanıp tekrar AO/tint/normal/alpha/destek ayarı döngüsüne girme. Teknik yönetmenle kaynak karakterini koruyan en küçük yeni yaklaşımı seç. Öncelikle mevcut LOD1'in maliyetini ve ekran kaplamasını taban alıp kaynak yaprak kümeleri/boşluklarını koruyan ara LOD'u değerlendir. Bütçe veya LOD politikasının değişmesi gerekiyorsa bunu gerekçeli, ölçülebilir teknik karara bağla; kötü adayı yalnız uzağa iterek FAIL'i gizleme. Çok görünüşlü impostor ayrı olası yoldur, doğrulanmış çözüm değildir.

Önce tek çınar üzerinde sonlu deney ve gerçek görsel kabul; sonra diğer türler. Mevcut import audit'inin reddedilen shader'daki sabit AO/sentetik normal metnini zorunlu tuttuğunu unutma: yeni mimari için gerçek teknik sözleşmeyi güncelle, bu eski kodu test uğruna koruma. Rebuild/katalog/import/provenance da yeni yöntemle tutarlı olmalı. Yakın LOD0'ları ve bina hero'larını baştan tasarlama.

Projenin kendi game development agency harness ve skillerini kullan. Tek uzmanla sıralı çalış, aynı anda tek Godot çalıştır. STOP önceki safe pause'a ait; çalışma dizinini/commit'i ve başka aktif lock olmadığını doğruladıktan sonra bu açık devam talimatıyla kaldır, kendi kilidini al. Başka oturumun kilidini veya sürecini silme. Önceden var olan artifacts/library/ ve tmp/ içeriklerini koru.

Son 47 odaklı test geçti; T-057 final full çalışmadı. full-latest.json eski T-056 sonucudur. T-057 için QA + bağımsız sanat + final full bitmeden done deme. Bütün yeni varlıklar proposed/lab; Q-018 ve T-055 kullanıcı değerlendirmesi açık. Kütüphane tamamlanmadan ve onay olmadan oyuna ekleme; main merge/push/foundation değişikliği yapma. T-058'e geçmeden önemli aşama sonunda kanıtları/commit'i/handoff'u kaydet ve safe pause yap.
