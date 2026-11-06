# Gece iş kuyruğu (2026-11-06) — sahip uyurken ajan durmaz

Sahip talimatı: "Ben sana dur diyene kadar duraklamaman gerekiyor." Her uyanışta (zamanlayıcı ~20 dk) bu dosyayı oku, ilk tamamlanmamış maddeye geç, bitirince `[x]` yap ve kısa not düş. Kuyruk biterse "Kuyruk tükendiğinde" bölümüne geç; ASLA "bekliyorum" diye durma.

## Değişmez kurallar
- Push YOK. Yerel main'e yalnız `git-wt integrate` + `ship` (verify full PASS sonrası).
- Sanat/zevk değişikliği YOK (renk, doku, desen, palet). Sahip kararı gerektiren konuda karar uydurma; `production/QUESTIONS.md`'ye kendi başına anlaşılır, seçenekli soru ekle ve işe devam et.
- Tek Godot kilidi: `mkdir /tmp/imaro-godot.lock` (+ `nice -n 19`); yalnız kendi oluşturduğun kilidi sil, canlı Godot varken asla.
- Raporda doğrulanmış / varsayılan / test edilmemiş ayrı yazılır. Çalıştırmadığına "geçti" deme.
- Oyun dosyası değişince `tools/verify.sh quick` (stop kapısı), teslimde `full`.
- iPad: `IPAD=00008112-001120801A45401E`, `IMARO_IOS_TEAM_ID=UX3VF7M5XM` yalnız ortam değişkeni (repoya yazma). Koşu kitabı: `production/tasks/T-076.md`.

## Sıra
- [~] 1. (ENGELLİ, aşağıya bak) iPad VSync serisi: geçerli koşular a1, a2, a3. a4 11 sn'de `pause` ile kesildi (geçersiz). Seri betiği `/private/tmp/claude-501/ipad-series2.sh` b1, b2 (`--perf-log-novsync`, `vsync_mode`==0 değilse GEÇERSİZ) koşuyor. a4'ü bir kez yeniden dene. Kesilen koşuyu sayma.
- [~] 2. (ENGELLİ: cihaz uygulamayı ~30 sn sonra kesiyor) Isınma koşusu (sahipsiz yapılabilir): `--demo --perf-log=ipad-isil.json --perf-log-thermal` ~15 dk; ekran açık kalmalı. Pause/kilitlenirse geçersiz yaz.
- [x] 3. `verify full` (HEAD `cec0b32` B-122 + sonrası), PASS ise `git-wt done` kuyruğuna ekle (exit 141 geçici çözümü: dal adını `$(git rev-parse --git-common-dir)/wt/queue` dosyasına ekle) -> `~/.local/bin/git-wt integrate` -> `ship`.
- [x] 4. Ölçüm tablosu: T-076 Kanıt bölümü, `production/log/2026-11-06-ipad-olcum.md`, ADR-0010 iPad satırları (hedef vs ölçüm; hedefi geçenle geçmeyeni açık yaz). Sahip gerektiren adımlar (soğuk açılış kronometre, yol onayı etkileşim oturumu, el ile ısınma hissi) "SAHİP BEKLİYOR" diye kalır.
- [~] 5. (KISMİ, aşağıya bak) GOLDEN_X durum farkını çıkar (B-130 öncesi/sonrası hangi aktör alanı değişti) ve `production/log/`'a yaz.
- [x] 6. Bayat masaüstü perf kayıtlarını (M2-CLOSURE.md, 2026-11-05-perf-serisi) iPad sayılarıyla çapraz not et (yeniden ölçüm gerekmiyorsa yalnız not).
- [x] 7. M2-CLOSURE.md durum başlığını güncelle (verify full tarihi/sayısı, B-122 çözüldü, iPad sonuçları, kalan sahip maddeleri: Q-041, soğuk açılış, etkileşim, ısınma hissi).

## Kuyruk tükendiğinde (durmak yok)
- `production/bugs/` içinde AÇIK hata var mı bak; sanat/sahip kararı gerektirmeyeni gerçek çalıştırmayla çöz.
- Test kapsamı boşluğu: yakın zamanda değişen alanlarda (HUD çekmece, güven şeridi, grup tepkisi) olumsuz/uç durum testi ekle.
- B-123 gündem düzeni için seçenekli sahip sorusu hazırla (Q-NNN), kendin karar verme.
- `production/STATE.md` checkpoint satırını güncel tut.

## Notlar
- 2026-11-06 01:2x: B-122 çözüldü (`cec0b32`): çekmece içerik asgarisi araç çubuğunu örtüyordu. verify quick PASS (964), gerçek sahne testleri PASS, pencereli prob PASS. verify full henüz yok.
- Q-041 sahipte (A önerilen).
- 01:4x: madde 4 TASLAK yazıldı (`2026-11-06-ipad-olcum.md`, a1-a3 + ADR karşılaştırması). Eksik: b serisi, ısınma, etkileşim, soğuk açılış. a4 geçersiz (pause). verify full 01:3x başladı (`/private/tmp/claude-501/vf.log`).
- 01:4x: madde 6 yapıldı (M2-CLOSURE iPad çapraz notu). Q-042 (B-123 gündem düğmesi konumu) sahibe hazır. Bekleyen: b1 (01:33 başladı), verify full.
- 02:0x: madde 3 yapıldı: verify full PASS (3140, 0 hata), integrate+ship (yerel main, push yok).
- 02:05: iPad engeli: b1 `reason=pause`, `vsync_mode`=1 (VSync'siz bayrak iOS'ta uygulanmıyor), cihaz konsolu `Audio interruption began` ~30 sn sonra + SIGTERM. Geçerli VSync'li 4 koşu var (a1, a3-eski, a2, a3-yeni). Isınma koşusu (15 dk) aynı kesintiye takılır: sahip iPad'i uyanıkken izleyemeden DENEME (kör yeniden başlatma yok). Sahip sabah: ekranı açık tut/Otomatik Kilit/Rahatsız Etme kontrolü. Madde 4 tablosu güncellendi.
- 02:2x: madde 5 (GOLDEN_X farkı) KISMİ: geçici prob ile B-130 koşusunda eşik değeri (190/250) `game_state.systems` ve `config` içinde ÇIKMADI (bulunan tek 250: council.3 volatility/stance, ilgisiz). Yani hash farkı `ReasonLog` nesnesindeki karar kayıtlarından (theta) geliyor olmalı; bu doğrudan doğrulanmadı (ReasonLog nesne olduğu için aranmadı). Test yorumu (golden_x_council_trust_test.gd) ile tutarlı: kural kapalı referansı yalnız bloc.react eşiğine göre yeniden alındı. Geçici prob silindi, repo temiz.
- 02:3x: madde 4 (ADR-0010 'Ölçülen' notu, T-076 Kanıt) ve 7 (M2-CLOSURE başlığı) tamam. Kuyruk: yalnız engelli iPad işleri (1, 2) ve kısmi 5 kaldı -> 'Kuyruk tükendiğinde' bölümüne geçildi.
- 03:0x: test boşluğu kapandı: `drawer_test.gd` yeni test HudRoot bağlantısını koruyor (olumsuz kontrol: kapalıyken FAIL, açıkken PASS). Gerçek sahne onayı denemesi hatayı yakalamadığı için eklenmedi. verify quick PASS (383).
- 03:1x: kalan maddeler sahip/iPad ekranı bekliyor (1, 2, 5-kısmi). Boş gecede `verify full` yeniden başlatıldı (HEAD 686bab5, `/private/tmp/claude-501/vf.log`); PASS ise `git-wt integrate` + `ship` (yerel main). B-027 (gerekçe günlükten düşüyor) teknik direktör konusu: ADR-0005 §5 saklama ufku; sahip sorusu GEREKMİYOR, TD incelemesi sabaha/ihtiyaca bırakıldı.
