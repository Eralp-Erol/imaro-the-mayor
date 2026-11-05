# 2026-11-05 · art-director · M2 görsel kalite kapısı

Karar: **PASS WITH FIXES (KABUL EDİLEBİLİR)**. Godot çalıştırılmadı, kod okunmadı; yalnız aşağıdaki gerçek kareler açılıp bakıldı.

## Bakılan kareler (ana klasör `imaro-the-mayor-handover-imaro-m01-349562fb/artifacts/`)
- Masaüstü 1600x900: `qa/t066-window/desk-01, -04, -06, -08, -10, -15`
- Dokunmatik 1024x768: `qa/t066-window/touch-01, -04, -10b, -20`
- Smoke: `screenshots/captures/20261105-003056-playable-smoke.png`, `...003419-playable-smoke-k8-lod0.png`, `...003445-playable-smoke-k8-lod1.png`
- **Bulunamadı:** `t066-fix`, `her-yolu-yik` kareleri; 800x600 ve 768x1024 dokunmatik kareler. Bu çözünürlükler için **karar verilemedi**.

## Başlıklar (gördüğüm)
| Başlık | Karar | Neden |
|---|---|---|
| Zemin/arazi | KABUL EDİLEBİLİR | Metro karesinde kıyı, sığ su, tarla dokusu iyi okunuyor; sokak ölçeğinde zemin her yerde bej toprak ve üstünde büyük koyu bulut lekeleri var (desk-01, touch-20), kent "tozlu şantiye" gibi duruyor. |
| Bina-yol-bitki tutarlılığı | KABUL EDİLEBİLİR | 4-5 katlı bloklar, servi/yayvan ağaç, araç ölçeği birbirine uyuyor; ama tek kırma çatılı blok çok tekrarlanıyor ve çatıların büyük kısmı kiremit (VIS: "hepsi kırmızı kiremit" riski). |
| Yıkılan yol / boş belediye arazisi | YENİDEN YAPILMALI | Yıkım sonrası alan düz, doygun hardal sarısı tek renk leke (desk-06, -10, -15); çevreyle uyumsuz, "yer tutucu" okunuyor. 120 gün sonra 15 parselde yalnız 2 bina var; boşluk çok büyük duruyor. |
| Işık | GEÇTİ | Düz gün ışığı, yumuşak gölge, altın saat yok; low-key. |
| HUD masaüstü | KABUL EDİLEBİLİR | Türkçe, okunur, kontrast iyi; sağ panel ekranın ~%25'ini, sol bildirim yığını 4 satırı alıyor. |
| İmar paneli | YENİDEN YAPILMALI (UI) | Liste ham kimlikle dolu ("Parsel 19837 · Yapılı parsel: plan akışı yok", touch-10b'de 15 parsel numarası tek paragraf); seçili 15 parsel haritada vurgulanmıyor (desk-10). |
| HUD dokunmatik 1024x768 | YENİDEN YAPILMALI (UI) | touch-04 / touch-10b'de paneller şehrin ~%60'ını örtüyor, yeni çizilen yol neredeyse görünmüyor; altta yalnız "Gün N" yazan boş, uzun şerit var; üst çubuğun üstünde ~25 px şehir şeridi açık kalıyor. |
| Kalabalık/yoğunluk | KABUL EDİLEBİLİR | Sokak ölçeği yaşayan bir kent gibi; yaya yok, araç seyrek (Q-026 sahipte). |
| Hatalı çizim | KABUL EDİLEBİLİR | Beyaz/boş kare yok. K8 karesi (liman) yolsuz, ağaçsız, gölgesiz, düzgün dizili aynı hangarlar: oyun karesi olarak "kutu grid" okunur (izole test kamerası olabilir, çıkarım). LOD0/LOD1 gözle aynı. Sağ üstte zeminde nokta/dither deseni (touch-20). |

## Teknik-sanat işleri (technical-artist / ui-engineer)
1. Boş/yıkılmış arazi materyali: düz sarı yerine çevre zeminiyle karışan kuru çim/toprak, parsel kenar çizgisi.
2. Sokak zeminindeki büyük koyu lekelerin kaynağını bul (bitki maskesi/AO?); yoğunluğu yarıya indir.
3. Bina çeşitliliği: düz çatı ve açık renkli cephe oranını artır, aynı bloğun yan yana tekrarını kır.
4. İmar listesi: parsel numarası yerine "15 parsel" özeti + haritada seçim vurgusu; dokunmatikte panel daralt/katla, "Gün N" şeridini kaldır.
5. Liman/sanayi karesini oyundaki gibi (yol + bitki açık) yeniden çek; ancak ondan sonra karar verilir.

## SAHİBE SOR (karar uydurulmadı)
- Çatı paleti: kiremit ağırlıklı mı kalsın, yoksa daha çok düz/beton çatı mı?
- Boş belediye arazisi oyunda nasıl görünsün: kuru tarla mı, şantiye çiti mi, düz çim mi?
- Dokunmatikte panel: sağdan tam yükseklik mi, alttan yarım çekmece mi?
