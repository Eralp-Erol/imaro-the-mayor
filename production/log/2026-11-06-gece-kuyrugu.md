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
- [ ] 1. iPad VSync serisi: geçerli koşular a1, a2, a3. a4 11 sn'de `pause` ile kesildi (geçersiz). Seri betiği `/private/tmp/claude-501/ipad-series2.sh` b1, b2 (`--perf-log-novsync`, `vsync_mode`==0 değilse GEÇERSİZ) koşuyor. a4'ü bir kez yeniden dene. Kesilen koşuyu sayma.
- [ ] 2. Isınma koşusu (sahipsiz yapılabilir): `--demo --perf-log=ipad-isil.json --perf-log-thermal` ~15 dk; ekran açık kalmalı. Pause/kilitlenirse geçersiz yaz.
- [ ] 3. `verify full` (HEAD `cec0b32` B-122 + sonrası), PASS ise `git-wt done` kuyruğuna ekle (exit 141 geçici çözümü: dal adını `$(git rev-parse --git-common-dir)/wt/queue` dosyasına ekle) -> `~/.local/bin/git-wt integrate` -> `ship`.
- [ ] 4. Ölçüm tablosu: T-076 Kanıt bölümü, `production/log/2026-11-06-ipad-olcum.md`, ADR-0010 iPad satırları (hedef vs ölçüm; hedefi geçenle geçmeyeni açık yaz). Sahip gerektiren adımlar (soğuk açılış kronometre, yol onayı etkileşim oturumu, el ile ısınma hissi) "SAHİP BEKLİYOR" diye kalır.
- [ ] 5. GOLDEN_X durum farkını çıkar (B-130 öncesi/sonrası hangi aktör alanı değişti) ve `production/log/`'a yaz.
- [x] 6. Bayat masaüstü perf kayıtlarını (M2-CLOSURE.md, 2026-11-05-perf-serisi) iPad sayılarıyla çapraz not et (yeniden ölçüm gerekmiyorsa yalnız not).
- [ ] 7. M2-CLOSURE.md durum başlığını güncelle (verify full tarihi/sayısı, B-122 çözüldü, iPad sonuçları, kalan sahip maddeleri: Q-041, soğuk açılış, etkileşim, ısınma hissi).

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
