# Imaro: The Mayor

Godot 4.7.2 ile gerçek 3D belediye başkanlığı prototipi. **Imaro: The Mayor** oyun markası; **Ilgın Belediyesi** oyun dünyasındaki kurgusal belediyedir. Hedef platform yatay iPad; mevcut doğrulama macOS üzerinde yapılmıştır.

Belediye özel bina yerleştirmez. Oyuncu imar teklifi verir; meclis kararından sonra yatırımcı maliyet ve getiriye göre bağımsız karar alır. İnşaat zamanla ilerler; tamamlandığında konut, işyeri, doluluk, bütçe ve mahalle tepkileri değişir.

## Çalıştırma

`project.godot` dosyasını Godot 4.7.2 ile açın veya proje kökünde:

```sh
.tools/Godot.app/Contents/MacOS/Godot --path .
```

Yerel `.tools/` kurulumu Git'e dahil değildir. Başka makinede aynı sürümün Godot yürütülebilirini kullanın.

- Parsel 24'ü seçin, karma kullanım teklifini meclise sunun ve üstteki 4× düğmesiyle zamanı ilerletin. 18 günlük özel inşaat sonunda nüfus ve kapasite değişir.
- Parsel 20'ye konut imarı teklif edin: onay alınsa bile yüksek maliyet nedeniyle yatırım gelmez. Gerekçe panelde görünür.
- Sürükleme: pan; tekerlek veya iki parmak: zoom; Q/E veya iki parmak açısı: dönüş. Sol HUD düğmeleri de kamerayı kontrol eder. Boşluk: zaman/duraklatma.
- Belediye, Bütçe ve Mahalle sekmeleri simülasyon verilerini gösterir. Hava düğmesi yalnızca görsel ışık paletini değiştirir.

## Kontroller

Görsel testleri sırayla çalıştırın; gerçek Godot penceresi açılır ve sonuç dosyaları yenilenir:

```sh
.tools/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
.tools/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/simulation_test.gd
.tools/Godot.app/Contents/MacOS/Godot --path . -- --capture-gameplay
.tools/Godot.app/Contents/MacOS/Godot --path . -- --test-touch
.tools/Godot.app/Contents/MacOS/Godot --path . -- --visual-capture
```

Sonuçlar: [test raporları](artifacts/tests/), [gerçek ekran görüntüleri](artifacts/screenshots/), [doğrulama ve açık kalite kapıları](docs/VALIDATION.md).

## Kapsam ve sınırlar

32 parsel, iki yatırımcı profili, deterministik gün adımları, meclis, inşaat, bütçe, sosyal tepkiler ve yerel kayıt/yükleme mevcut. Mimari sınırlar [teknik notta](docs/TECH-DIRECTION.md), hedef görsel dil [sanat yönünde](docs/ART-DIRECTION.md) açıklanır.

Fiziksel iPad, iOS export/imzalama, cihaz güvenli alanları ve uzun süreli performans henüz doğrulanmadı. Masaüstüne gönderilen dokunma olayları cihaz testi değildir. Cephe çeşitliliği ve ışık/gölge kalitesi referans seviyesine ulaşmadı; trafik, hava ve yaya görselleri kapsamlı simülasyon sayılmaz. Yeni sistemlerden önce görsel ve cihaz kalite kapıları tamamlanmalı.
