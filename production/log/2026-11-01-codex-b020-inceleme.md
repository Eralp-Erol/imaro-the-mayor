# Codex devir incelemesi · B-020 ve ölçüm önkoşulu

Dal: `agent/handover-imaro-m01-349562fb`, başlangıç HEAD `522199d`.
Kapsam: B-020 kuru koşu / sürüm önbellekleri; REQ: TEK-01/02/03, WLD-01, CAN-03.

## B-020 sonucu

Kod incelemesinde `_dry_run`ın başarılı geri almadan sonra sürümü ve günlüğü geri koymasının
istenen üç tüketicide bayat sonuç ürettiği bir vaka bulunmadı. Ürün kodu değiştirilmedi;
kanıtlanmış yeni hata olmadığı için yeni hata testi eklenmedi.

- `PublicWorksContext.draft` / `draft_expropriating`: anahtar sürüm + sınıf + noktalar.
  `DemolitionPlan.run` / `rollback` bu sorguları çağırmaz. Kuru koşu eşzamanlıdır;
  `await`, sinyal veya kullanıcı callback'i ile ara ağ durumunda bu memoları doldurmaz.
  Geri alma sonrası aynı anahtarın karşılığı yine aynı ağdır. `ExpropriationFlow.problem`
  ayrıca durum nesnesi, tick, alınan parsel sayısı ve politika bayrağını anahtara katar.
- `RoadDrawTool`: `_verdict_version` ve komut anahtarı ana iş parçacığında okunur;
  kuru koşu sırasında araç çalışmaz. Başarılı geri almadan sonra geçerli eski cevap
  korunur; gerçek yol değişikliği sürümü artırıp `refresh_if_graph_changed`i tetikler.
- `RoadEditSync`: `_seen_version` ve iş sürümü karşılaştırılır. Başarılı önizleme
  sahte pending üretmez; eski gerçek değişim günlüğü korunur. `change_log.duplicate()`
  sığdır ama kuru koşu eski `NetworkChange` nesnelerini değiştirmez; yeni kayıt ekler.
  Meşgul gönderim `_precheck`te kuru koşuya girmeden reddedilir (mevcut B-020 testi).
- Ağ içi türevler yalnız sürüme bağlı değildir: `NetworkRestore` hash sütunlarını
  kirli işaretler; `undo_last_op` bileşen önbelleğini temizler/geri koyar ve kimlik
  sayaçlarını geri getirir. Başarısız rollback dalı sürümü/günlüğü geri sarmaz.

Sınır: bu sonuç başarılı rollback ve mevcut çağrı yolları içindir. Daha sonra kuru
koşuya callback/await eklenmesi veya meşgulken doğrudan işleyici çağrılması yeniden
inceleme gerektirir. B-020 kaydındaki, önceden kuyruğa girmiş komutun işçi sürerken
tick sınırında ağı yazması ihtimali bu incelemede yeniden üretilmedi; çözüldü denmiyor.
Sim işleyicisinin dünya alanlarına doğrudan yazması mevcut bağlaşımdır; yeni bir
bayat veri vakası olmadan mimari değişiklik yapılmadı.

## Bu oturumda çalıştırılan doğrulama

`IMARO_GODOT=/Users/eralperol/Documents/Projects/imaro-the-mayor/.tools/Godot.app/Contents/MacOS/Godot`
ile `tools/godot.sh` kullanıldı; Godot süreçleri sırayla çalıştırıldı.

- `demolish_test.gd`, `road_edit_sync_test.gd`, `road_draw_tool_test.gd`:
  **39/39 test, 0 hata, 0 başarısızlık, 0 orphan; çıkış 0**.
  Ham çıktı: `tmp/codex-b020-tests.log`; XML/HTML: `tmp/codex-handover/b020-gdunit/report_1/`.
- `public_works_draft_memo_test.gd`, `m2_query_test.gd`,
  `golden_expropriation_undo_test.gd`: **29/29 test, 0 hata, 0 başarısızlık;
  çıkış 0**. GOLDEN_A/B/X sabitleri bu koşuda geçti; değiştirilmedi.
  Ham çıktı: `tmp/codex-cache-golden-tests.log`;
  XML/HTML: `tmp/codex-handover/cache-golden-gdunit/report_1/`.
- Başsız arayüz testleri gerçek fare/dokunma kanıtı değildir.
- Sonrasında `tools/verify.sh quick`: **PASS**, 34/293 suite, 354 test,
  0 hata/başarısızlık; **12 orphan uyarısı** (kaynağı bu oturumda ayrıştırılmadı).
  Kanon, studio, alan eşlemesi ve import geçti; değişen `.gd` olmadığından lint
  kaynak taraması yapmadı. 259 suite (~2538 test), canon-guard ve pencereli tam
  doğrulama çalışmadı. Bu sonuç **KISMİDİR**. Çıktı:
  `tmp/codex-handover-verify-quick.log`, `artifacts/verify/quick-latest.json`.
- `verify full` bu oturumda çalıştırılmadı. `c175c54` tam koşusu yalnız devir
  belgesinden bilinen tarihî sonuçtur.

## Performans önkoşulu / devam

İlk kontrol (yerel saat ~14:51): yük ortalaması **36,01 / 15,13 / 30,99**;
başka Swift derlemeleri, Node ve masaüstü uygulamaları çalışıyor.
`pmset -g therm` işlemci hız sınırı sırasıyla **%90, %39, %53, %62** gösterdi.
Bu ortam sakin makine değildir. Başkasının süreci sonlandırılmadı.
~14:57 son kontrolünde yük **223,71 / 96,48 / 58,19**, hız sınırı **%39** idi.
Sakinlik sağlanamadığı için demo performans koşusu başlatılmadı; sahibine ortam
durumu bildirildi. Yeni kare/yol süresi üretilmedi.

DOĞRULANMIŞ: yukarıdaki 68 hedefli test, kısmi quick kontrolü ve ortam kontrolleri.
VARSAYILAN: sürüm geri sarmanın güvenliği yukarıdaki mevcut senkron çağrı sözleşmesine bağlıdır;
tüm olası taslaklar için dinamik ispat değildir.
TEST EDİLMEMİŞ: sakin makinede `playable.tscn --demo` kare sıçramaları ve tick ~835
yol yeniden kurma süresi. Eski 125–140 ms / 1,16 s değerleri bu oturumun ölçümü değildir.
Sakin ölçüm tamamlanana kadar performans düzeltmesi önerilmedi; B-016'ya başlanmadı.
