# GOLDEN_X kural-kapalı referansı: hash farkı nereden geldi? (2026-11-06)

Soru: B-130 (`ff15a0d`) sonrası `GOLDEN_X_BEFORE_D021` (kural kapalı referans) `c987fb3d…` -> `92d1a99e…` oldu. Sebep ne?

## Deney (doğrulanmış, geçici dosya değişikliğiyle `golden_x_council_trust_test.gd` koşuldu, dosya geri alındı, repo temiz)
| `data/actors/decision_tables.json` durumu | kural-kapalı hash |
|---|---|
| `ff15a0d` ÖNCESİ (tam dosya) | `c987fb3d9d6e338e2318902f8e5d73bdbeffb2f318442e1cfa07824193cd4094` (eski referans) |
| Bugünkü dosya, yalnız `petition` theta 190 -> 250 geri alınmış (yeni `_notes` metni duruyor) | `2099a3d6a5259a26afc0aa3439294519068e51f6db2535c495795130c55fa9ea` |
| Bugünkü dosya (theta 190, yeni `_notes`) | `92d1a99e9ef9b491683d790a7e8b5ca2f39510ba7114f1c2fde7e324e22c1ef6` (güncel referans) |

## Sonuç
- Hash iki ayrı adımda değişti: (1) yalnız `_notes` metni (belgeleme cümlesi) değişince `c987…` -> `2099…`; (2) theta 250 -> 190 olunca `2099…` -> `92d1…`.
- Yani commit mesajındaki "eşik kayıtları değiştirdi" gerekçesi YALNIZ yarı doğru: eşik gerçekten hash'i değiştiriyor, AMA veri dosyasındaki `_notes` açıklama metni de hash'e giriyor (sonuç doğrulanmış; hangi yoldan girdiği — config'in ham metni mi, sözlük serileştirmesi mi — İNCELENMEDİ).
- Risk [hipotez, nedenin yolu doğrulanmadı]: veri dosyasındaki bir YORUM/NOT cümlesini düzeltmek bile determinizm GOLDEN hash'lerini kırar. Yanlış alarm üretir ve gerçek bir sim değişikliğini gizleyen "hash yenile" alışkanlığına yol açar.
- Yapılmadı (kural): `_notes`'u hash dışı bırakmak GOLDEN değişikliğidir -> technical-director onayı + ayrı commit gerekir. Sim/kanon dosyalarına dokunulmadı.

## Öneri (teknik direktöre)
`_notes` (ve `_` ile başlayan meta anahtarlar) state hash girdisinden çıkarılsın; sonra tüm GOLDEN'lar tek ayrı commit'te bir kez yenilensin. Bu bir mimari/determinizm kararıdır; sahip kararı gerekmez.
