# Kayıt yüklemede parsel denetimi (ADR-0005 Ek J takip c)

REQ: TEK-01/02, WLD-01, CAN-03/04. Başlangıç: `522199d` üstündeki çalışma ağacı;
B-016 değişiklikleri için full PASS (2893 test) önceki kayıttadır, bu yeni değişikliğin kanıtı değildir.

Plan: yıkım yeniden oynatılırken eklenen/silinen parseller boş olmalı; kamulaştırma
bayraklı ama expropriation kaydı olmayan yol için beklenen alınan küme boş olmalı.
Uyumsuzluk `network_mismatch` ile reddedilmeli; facade durumu ve dünyanın TAM
`state_hash`i yükleme öncesiyle aynı kalmalı. Sıfır alınanlı gerçek yolun normal
kaydet/yükle/devam akışı bozulmamalı. GOLDEN_A/B/X değişmez.

Kanıt planı: gerçek küçük dünya ve sim üzerinde kontrollü hatalı replay raporu;
önce kırmızı, sonra yeşil testler; ilgili kayıt/yükleme ve GOLDEN testleri; `verify quick`.
Yeni kayıt biçimi, politika, sahip kararı veya HUD değişikliği kapsam dışı.

İlk test betiğindeki sabit dizi tanımı parse hatası verdi; düzeltilmeden davranış
kanıtı sayılmadı. Geçerli kırmızı koşu (`replay-red2.log`): 3 test, 12 başarısızlık,
0 script hatası; pozitif sıfır-alınan kaydı yüklenirken, üç sapma kabul edilip mevcut
oyunun üzerine yazılıyordu. Kontroller eklendikten sonra 5 suite / 68 test geçti
(`replay-green.log`), GOLDEN_A/B/X aynı. Olumsuz testler facade hash'iyle birlikte
dünyanın tüm `state_hash`inin de eski halinde kaldığını denetler.

`verify quick` PASS: 83/294 suite, 867 test, 0 hata/başarısızlık, 12 orphan uyarısı;
211 suite atlandı, KISMİ (`replay-verify-quick.log`). Bu aşamadaki fingerprint
`836d1cd16dc3…`; bildirim düğüm ömrü düzeltmesi daha sonra yapıldı.

## Birleşik kapanış

DOĞRULANMIŞ: son `verify quick` PASS (138/294 suite, 1369 test, 0 hata/başarısızlık,
0 orphan; KISMİ). Ardından **verify full PASS: 294/294 suite, 2897 test,
0 hata/başarısızlık/skip/orphan**. GOLDEN_A/B/X aynı; gdlint/import temiz,
canon-guard 105 PASS, pencereli smoke 180 kare hatasız.
Rapor `artifacts/verify/full-latest.json`; günlükler
`tmp/codex-resume-20261103/combined-verify-quick.log`, `combined-verify-full.log`.
HEAD `522199d` üstündeki commit edilmemiş çalışma ağacı; kaynak fingerprint
`dd77d85e8a0642cc10420ae76ee2f2478b326141da0bdad18087f1a7bde6cdd9` son kontrolle aynı.

VARSAYILAN: sapma testinde dünya hatası rapor sınırında kontrollü enjekte edilir;
gerçek dünyada bugün durduk yere parsel değiştiği iddia edilmez. Amaç ilerideki
dünya değişikliklerinin sessiz kayıt kaymasını engellemektir.

TEST EDİLMEMİŞ: fiziksel iPad/dokunma; gelecekteki bozuk bir motor derlemesiyle gerçek
parsel sapması. D-018 sonrası yeniden imara açma akışı bu değişikliğin parçası değildir.
