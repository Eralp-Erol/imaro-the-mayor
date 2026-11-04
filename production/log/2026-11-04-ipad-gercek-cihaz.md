# iPad gerçek cihaz testi — 2026-11-04

Cihaz: iPad Pro 12,9" (6. nesil, iPadOS 26.5.2). Sürüm: debug dışa aktarma, sürüm 287e51a + export ayarı düzeltmesi.

## Yol
1. `tools/export.sh ios` (export_project_only) → Xcode projesi; Xcode otomatik imza, takım kimliği ve geçici yer tutucu ikon YALNIZ yerel çalıştırmada verildi (repoda yok).
2. `xcodebuild … -allowProvisioningUpdates -allowProvisioningDeviceRegistration` → iPad geliştirici hesabına sahibin onayıyla kaydedildi.
3. `xcrun devicectl device install app` + `process launch`.

## Bulgu ve düzeltme
- İlk açılışta zemin BEMBEYAZ. Kök neden: üç export ön ayarında `exclude_filter` `art/*` içeriyordu; `art/shaders/terrain_land.gdshader` ve `road_surface.gdshader` pakete girmiyordu. Düzeltme: `art/blender/*` (yalnız kaynak dosyalar dışarıda). Mac/Windows ön ayarlarında da aynı hata vardı.
- Ana sahne geçici olarak `scenes/game/playable.tscn` yapılarak denendi (repoda DEĞİŞMEDİ; proje hâlâ platform duman sahnesiyle açılır).

## Sonuç
- SAHİP BİLDİRİMİ (iPad'de kendisi): "oyunu başlattım ve istenildiği gibi çalışıyor", zemin sorunu çözüldü.
- Ölçülmedi: kare süresi/FPS, parmakla kaydırma/yakınlaştırma hassasiyeti, dokunma hedef boyutlarının cihazda doğrulaması, ısınma/pil, kayıt-yükleme, release sürüm. Sahibin "çalışıyor" cümlesi bir performans kanıtı değildir.
- Kullanılan yer tutucu ikon ve geçici ana sahne üretim sürümü değildir; iOS ana sahne/ikon/imza düzeni ayrı iş (karar gerektirmez: ikon sahibin görsel kararıdır).
