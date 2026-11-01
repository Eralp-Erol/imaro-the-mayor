# 2026-11-01 · iPad hız ipucu şeridi + mock yıkım dürüstlüğü

REQ: CAN-03 (yalnız belediye eylemleri), SIM-12 (ret nedeni görünür), ADR-0004 (touch >= 44 pt, aralık >= 8 pt).

## A · Hız ipucu kartı (`src/game/playable_speed_hint.gd`)
- Kök neden: kart etiket + "Hızlandır" + "Kapat" düğmelerini TEK yatay satıra koyuyor, genişliği serbest harita
  alanının %40'ı (iPad paneli açıkken ~250 px) ile sınırlıyordu. Düğmelerin asgari genişlik toplamı bunu aştığı için
  sarmalı etiket tek harf genişliğine ezildi (dikey harf yığını); kart ayrıca bildirim sütununun x aralığını hiç
  hesaba katmıyordu (konum yalnız harita alanının sağ-üstüne göreliydi).
- Düzeltme: etiket üstte, düğmeler altta (dikey yerleşim); genişlik bildirim sütununun SAĞINDAki boşluktan hesaplanır
  (en çok 460, en az `MIN_WIDTH` 220); sığmazsa kart bildirim şeridinin ALTINA iner. Sarmalı etiket gerçek genişliğe
  ilk karede oturtulur.
- Test: `tests/ui/speed_hint_layout_test.gd` (desktop 1600x900, touch 1024x768, touch/desktop 800x600; panel açık/kapalı):
  etiket <= 3 satır, kart >= 220 px, bildirim şeridi/panel/araç çubuğuyla çakışmaz, harita alanında, touch hedef >= 44,
  düğme aralığı >= 8.

## B · Mock `public_work.demolish`
- Mock yıkımı uygulamıyordu ama `_precheck` sessizce kabul ediyordu (Yık düğmesi görünür, basınca hiçbir şey olmazdı).
- Şimdi mock `public_work.reject.demolition_mock` ile reddeder; yol paneli düğme yerine "Bu yol şu an yıkılamaz: Örnek
  (MOCK) veri kipinde yol yıkımı uygulanmıyor; gerçek simülasyonda çalışır." yazar. Sahte sayı yok.
- Test: `tests/contracts/demolish_contract_test.gd::test_mock_rejects_demolish_honestly_...`.

## Doğrulanmamış
- Fiziksel iPad dokunması; kırmızı-yeşil (eski kodla testin kırmızı olduğu) ayrıca çalıştırılmadı.
