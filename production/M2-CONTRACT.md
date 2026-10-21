# M2 görev ve doğrulama sözleşmesi (2026-10-21)

Kullanıcı talimatı (2026-10-21): M1 kapısındaki "M02 YOK / DUR" kısıtı **kaldırıldı**; geliştirme M2 ve sonrasına otonom sürer.
Bu sözleşme M1 sözleşmesinden **bağımsızdır**: M1'in `exit 2` ("yalnız kullanıcı/cihaz onayı kaldı → DUR") kuralı M2'nin
durdurma koşulu DEĞİLDİR. M1'in bekleyen kullanıcı/cihaz kabulleri (`docs/agent-handoff/M01_OPEN_ITEMS.md`) açık kayıtlı
kalır, yeni geliştirmeyi durdurmaz ve kimse onları kullanıcı adına vermez.

## Amaç (ROADMAP M2, "ilk nedensel döngü")
Oyuncunun parsel üzerindeki imar kararı → yatırımcının gerekçeli kararı → inşaatın zamanla ilerlemesi → **gerçek 3D yapı
değişimi** → ölçülebilir ekonomik ve siyasi sonuç → aynı alanın farklı zoom'larda incelenmesi. Sahte bina spawn'ı, sabit HUD
verisi veya yalnız animasyonla temsil edilen sonuç yoktur (CAN-03; "HUD yalnız gerçek sim verisi").

## Görev sırası (bağımsız, sıralı; her biri kendi kabul ölçütleriyle)
| ID | Kapsam | Bağımlılık | Ana REQ |
|---|---|---|---|
| **T-040** | Dikey dilim çekirdeği: imar kararı → yatırımcı kararı → inşaat → gerçek 3D yapı (sim'den türeyen, hücre-yerel) → ölçülebilir ekonomik/siyasi sonuç (HUD) | — | CAN-03, SIM-01..05, SIM-12, WLD-01, VIS-02 |
| T-041 | Parsel/bölge denetçisi: aynı alanı metro/ilçe/sokak zoom'unda incele, nedensellik zinciri (karar→gerekçe→inşaat→sonuç) tek panelde | T-040 | CAN-04, SIM-12, VIS-03 |
| T-042 | Oyuncu yol/kamusal alan çizimi → altyapı kapasitesi → yatırımcı kararına etkisi (gerekçede görünür) | T-040 | CAN-05, WLD-12, SIM-03 |
| T-043 | Geliştirme test alanı Orven (D2) ve ≥2 ilçe kimliğiyle başlatma (başlangıç veri parametresi) | T-040 | WLD-01, CAN-06 |
| T-044 | M2 kapı raporu: F03 ölçütleri eşleme tablosu, bağımsız QA özeti, açık kullanıcı/cihaz kabulleri (iPad dilimi cihazda) | T-040..T-043 | M2 çıkış ölçütü |

Ayrıntılı görev dosyası yalnız görev başlayınca açılır (`production/tasks/T-0NN.md`, şablon `_TEMPLATE.md`); T-040 şimdiden açık.

## Görev başına protokol (her görevde aynı)
1. **Kısa kapsam** (görev dosyası: ölçütler + REQ + kanıt planı + doğrulanmayacaklar).
2. **Implementasyon** (ilgili hat/uzman; sim saf+deterministik; render sim'den okur, sim'e yazmaz).
3. **Odaklı test**: görevin kendi testleri + `tools/lane.sh verify <hat>`; tam doğrulama yalnız teslimde/ihtiyaçta.
4. **Bağımsız QA**: uygulayıcıdan farklı oturum/sağlayıcı; gerçek runtime (başsız sahne testi + pencereli yakalama);
   rapor `production/qa/T-0NN-qa.md` (`VERDICT: PASS|FAIL`, kanıt, bulgular, doğrulanmadı).
5. **Commit** (temiz ağaç) → **checkpoint** (`docs/agent-handoff/IMARO_CHECKPOINT.md` + görev dosyası kanıtı) → sıradaki göreve geç.

## Doğrulama sözleşmesi (M2)
Kabul tanımı makine-okunur: `production/acceptance/T-0NN.json` (zorunlu dosyalar, GdUnit hedefleri, zorunlu runtime artifact'ları,
açık kullanıcı/cihaz maddeleri). Uygulayıcı ve bağımsız QA bunu **elle/odaklı** çalıştırır: listelenen GdUnit hedefleri 0 hata,
`gdlint` temiz, `tools/canon-check.sh` + `tools/studio_check.py` PASS, temiz ağaç, artifact'lar gerçek runtime çıktısı.
Çıkış semantiği (otomasyon eklenirse): **0** doğrulandı · **1** FAIL · **3** ortam · **4** eksik. **Çıkış 2 ("yalnız kullanıcı/cihaz
onayı kaldı → DUR") M2'de YOKTUR ve hiçbir koşulda durdurma anlamına gelmez**; kullanıcı/cihaz onayı gerektiren maddeler görev
dosyasında "AÇIK — kullanıcı/cihaz" olarak listelenir, PASS/FAIL sayılmaz. Başarısız testi PASS işaretlemek, eşik gevşetmek veya
yavaş/başarısız kareleri ölçümden çıkarmak YASAK. (Genel bir `scripts/verify_imaro_task.py` yazılması araç izin sınıflandırıcısınca
reddedildi; bkz. §Otomasyon durumu.)

## Otonomi kuralları (özet; bağlayıcı)
- `design/foundation/` değişmez; açık yaratıcı kararlar geçici/yapılandırılabilir veriyle sürer, `production/QUESTIONS.md`'ye
  gruplanır, kullanıcı adına kesinleştirilmez. Kullanıcı/cihaz onayları (Q-015, iPad, Windows, art-director, M1 incelemesi) UYDURULMAZ.
- Claude tarafı yalnız Opus 5.5 / Sonnet 5.5 (**Haiku yasak**). `main`'e otomatik merge, force push, deploy YOK.
- Tekrarlayan hata/gerçek engel: görev dosyasına `Durum: ENGELLİ` + neden yazılır, bağımsız sonraki göreve geçilir.
  Sonsuz döngü yok: görev başına sınırlı deneme ve tur bütçesi.

## Otomasyon durumu (dürüst kayıt)
Görevler arası otomatik devam eden arka plan yürütücüsü (gözetmen) için bir TASLAK yazıldı (`docs/agent-handoff/drafts/`; çalıştırılmadı,
test edilmedi). 2026-10-21'de araç izin sınıflandırıcısı bu altyapının (gözetmen betiği ve genel kabul betiği) oluşturulmasını/çalıştırılmasını
reddetti ("Create Unsafe Agents"). Doğrulanmadığı için etkin DEĞİLDİR. Ayrıntı: `docs/agent-handoff/IMARO_CHECKPOINT.md` §0.
