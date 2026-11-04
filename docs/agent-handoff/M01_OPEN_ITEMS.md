# M01 açık kayıtlar (2026-10-21) — yeni geliştirmeyi DURDURMAZ

Kullanıcı talimatı (2026-10-21): bekleyen manuel kabuller M2 geliştirmesini engellemez. Aşağıdakiler **kullanıcı/cihaz** kabulleridir;
hiçbiri kullanıcı adına verilmedi, `docs/agent-handoff/M01_MANUAL_SIGNOFF.json` OLUŞTURULMADI (doğrulayıcı bunları MANUAL sayar).

## Kullanıcı / cihaz onayı bekleyenler
| Kalem | Ne gerekiyor | Not |
|---|---|---|
| Q-015 Ismeral coğrafya yaratıcı onayı | T-028 etiketli topoloji haritasını (`scenes/dev/topology_map.tscn`; `tools/capture.sh topo …`) inceleyip karar | Kalıcı koordinat sabitlenmedi; her şey `WorldData`'dan runtime türetilir |
| T-008 iPad cihaz duman testi | iPad Pro'da dokunmatik profil, iPadOS export zinciri | Cihaz gerekir; simülatör değil |
| T-009 çapraz platform determinizm | İkinci platformda `StateHash` tekrar oynatma | Altyapı var, ikinci cihaz çalıştırması yok |
| T-010 renderer/kalite profili karşılaştırması | GL Compatibility ↔ alternatif | Çalıştırılmadı |
| T-007 Windows .exe çalıştırma | Windows cihazında çalıştırma testi | Export hattı var, çalıştırma yok |
| T-012 / VIS-04 art-director görsel kapısı | Gerçek T0 verisiyle yapı render'ının sanat onayı | K8 sayısal ölçüt karşılandı; sanat kararı kullanıcı/art-director'da |
| Kullanıcının demo incelemesi | `tools/godot.sh --path . res://scenes/game/playable.tscn -- --preset=district:D1 --demo` | 2026-10-21'de kullanıcı denedi → girdi hatası bulundu ve düzeltildi (`df81764`); yeniden inceleme açık |

## Bilinen, kapanmamış teknik durumlar (dürüst kayıt)
- **Metro P95, karar rejiminde:** smoke `--demo` en hızlı sim hızında (16 tick/sn) koşar. Sim ~tick 38'den sonra günde 60 yatırımcı kararı verir
  (`max_reviews_per_tick`); bu ana thread'de ~13–15 ms. Bu rejime denk gelen pencerede (ısınma ≥ 500 kare) metro P95 ≈ 20–23 ms (hedef 16,6), ortalama
  hedefte (≈4,5–5 ms). Varsayılan pencerede (ısınma 120) smoke SMOKE_OK: ort. 3,52 / P95 7,39. Mimari seçenekler (worker thread'te sim, gün çalışmasını kareye bölme,
  `max_reviews_per_tick` denge verisi) kullanıcı/tasarım kararı bekler; eşik gevşetilmedi.
- **K8 LOD0↔LOD1 farkı:** izole koşuda deterministik %2,5851 (3/3 aynı piksel sayısı); bir smoke koşusunda %40,03 görüldü; sonraki smoke koşusunda ve izole koşularda tekrarlanmadı (%2,5851), nedeni KANITLANMADI.
- **Pencereli yakalama takılması:** iki kez (biri değişikliklerden önce) `capture.sh` saatlerce takıldı. `tools/capture.sh` artık zaman aşımlı (420 sn) + bir yeniden denemeli.
- **Kota geçişi (Claude↔Codex):** `agent_handover.py` içinde stub testleriyle doğrulandı, gerçek bir kota olayında hiç tetiklenmedi.
