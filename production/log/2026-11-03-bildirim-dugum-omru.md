# Bildirim şeridi düğüm ömrü / orphan uyarıları

REQ: TEK-03, SIM-12; yalnız UI bellek ömrü, görünüm/tasarım kararı yok.
2893 testlik full koşusunun 22 uyarısı `full-2893-unit.log`dan ayrıştırıldı:
`hud_root_test` 4, `honest_ui_test` 12, `m2_result_panel_test` 4,
`playable_expropriation_game_test` 2. Hepsi HUD/profil/panel yenilemesinde.

Kod: `NotificationStrip.create` ihtiyaç olmadan iki özet satırı (satır + etiket =
4 Node) oluşturuyor, ağaca bağlamıyor. Şerit silinirken PREDELETE ile temizleniyorlar
ama eski HUD silinmek üzere kuyruğa girince, bu ayrı düğümlerin silinecek bir üst
düğümü yok; test sayacı onları orphan görüyor. Kalıcı kaçak olduğu iddia edilmiyor.

Plan: özetleri yalnız gerçek veri gerektiğinde oluştur, daima şeridin çocuğu tut;
artık gerekmeyen özeti silme kuyruğuna al. Kabul: boş şeritte sahipsiz özet düğümü
yok, gerçek sayılar ve mevcut satır yeniden kullanım/yerleşim testleri aynı,
bu dört test grubunun orphan sayısı sıfır. Yeni düğme/metin/oynanış yok.

Regresyon önce KIRMIZI: boş bir şerit yaratılması root orphan listesini 4 artırdı
(`strip-red.log`, 6 test, 1 başarısızlık, script hatası yok). Özetler artık yalnız
gerekince `_sync_summary` ile yaratılıp şeride bağlanıyor; gerek kalmadığında
silme kuyruğuna alınıyor ve referans bırakılıyor. PREDELETE'de sahipsiz düğüm
temizleme ihtiyacı kalktı. Sayılar/metinler, sıra ve görünür durum aynı API'den geliyor.

Hedefli koşu (`strip-green.log`): 5 suite / **46 test, 0 hata/başarısızlık,
0 orphan**. Yukarıdaki dört uyarılı suite'in hepsi (gerçek playable kamulaştırma
testi dahil) aynı koşuda temiz. Bu, uyarıların kaynağını doğrular; fiziksel iPad
veya görsel tasarım kabulü anlamına gelmez. Birleşik quick/full sonucu sonra eklenecek.

Son birleşik doğrulama: **verify quick PASS 1369 test, 0 orphan (KISMİ)**;
**verify full PASS 2897 test, 0 hata/başarısızlık/orphan**, canon-guard 105,
pencereli smoke 180 kare temiz. Fingerprint `dd77d85e8a06…`; tam kanıt
`2026-11-03-kayit-parsel-denetimi.md` kapanışında. Bu sonuçta önceki 22 uyarı yoktur.
