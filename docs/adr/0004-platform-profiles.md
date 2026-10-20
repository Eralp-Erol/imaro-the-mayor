# ADR-0004 · Platform profilleri: masaüstü birincil, iPadOS ikincil

- Durum: kabul · Tarih: 2026-10-20 · Karar veren: kullanıcı (platform stratejisi, D-003), technical-director (teknik uygulama)
- Karşıladığı gereksinimler: PLT-01..06, TEK-01..05, D-002 (başlangıç ilçesi verisi), D-004 (iPad cihazı, erken test, renderer profilleri)
- ADR-0001'i günceller: renderer ve bütçe bölümleri bu ADR'deki profillere göre okunur.

## Bağlam
D-003: Windows + macOS birincil, iPadOS ikincil ama ilk günden mimaride; simülasyon derinliği iPad'e göre kısılmaz; tek simülasyon çekirdeği + ortak dünya verisi; platforma özgü kontrol/UI/grafik profilleri serbest; performans ölçümle değerlendirilir; eşit kapasite varsayılmaz. Mevcut mimari (ADR-0001/0002) iPad'i birincil hedef sayan, dokunmatik öncelikli bir varsayımla yazılmıştı.

## Mevcut mimariyle karşılaştırma
| Konu | ADR-0001/0002 durumu | D-003 ile uyum | Değişiklik |
|---|---|---|---|
| Tek sim çekirdeği, ortak dünya verisi | Saf `src/sim` + `src/world`, render/input'tan ayrı | ✅ birebir | Yok |
| Motor (Godot 4.7.2) | Windows, macOS, iOS export'u destekler | ✅ | Export şablonları **kurulu değil** → T-007 |
| Renderer | Compatibility her yerde | ✅ temel olarak | Masaüstü "yüksek" grafik profili Mobile/Forward+ ile ölçülerek değerlendirilir (aşağıda) |
| Girdi/UX | "Dokunmatik öncelikli" | ⚠️ değişti | Masaüstü (fare/klavye/trackpad) birincil; iPad dokunmatik profili ikincil ama ilk günden |
| Performans bütçesi | Düşük güçlü GPU / iPad varsayımı | ⚠️ değişti | Masaüstü referans bütçesi; iPad bütçesi cihaz ölçümünden sonra; sim kapsamı bütçeye göre kısılmaz |

## Açıkça raporlanan teknik gerilimler
1. **"Derinlik iPad'e göre kısılmaz" + "tek çekirdek" + "eşit kapasite varsayılmaz".** Simülasyon LOD'u (ADR-0002 §3, açık/toplu model yarıçapı) platforma göre değişirse aynı karar farklı sonuç verir ve masaüstü kaydı iPad'de aynı şehir olmaz. **Karar:** simülasyon sonuçları platformdan bağımsızdır; sim LOD'u oyun durumunun parçasıdır, platform profili değildir. Platformlar yalnız şunlarda ayrışır: render LOD/görüş mesafesi, grafik kalitesi, UI/girdi, en yüksek oyun hızı ve tick'in karelere bölünmesi. iPad ölçümleri tam kapsamı taşıyamazsa bu **kapasite farkı** olarak ölçümlerle size getirilir; sessizce iPad için ayrı/kısıtlı bir simülasyon yapılmaz, masaüstü asla kısılmaz.
2. **Platformlar arası determinizm (x86-64 ↔ ARM64).** Windows ve Intel Mac x86-64; iPad ve Apple Silicon Mac ARM64. IEEE-754 temel işlemler (+, −, ×, ÷, `sqrt`) tutarlıdır ama `sin/cos/exp/log/pow` gibi transandantal fonksiyonlar platform matematik kütüphanesine göre son bitte farklılaşabilir. Kayıt/tekrar oynatma ve ileride çok oyunculu olmayan ama platformlar arası paylaşılan kayıtlar için risk. **Önlem:** kalıcı sim durumu tamsayı/sabit nokta (zaten kural); karar eşiklerine giren transandantal sonuçlar sabit hassasiyete yuvarlanır veya kendi tablo/polinom uygulamamız kullanılır; **çapraz platform tekrar oynatma testi** (aynı senaryo → aynı `StateHash`) bir kalite kapısıdır (T-009).
3. **Cihazlar (D-004 ile güncellendi).** Var: 2019 Intel MacBook Pro (geliştirme + macOS referansı), **iPad Pro (M serisi) + Apple Developer hesabı**. Yok: Windows test cihazı (bu Mac'te Boot Camp ya da ayrı PC gerekir), Apple Silicon Mac (macOS'ta Metal yolu doğrulanamaz). Cihazı olmayan platform "derlendi, çalıştırılmadı" diye raporlanır.
4. **iPadOS derleme zinciri bu Intel Mac'te (2026-10-20 değerlendirmesi).** Kurulu: Xcode 26.3 (17C529), iOS SDK 26.2, iOS 26.3 simülatör çalışma zamanı, 1 geliştirme imza kimliği, 12 provisioning profili. Eksik/denenmemiş: Godot 4.7.2 iOS export şablonları kurulu değil; iPad şu an `devicectl` eşleşmiş cihaz listesinde yok (USB ile bağlayıp "Bu bilgisayara güven" + Geliştirici Modu gerekir); Godot'nun ürettiği Xcode projesinin Xcode 26.3 ile derlenmesi ve iPad'in iPadOS sürümünün SDK 26.2 ile uyumu denenmedi. Değerlendirme: uygulanabilir görünüyor (Intel Mac'te Xcode ile arm64 iOS derlemesi olağan); kanıt T-007'deki boş sahne cihaz testiyle gelir. Risk: gelecekteki Xcode sürümleri Intel Mac'i bırakırsa iOS derlemesi için Apple Silicon Mac gerekir.
5. **Geliştirme ortamı yalnız macOS.** `tools/*.sh` bash'tir; Windows hedef platformdur, geliştirme platformu değildir.

## Karar
1. **Profil katmanı** (`src/app/platform_profile.gd`, M1'de): `{platform, input_profile, ui_profile, graphics_profile, max_game_speed, tick_slicing}`; özellik etiketlerinden (`OS.has_feature`) ve kullanıcı ayarından seçilir. Simülasyon kodu profili **okumaz**.
2. **Girdi profilleri:** `desktop` (fare: seç/sürükle-pan/tekerlek zoom/orta tuş veya Q-E dönüş, klavye kısayolları, macOS trackpad jestleri) ve `touch` (tek parmak pan, pinch zoom, iki parmak dönüş, uzun bas = bağlam). Aynı oyuncu fiilleri, farklı yerleşim.
3. **UI profilleri:** ortak bileşenler, profil başına yerleşim/ölçek; masaüstü daha yoğun panel ve hover bilgisi; iPad ≥44 pt hedef, güvenli alan, hover'sız eşdeğerler.
4. **Grafik profilleri:** Compatibility bugünkü başlangıç renderer'ıdır, değişmez değildir (D-004). Her platform ve kalite profili için Compatibility / Mobile / Forward+ cihaz ölçümüyle karşılaştırılır (T-010) ve kazanan profile yazılır (renderer başlangıçta seçilir; proje ayarı özellik geçersiz kılmaları ve `--rendering-method` ile). Profil içi ayarlar: gölge, HLOD mesafeleri, ayrıntı yarıçapı, MSAA.
5. **Performans hedefleri:** masaüstü referans = geliştirme Mac'i (minimum donanım vekili, ADR-0001 tablosu); Windows referans cihazı belirlenince eklenir; iPad bütçesi `experiments/scale-bench` cihazda koşulunca yazılır.

## Platform test hedefleri
| Platform | Ne zaman | Ne | Önkoşul |
|---|---|---|---|
| macOS (Intel, geliştirme Mac'i) | her görev | `verify.sh`, capture, benchmark | mevcut |
| macOS export (.app) | M1 (T-007) | export + açılış duman testi + benchmark | export şablonları |
| Windows export (.exe) | M1 (T-007) | export her milestone'da; **çalıştırma** cihaz gelince | şablonlar + Windows cihazı (kullanıcı) |
| iPadOS (iPad Pro M serisi) | M1: zincir T-007 (boş sahne cihazda); duman testi T-008 (ilk grafik + girdi prototipi T-001/T-003 sonrası); sonra her milestone | export → Xcode → cihaza kurulum/açılış, dokunmatik profil, kare süresi, scale-bench | cihaz mevcut; iPad'in USB ile bir kez eşleştirilmesi (kullanıcı) |
| Çapraz platform determinizm | M1'de altyapı, her yeni platform cihazında koşu (T-009) | aynı senaryo → aynı `StateHash` | T-002, T-007 |
| Renderer/kalite profilleri | M1 (T-010), cihaz eklendikçe | Compatibility / Mobile / Forward+ karşılaştırması (macOS Intel, iPad Metal; Windows sonra) | T-007 |
| Apple Silicon Mac | erişim olunca | macOS Metal yolu | cihaz (kullanıcı) |

## Sonuçlar
- Simülasyon tasarımı hiçbir aşamada "iPad'de çalışır mı?" diye kısılmaz; iPad farkı ölçümle görünür hâle gelir ve sizin kararınıza sunulur.
- Masaüstü UX birincil olduğu için kamera/UI görevleri (T-003, M2 UI) önce masaüstü profiliyle kabul edilir, dokunmatik profil aynı görevde en az duman testiyle gelir.
