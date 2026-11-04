# M2 kapanış listesi (taslak) — 2026-11-04

M2 = "İlk nedensel döngü (dikey dilim)", `production/ROADMAP.md`. Ölçüt: F03 "Oyun hissi için doğrulanması gereken kabul ölçütleri" (7 madde) + M2 satırındaki ek koşullar. Bu dosya KAPANIŞ DEĞİLDİR; neyin kanıtlı, neyin açık olduğunu ayırır. Kanıt yoksa "kanıt aranmadı" yazılır, "geçti" denmez. Karar yetkisi: sahip + director'lar.

## F03 ölçütleri

| # | Ölçüt | Durum | Dayanak / eksik |
|---|---|---|---|
| 1 | Mevcut yerleşim dokusu ve topografya hissedilir (boş grid değil) | KISMEN | T0 üreteci ve sanat kapıları kayıtlı (T-005, T-056..T-059 QA). Sahip görsel kabulü ve M1 açık ölçütleri (T-012 K8 LOD farkı %9,5 > %5, üçgen ~1,27M > 900k) kapanmadı. |
| 2 | Yol/imar/kamu alanı kararı fiziksel 3D dünyada uygulanır | KANITLI (masaüstü) | Çalışan döngü: yol çiz → kamulaştır → imar; pencereli QA turları 2-3. Yeni "belediye arazisini imara aç" girişi pencerede henüz görülmedi (QA turu sürüyor). |
| 3 | Yatırımcı/hane yanıtı kararla ilişkili ama otomatik değil | KANITLI | T-040 bağımsız QA 3. tur PASS; gerekçeli ret/kabul; CAN-03 testleri. |
| 4 | Nüfus/iş/ulaşım/bütçe değişimi anlamlı ve görünür | KISMEN | Değişim akışı ve bütçe göstergesi var. Kare/perf kanıtı sakin makinede tam değil. Q-003 para birimi açık ("gösterge"). Kalabalık/yoğunluk görsel kabulü sahipte. |
| 5 | En az bir karar gerçek siyasi/toplumsal tepki üretir | KANITLI (sim) / KISMEN (görüş) | Yol/yıkım tepkisi, gündem kartı, meclis var. Meclis RED yolu artık testle KANITLI (`tests/game/council_red_scenario_test.gd`: yeşil imar + dolu altyapı + ≥10 parsel, gürültüyle ~%5-8; UI/olay akışı hatasız); D-020: RED nadir kalsın. Pencereli RED karesi alınmadı. |
| 6 | Aynı alan farklı zoom'larda aynı dünya | KISMEN | Çok ölçekli kamera (T-003) var. Zoom geçişlerinde LOD farkı ölçütü açık (bkz. 1). |
| 7 | Örnek ilçe zorunlu başlangıç yeri olmaz | KISMEN | Sim yarısı KANITLI (başsız test, gerçek Ismeral, 6 ilçe + 2. tohum: yol→imar→yatırımcı döngüsü, CAN-03, determinizm; `tests/game/m2_start_district_test.gd`). D-020: sahip "Hep D2'den başlasın" dedi — B-026 (yol yetkisi yalnız D2) karar gereği kapandı; ölçüt 7 D2 başlangıcıyla KISMEN. Pencereli kanıt yok. |

## M2 satırındaki ek koşullar
- **iPad'de aynı dilim cihazda oynanır (dokunmatik profil, ölçüm):** KISMEN. 2026-11-04 fiziksel iPad Pro 12,9" (6. nesil) üzerinde debug sürüm kuruldu ve oyun açıldı; sahip "istenildiği gibi çalışıyor" dedi (bildirim, ölçüm değil). Ölçüm (kare süresi, dokunma hassasiyeti, ısınma) YOK. Ayrıntı: `production/log/2026-11-04-ipad-gercek-cihaz.md`.
- **Masaüstü profiliyle kabul:** kısmen; sahip kabulü yok.
- **Performans:** kare sıçramaları ölçüldü (en kötü 117,92 ms; ~1,16 s tekrarlanmadı) ama sakin makinede ikinci seri ve bütçe kararı yok.

## Kapanış için yapılacaklar (sırayla)
1. İki ilçe/başka tohumla başlatma: TEST YAZILDI (sim yarısı geçti). Başlangıç ilçesi: D-020 (hep D2) ile karara bağlandı.
2. Pencereli QA turu: yeni imar akışı (sürüyor), eski yolu yıkma ekranı (sürüyor), sonuç kareleri.
3. Meclis RED: senaryo bulundu ve test yazıldı (`production/log/2026-11-04-meclis-red-senaryosu.md`). Sahip kararı D-020: RED nadir kalsın. Kalan: pencereli RED karesi (isteğe bağlı).
4. Sakin makinede perf serisi ve kare bütçesi hedefi (teknik direktör hedefi belirler).
5. iPad: AÇILIŞ KANITLI (sahip bildirimi). Kalan: cihazda kare süresi/dokunma ölçümü, release sürüm, gerçek ikon ve iOS ana sahne düzeni.
6. M1'den taşınan görsel ölçütler (LOD farkı, üçgen bütçesi): art-director + technical-director kararı.
7. Üç yönetici incelemesi (design / art / technical director) + `verify full` + kapanış kaydı.

## Sahip kararları (M2'yi engellemez, ama kapanış kartında sorulur)
Q-003 para birimi · Q-015 Ismeral coğrafya onayı · Q-025 halk neye tepki versin · Q-026 araç/yaya yoğunluğu (Kart D) · Q-014/Q-028 meclis eşiği (Kart B) · Q-018 sanat kütüphanesi şablonları · Q-027/Q-029 gündem kartı adı ve tepki sertliği · R1-R3 yeniden iskân varsayımları · T-065 Aşama 2.

## Doğrulanmadı
Bu liste dosya okumasından derlendi; testler koşturulmadı. Durum sütunundaki "KANITLI" ifadeleri ilgili QA kayıtlarına dayanır, bu oturumda yeniden doğrulanmadı.
