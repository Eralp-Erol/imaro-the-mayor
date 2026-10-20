# Imaro: The Mayor

Yaşayan bir 3D şehir kurma + siyasi kariyer oyunu: Anderva'nın batısındaki Ismeral metropolünde bir ilçe belediye başkanı olarak başlayıp, imar, kamu yatırımları, ekonomi ve siyasetle şehri dönüştürmek.

**Durum:** stüdyo kurulumu (M0) tamamlandı; oyun üretimi M1 ile başlıyor. Repoda henüz oyun içeriği yok.

| Ne | Nerede |
|---|---|
| Yaratıcı kaynak (değiştirilemez) | `design/foundation/` · öncelik: `design/CANON.md` · izlenebilirlik: `design/REQUIREMENTS.md` |
| Stüdyo düzeni, ajanlar, kapılar | `CLAUDE.md`, `docs/STUDIO.md`, `.claude/` |
| Mimari kararlar | `docs/adr/` |
| Üretim durumu, yol haritası, sorular | `production/STATE.md`, `production/ROADMAP.md`, `production/QUESTIONS.md` |
| Araçlar | `tools/README.md` |

## Hızlı başlangıç
Godot 4.7.2 gerekir (`tools/godot.sh` yolu ve sürümü doğrular; başka konumdaysa `IMARO_GODOT` ile verin).

```bash
tools/verify.sh quick
```

Claude Code ile: `/dev-task` sıradaki görevi uçtan uca yürütür; `handoff` oturumu kaydeder.
