# Altyapı yetmiyor ipucu (UI) · 2026-10-31

REQ: SIM-12 (neden görünür), CAN-03 (yalnız belediye eylemi: yol), D-008 (oyuncu bölgenin neden bina almadığını okur). Sim, sözleşme, `playable.gd` (1000 satır), `m2_results.gd`, `reason_panel.gd` DEĞİŞMEDİ. Commit yok.

## 1. İnceleme (gerçek akış: yolsuz plan -> plan yürürlükte)
| Yer | Önce | Bulgu |
|---|---|---|
| Bildirim şeridi | Altyapı vazgeçmeleri "Yatırımcı vazgeçti · Parsel N" (arka plan önceliği, her parsel ayrı, neden yok) | Neden ve eylem yok; 12 satır şeridi doldurur. |
| Döngü sonucu paneli | "Vazgeçti ... Neden: altyapı kapasitesi yetmiyor" | Neden var, ama ne yapılacağı yok. "Nedenini gör" gerekçe kaydı budanmışsa (1000'lerce ret) yok; "budandı" notu dürüst. |
| Parsel denetçisi (ilçe bandı "Seçili parsel" kartı) | "Neden: altyapı kapasitesi yetmiyor" | Eylem yok. |
| Gerekçe paneli (ReasonPanel) | `reason.infra_gate_note` + yol komutu kaynağı zaten var | Dokunulmadı (kare takılması düzeltmesi korunur). |
| Plan sonucu metni (`PlanStateText`) | Teklif/planlı/plansız durumları | Plan yürürlükte; altyapı nedeni plan durumu değil yatırımcı kararıdır, burada eklenmedi. |

## 2. Değişiklik (yalnız metin + okuma, yeni sözleşme yok)
- `data/ui/strings.tr.json`: `strip.infra_summary` ("{n} parselde altyapı yetmiyor; yol eklemek kapasiteyi artırır"), `m2.hint.infrastructure`, `m2.hint.infrastructure_n`.
- `src/ui/hud/notification_strip.gd`: `event.investor.declined` + kod `infrastructure_exhausted` tek tek listelenmez; plansız özetine benzer TEK özet satırı (benzersiz parsel sayısı). Parsel yatırım alınca/başka karar gelince sayıdan düşer. API: `is_infra_decline`, `infra_count`, `infra_summary_text`.
- `src/ui/flows/m2_result_model.gd`: `infra_declined_count()`.
- `src/ui/flows/m2_result_panel.gd`: karar kartının altında ipucu satırı (1 parsel: tam cümle; birden çok: sayılı). Yalnız öneri SONRASI ve kodu `infrastructure_exhausted` olan kararlar sayılır.
- `src/ui/panels/inspector_panel.gd`: seçili parsel kartında nedenin altında tek ipucu satırı.
- Okunan sim alanları: `SimEvent.message_key/args.code/subjects` (şerit); `ParcelView.decision/decision_code/decision_tick` (panel, denetçi). Sayı/uydurma yok; ipucu yalnız ret kodu altyapı ise çıkar.
- Ölü buton yok; CAN-03: yalnız "yol eklemek" yönlendirmesi, bina yerleştirme yok.

## 3. Testler
`tests/ui/infra_hint_test.gd` (5 test): gerçek ekonomi + gerçek plan/yol komutları (PlayableEconomy dar kapasite): yolsuz planda panelde neden + ipucu; karar yokken ipucu yok (negatif); yol sonrası altyapı-ret sayısı düşer; şerit tek özet satırı (tekrar parsel sayılmaz, tek satır listelenmez); yatırım alan parsel sayıdan düşer, talep reddi satır olarak kalır. Kırmızı->yeşil: kod öncesi `infra_declined_count` ve şerit API'leri yoktu (derlenemezdi); ilk koşuda ipucu "0 parselde" hatası test kurulumundaki izleme zamanından geldi, düzeltildi.

## 4. Gerçek runtime (pencereli, `playable.tscn`, sürücü: scratchpad `infra_flow_capture.gd`)
Yolsuz plan (12 boş parsel, zone.mixed) -> 160 gün -> panel + denetçi görüntüsü -> yol (sürücü, `public_work.road`) -> 120 gün -> panel görüntüsü. Görüntüler (1600x900, repoda değil): `/private/tmp/claude-501/ugr_screens/h1600-1-yolsuz-panel.png`, `h1600-2-yolsuz-denetci.png`, `h1600-3-yol-sonrasi-panel.png`. Ölçüm: yolsuz plan 12 parselin 12'si altyapı reddi (şerit: "12 parselde altyapı yetmiyor; yol eklemek kapasiteyi artırır"); 211 m yol sonrası 120 günde 4 onay/4 tamamlanan proje, şerit sayısı 12 -> 8. 1024x768 yakalama DENENMEDİ (iki pencere aynı anda kare akışını durdurdu; tek pencereyle 1600x900 alındı); pencereli yakalama ara sıra takılır (tools/capture.sh notu).

## 5. Doğrulanmış / varsayılan / test edilmemiş
Doğrulanmış: `tests/ui` 331 test 0 hata 0 başarısız (20 yetim düğüm uyarısı, çıkış kodu 101; yeni suite tek başına 0 yetim); gdlint temiz (5 dosya); pencereli 1600x900 yakalama (3 görüntü), bakıldı. 1024x768 ve dokunmatik profil yakalanmadı.
Varsayılan: ipucu metni düz Türkçe ve yol eylemine yönlendiriyor (kullanıcı okuması yapılmadı). Bir yol kapasiteyi artırınca ipucu satırı yatırımcı yeniden değerlendirene kadar kalır (sim davranışı: ret sonrası bekleme `decline_backoff_days`); "yol eklendi, yatırımcı yeniden bakıyor" ara durumu gösterilmedi.
Test edilmemiş: fiziksel iPad/dokunmatik, `verify quick/full` (siz koşturacaksınız), yol ve plan ardışıklığı dışındaki bölgeler, ipucunun yol çizme aracına doğrudan düğmeyle bağlanması (bilinçli: ölü/yeni buton yok; araç çubuğunda "Yol çiz" zaten var).
Bulgu (sim, bu iş dışı): yüzlerce ret varken gerekçe kaydı budanıyor ("kayıt kapasite nedeniyle budandı"); ipucu kodu bu yüzden gerekçe kaydından değil `decision_code`dan okur.
