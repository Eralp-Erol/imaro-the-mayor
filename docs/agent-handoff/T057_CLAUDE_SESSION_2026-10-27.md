# T-057 · Claude oturum devri — 2026-10-27 (safe pause)

Önce `T057_CODEX_TO_CLAUDE_2026-10-27.md` ve `production/qa/T-057-technical-review.md` (Karar 4 + uygulama sonucu).

## Yapılan
- STOP kaldırıldı (açık kullanıcı devam talimatı); başka kilit/Godot yoktu; kilit alındı ve çıkışta silindi.
- Teknik karar 4 (opus): palmiye dışı tekil ≤40 tri proxy aranmaz; ilk aday LOD2 = LOD1 bit-eşit alt kümesi, kazanç kapısı (tri ≤172, fragment ≤0,80×LOD1); eşik politikası kural olarak (sayı yok); sözleşme değişiklik listesi §4.5.
- LOD2 çevrimdışı üretim (sonnet, `experiments/t057-lod2/`): P1/P2/P3/P5 PASS, **P4 FAIL** (270 tri, 0,988). Godot/sanat çalıştırılmadı.

## Önemli bulgular
- 30 ana bitki importunda `generate_lods=true`; README otomatik LOD kapalı diyor. Önceki 120/150 m LOD0/LOD1 karelerinin hangi LOD'u çizdiği doğrulanmadı. FAIL'leri açıklamaz ama yeni taban kareleri `false` ile alınmalı.
- Çınar LOD1'in 160/288 tri'si odun; ama §4.2 koruma kuralları yüzünden çıkarılabilir odun yalnız 72 tri.
- 150 m'de çınar 1080p'de ≈136 px, 250 m'de ≈81 px (hesap): "uzağa itince görünmez" varsayımı geçersiz.

## Sıradaki seçenekler (karar bekliyor, başlatılmadı)
1. Ucuz kontrol: çınar LOD0/LOD1 150 m ön/yan/üst ve 250 m, `generate_lods=false` importla ham kareler; art-director. LOD1 kabulse "LOD1 uzat + hücre HLOD" ayrı görev/ADR; değilse sorun LOD1 kalitesi.
2. Göreli lab maliyet kıyası (§4.1-D ölçüm 2): LOD1 N-örnek grid, ort/p95 ms, primitives, draw call; kent/iPad iddiası yok.
Yeni temsil ailesi veya ayar turu önerilmiyor (üç aile art/teknik olarak elendi).

## Değişmeyenler
Ana katalog (91 kayıt), 30 GLB, atlas, LOD0, shell/normal deneyleri, art/blender/vegetation, tools/library, tests/library. T-057 final full ve bağımsız QA/sanat yok; done değil. Push/main yok.
