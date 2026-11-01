# Codex'e devir — 2026-11-01

Bu dosya Claude Code'dan Codex'e geçiş içindir. Önce `AGENTS.md` ve `CLAUDE.md`, sonra bu dosya, sonra `production/STATE.md` (CHECKPOINT).

## Nereden başlanır
- Depo: `/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb` (git worktree). Uzak: `https://github.com/Eralp-Erol/imaro-the-mayor.git`.
- Dal: `agent/handover-imaro-m01-349562fb`, HEAD `c3760b3`. `main` bu dalın atasıdır; dal main'den 315 commit ilerde.
- Bu dal **uzakta (origin) YOK, push edilmedi**. Uzakta yalnız `main` ve `dev/m1-parallel` var. Codex bulutta çalışacaksa önce sahibin push onayı gerekir; yerel çalışacaksa bu worktree'yi (veya ondan yeni worktree) kullan.
- Godot 4.7.2 ikilisi git'te değildir: `/Users/eralperol/Documents/Projects/imaro-the-mayor/.tools/Godot.app/Contents/MacOS/Godot`. `export IMARO_GODOT=<bu yol>`; `tools/godot.sh` sürümü doğrular.
- Kirli ağaç: yalnız izlenmeyen `artifacts/library/` ve `tmp/` (bilerek takipsiz kalır).

## Durum (doğrulanmış / varsayılan / test edilmemiş)
- DOĞRULANMIŞ: `tools/verify.sh full` PASS @ `c175c54` (2892 test, 0 hata, canon-guard 105, smoke 180 kare, gdlint temiz). Sonraki commit `c3760b3` yalnız STATE + `artifacts/verify/full-latest.json`. GOLDEN_A/B ve GOLDEN_X bit-bit aynı.
- Bu oturumda biten: yol geri al / yıkım (maliyetli, ek onay, parsel kimlikleri korunur), yıkım halk tepkisi, merkez 2x / çeper 0,8x kalabalık, yeniden iskân politikası (T-065 Aşama 1, sözleşme 1.7), yıkılan şeride yeniden yol, B-009..B-020 hataları.
- ASSUMED (sahip onayı yok, veride ayarlanır): kalan tepki %20, kısmi ev %60, yıkım maliyeti 15 birim/m, merkez/çeper eşikleri 1500/7000, Politikalar paneli Yönetim modunda.
- TEST EDİLMEDİ: fiziksel iPad; meclis RED ekranı gerçek oyunda; gerçek Ismeral'de boş ev yok (yeniden iskân "taşındı" yolu yalnız enjekte evle görüldü); açık politikayla GOLDEN_R; `--demo` kare sıçramaları (125-140 ms, tick ~835'te ~1,16 s yol yeniden kurma) sakin makinede ölçülmedi; kare maliyeti iddiaları.
- İNCELEME İSTEYEN: B-020 düzeltmesi (`src/sim/public_works/public_work_demolish_handler.gd` `_dry_run`) sim kodundan `WorldNetwork.graph_version` ve `change_log` alanlarını geri yazar. Sürüme bağlı önbelleklerde (ör. `public_works_context.gd` memo, `road_draw_tool.gd` verdict) bayat veri riski kanıtlanmadı. Dünya mühendisi bakmalı.

## Açık sahip kararları (UYDURMA; sahibe düz Türkçe, seçenekli kart)
`production/QUESTIONS.md` ve `production/MORNING-2026-11-02.md`: G1/Q-030 geri al süresi (B-013), Y1/Q-031 yıkılan şerit, R1-R3 yeniden iskân varsayımları, E1/Q-032 evsiz aileler, K1/Q-033 yıkım maliyeti (yıkmak 1,995 > yapmak 1,300), P1/Q-034 Politikalar paneli yeri, T-065 Aşama 2 (hane sınıfı verisi; GOLDEN bilinçli yenilenir, teknik direktör + sahip onayı), Q-003 para birimi.

## Sonraki teknik işler (karar gerektirmeyen)
1. `--demo` takılmalarını sakin makinede yeniden ölç; yol yeniden kurma ~1 s kalırsa godot-engineer işi olarak ayır.
2. B-016 (2/3646 döngülü taslak), çok noktalı yol aracından önce.
3. Yükleme anı parsel denetimi sertleştirme (`public_works_context.gd` ~190-191).
4. Yol vurgusu/numarası haritada; dar bildirim sütunu kaydırma (tasarım kararı).

## Değişmez kurallar (kısa)
- Push yok, main'e birleştirme yok (sahip onayı olmadan). Geri alınamaz git işlemi yok.
- `design/foundation/` ve `data/politics/blocs.json` düzenlenmez (hook korur). `artifacts/library/` ve `tmp/` takipsiz kalır.
- CAN-03: oyuncu özel bina spawn edemez. HUD yalnız gerçek sim verisi. Sim deterministik, render'dan ayrı (GOLDEN_A/B `tests/sim/m2_query_test.gd`, GOLDEN_X `tests/sim/public_works/golden_expropriation_undo_test.gd`).
- Satır üst sınırları: `playable.gd` tam 1000 (dokunma), `economy_system.gd` ~998/1000.
- Aynı anda tek Godot; yalnız kendi PID'ini öldür (`pkill -f Godot` yok). Bir doğrulama sürerken ağacı değiştirme.
- `verify quick` KISMİDİR; "tam doğrulandı" deme. Çalıştırmadığına "geçti" deme. Rapor: doğrulanmış / varsayılan / test edilmemiş ayrı.
- Sahip teknik değil: mesaj 3-5 satır, düz Türkçe, en fazla 2-3 karar, öneri ilk. Kararı yalnız sahibin kendi sözleriyle `design/decisions/D-NNN`'e yaz.
- Commit mesajı sonu: model attribution satırı (Claude akışında `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`); Codex kendi attribution'ını kullanır.
- Komutlar: `tools/verify.sh quick|full`, `tools/godot.sh`, gdlint: `uvx --from gdtoolkit==4.5.0 gdlint`. Demo: `scenes/game/playable.tscn --demo`.
