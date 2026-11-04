# 2026-11-04 · T-066 pencereli gerçek-oyun doğrulaması (bağımsız QA)

Sürücü: `artifacts/qa/t066-window/t066_window_probe.gd` (gerçek `playable.tscn`, `Viewport.push_input` fare/tekerlek/dokunma
girdisi; kaynak kod değişmedi). Çalıştırma: `tools/godot.sh --path . --resolution WxH --script <probe> -- --shots=<dizin> --prefix=ad`.
Kod durumu: masaüstü koşu b6a3717 (HEAD), dokunmatik koşu 17:33 (ana oturum 17:35'te `05166fa` birleştirmesini yaptı; koşu
başlangıçta yüklenen betiklerle sürdü).

## Görüldü (kareler `artifacts/qa/t066-window/`)
- Yol çiz -> kamulaştır -> onay (15 arsa, 10 bina yıkıldı) -> "Son yolu yık" -> "Evet, yık": `desk-02..06`. Yıkım sonrası sarı boş arazi.
- İmar sekmesi > "İmar önerisi" panelinde "Boş belediye arazisini imara aç: 15 parsel" düğmesi, panelin ilk (alan) adımında, tam genişlik,
  okunur: `desk-08`. Tıklayınca 15 satır + "Belediye arazisi: ..." notu: `desk-09`.
- Kullanım = Konut, önizleme "Potansiyel birim: 59 ... Eklenen yük boş kapasiteyi aşıyor", "Meclise sun": `desk-10b`.
- Gönderim -> "Öneri sıraya alındı", meclis "5 evet, 0 hayır", yürürlük, "İnşaat başladı/tamamlandı": `desk-11..15`.
- Dokunmatik 1024x768: aynı akış `touch-*`.

## Ölçüldü (QPROBE_CENSUS, `desk-run2.log`, `touch-run.log`)
- 15 parsel TAKEN (yol), yıkımdan sonra hâlâ 15 TAKEN, hiç bina/arsa yok (30 gün bekleme dahil), `municipal_lands` 15 uygun.
- İmar gönderiminden sonra: gün 36 tick'inde değişim YOK (taken 15), gün 46 bekleyen 15, gün 56: taken 0, 12 `planned` (by_sim,
  `decision=approved`), 3 `vacant` (`declined/infrastructure_exhausted`); gün 66 `under_construction`; gün ~126 `built`.
  Bina yalnız yatırımcı kararından (CAN-03 yerine geliyor); yıkım ve imar kararı tek başına bina üretmedi.

## Hatalar
B-022 (yanlış "Yapılı parsel" etiketi), B-023 (kullanım/gönder ekran dışı, dokunmatikte 17 tekerlek adımı), B-024 (1024x768'de
panel 6 px taşıyor), B-025 (şüpheli: sim 12 yapı, çizim ~2).

## Görülmedi
Gerçek parmak kaydırması, fiziksel iPad, kayıt/yükle sonrası pencere, B-025 kök nedeni, imar sonrası TAMAMLANMIŞ yapıların geniş açı karesi.
