# İlk oynanabilir temel

Godot 4.7.2 / GDScript; Intel Mac için Compatibility renderer, ortografik Camera3D. iPad landscape 1366×1024 mantıksal alan, uyarlanabilir Türkçe Control HUD. Gerçek iPad performansı ve export ayrıca doğrulanacak.

## Sınırlar
- `simulation/`: RefCounted veri ve kurallar; Node, kamera veya kare hızına bağımlılık yok. GameState içinde Parcel, Owner, Investor, Development, Municipality, CitizenGroup.
- `world/`: sabit mahalle yerleşimi, materyal başına gruplanan geometri, parsel görselleri, kamera ve ray seçimi. Görsel temsilden simülasyona geri yazılmaz.
- `ui/`: durum okur, imar teklifi ve belediye politika komutları gönderir.
- `main.gd`: bağımlılıkları bağlar; zaman biriktirici sabit gün adımlarını çalıştırır. İnşaat kararı yalnızca simülasyon gününde alınır.

## Nedensel döngü
Özel boş parsel → imar teklifi → sosyal çıkarlar ve bütçeden hesaplanan küçük meclis oylaması → yatırımcının maliyet/getiri eşiği → fonlanmış şantiye → günlerle ilerleme → konut/işyeri ve vergi geliri → gruplara gerekçeli tepki. Belediye özel bina yaratamaz. Kamu parselinde park yatırımı ayrı belediye harcamasıdır.

32 parsel / 4 yol adası; konut ve ticaret yatırımcıları farklı getiri eşiği ve talep ağırlığı kullanır. Sabit seed ile aynı başlangıç. Gelir, gider, doluluk ve arazi değeri modelden hesaplanır; tüm kararlar günlükte izlenir. Olumlu gelişim ve maliyeti yüksek/erişimi zayıf olumsuz senaryo ayrı test edilir.

## Kalite kapıları
Önce genel/yakın gerçek Godot görüntüleri ve kompozisyon incelemesi; ardından simülasyon bağlantısı. Headless testler: deterministik sonuç, kare süresinden bağımsızlık, bina spawn yasağı, oylama, yatırım eşiği, inşaat süresi, bütçe ve kayıt yükleme. Runtime doğrulaması: UI, kamera, seçme, önce/şantiye/sonra görüntüleri. Tekrarlayan geometri materyal bazında birleştirilir; dekoratif hareket az tutulur. Fiziksel iPad ve dokunmatik cihaz test edilmeden doğrulandı denmez.
