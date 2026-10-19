# Imaro: The Mayor · doğrulama, 19 Ekim 2026

Godot 4.7.2, macOS / Radeon Pro 560X, Compatibility renderer. Mevcut simülasyon–dünya–HUD ayrımı korundu; yeni oyun sistemi eklenmedi.

| Kontrol | Sonuç | Kanıt |
| --- | --- | --- |
| Deterministik simülasyon, bütçe, yatırım, kayıt/yükleme | 28/28 | [simulation.json](../artifacts/tests/simulation.json) |
| Gerçek viewport girdisi, parsel, HUD, imar, oyun saati, inşaat, kamera | 25/25 | [gameplay.json](../artifacts/tests/gameplay.json) |
| Masaüstünde native dokunma olayları, üç yatay pencere boyutu | 16/16 | [touch-input.json](../artifacts/tests/touch-input.json) |
| Fiziksel iPad, iOS export ve sürdürülebilir performans | Test edilmedi | Cihaz koşusu gerekli |
| Referanslarla görsel kalite eşleşmesi | Kısmi; kapı açık | Aşağıdaki karşılaştırma |

## Kök neden ve düzeltmeler

Önceki beş oynanış hatası test girdisinin koordinat uzayından kaynaklanıyordu: kamera ve HUD mantıksal viewport konumu üretirken test bunları pencere pikseli olarak gönderiyordu. Mouse paketi artık `Viewport.push_input(event, true)` kullanıyor; dokunma paketi `Input.parse_input_event` öncesinde mantıksal koordinatları pencereye dönüştürüyor. Standart kontrollerin arasına masaüstü imlecinin hover olayının girmemesi için sentetik mouse tıklaması aynı giriş karesinde tamamlanıyor. [Godot viewport giriş sözleşmesi](https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-method-push-input).

Test farklı bir parselden başlar; gerçek collider seçimi ve HUD teklifi kontrol edilir. Meclis, piyasa ve inşaat gerçek `_process` saatiyle, HUD 4×/duraklatma düğmeleri üzerinden ilerler. Screenshot manifesti gün ve parsel durumunu kaydeder. Yeni koşu eski başarı raporunu kaldırır; tamamlanmamış koşu başarı sayılmaz.

Görüntü yakalamada HUD çizim kuyruğu yenilenip normal Godot karesinin tamamlanması beklenir. Böylece kare ortasında elle render tetiklenirken görülen eksik düğme yazıları son görüntülerde giderildi.

Dokunma testinde ayrıca iptal edilen parmağın seçim üretmesi, odak kaybında jestin takılması ve küçük ekranda hedeflerin küçülmesi yakalandı. İptal/odak/yeniden boyutlandırma temizliği eklendi; düğmeler 64 mantıksal birime çıkarıldı. 1024×768, 1180×820 ve 1366×1024 pencerelerde seçim, tek teklif, UI'nın dünya girdisini tüketmesi, pan, pinch ve dönüş geçti. Ekran pikseli ölçümü fiziksel iPad point ölçümü değildir.

## Gerçek görüntüler ve referans karşılaştırması

- [Genel görünüm](../artifacts/screenshots/03-gameplay-overview.png): Imaro markası ve Ilgın Belediyesi ayrı; gerçek 3D parseller, Türkçe HUD ve ₺.
- [Şantiye başlangıcı](../artifacts/screenshots/04-construction.png) → [9/18 günlük şantiye](../artifacts/screenshots/04b-construction-progress.png) → [tamamlanmış yapı](../artifacts/screenshots/05-completed.png). Kapasite 460→478 konut, nüfus 796→828; şantiye sırasında kapasite artmıyor. Manifest günleri sıfır tabanlı, HUD günleri bir tabanlıdır.
- [Yatırım gelmeyen parsel](../artifacts/screenshots/07-investment-declined.png): konut imarı onaylı, özel arsa hâlâ boş; negatif getiri görünür.

Referans 01/02/04 ile ortak yönler: blok/prizma kütleler, balkonlar, düz çatılar, güneş depoları, esnaf tenteleri ve kıyı. 03/08'deki karar katmanı gerçek simülasyonla bağlı. Ancak cepheler fazla tekrarlı, sokak kompozisyonu fazla düzenli, açık yüzeyler fazla parlak ve gölgeler sert. Karakter/sokak canlılığı sınırlı. 06/07'deki yağmur, trafik sorunu ve yerinde kriz deneyimi uygulanmış sayılmıyor; hava düğmesi görsel palet değiştirir. Görsel kalite kapısı henüz kapanmadı.

## Sonraki kalite kapısı

Önce cephe çeşitliliği, sokak silueti ve ışık/gölge için aynı açılardan yeni görüntüler. Ardından Godot sürümüyle eşleşen iOS export ve imzalı debug derlemesiyle fiziksel iPad koşusu:

1. Cihaz/OS/renderer/derleme kimliğini kaydet; parsel → HUD → imar zincirini tek parmakla tamamla.
2. Panel kaydırma, iki parmak pan/zoom/dönüş, iptal, kenar jestleri ve UI üzerinden dünyaya yanlış dokunmayı kontrol et. Güvenli alan/home indicator ve en az 44 pt hedefleri cihazda ölç.
3. Uygulamayı arka plana alıp aç; kilitle/aç; jest, zaman ve kayıt durumunu kontrol et. Otomatik yaşam döngüsü kaydı ve tam güvenli alan desteği henüz teslim edilmiş değil.
4. En az 15 dakika oynayıp kare sürelerini, bellek, ısınma ve yükleme sıçramalarını ölç. Masaüstü raporundaki tek kare FPS/draw-call değerleri cihaz performansı kanıtı değildir.

Bu kapılar tamamlanmadan yeni oyun sistemlerine geçilmemeli.
