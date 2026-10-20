#!/bin/bash
# SessionStart: üretim checkpoint'ini, açık soruları ve son doğrulama durumunu bağlama ekler.
# Masaüstü uygulaması worktree oturumlarında $CLAUDE_PROJECT_DIR'i ANA checkout'a işaret ettirir (2026-10-20 gözlemi:
# worktree'de hook dosyası olmasa da hook çalıştı). Bu yüzden durum oturumun gerçek cwd'sinden (stdin JSON) okunur.
in=""; [ -t 0 ] || in=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$in" 2>/dev/null)
root=$(git -C "${cwd:-${CLAUDE_PROJECT_DIR:-.}}" rev-parse --show-toplevel 2>/dev/null || echo "${CLAUDE_PROJECT_DIR:-.}")
cd "$root" 2>/dev/null || exit 0
tmp=$(mktemp)
{
  echo "## Imaro stüdyo durumu (otomatik, SessionStart)"
  echo "Dal: $(git branch --show-current 2>/dev/null) · HEAD $(git rev-parse --short HEAD 2>/dev/null) · değişen dosya: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  # Worktree tabanı main'in gerisindeyse (2026-10-20: uygulama worktree'yi eski commit'ten açtı) hemen uyar.
  if git rev-parse -q --verify main >/dev/null 2>&1 && ! git merge-base --is-ancestor main HEAD 2>/dev/null; then
    echo "UYARI: bu dal main'in GERİSİNDE (HEAD $(git rev-parse --short HEAD), main $(git rev-parse --short main)). İşe başlamadan: commit'siz ise 'git merge --ff-only main', değilse yeni worktree aç. Kanon/hook/CLAUDE.md eski olabilir."
  fi
  if [ -f production/STATE.md ]; then
    sed -n '/<!-- CHECKPOINT:BEGIN -->/,/<!-- CHECKPOINT:END -->/p' production/STATE.md | grep -v 'CHECKPOINT:' | head -30
  else
    echo "production/STATE.md yok — plan-milestone ile başlat."
  fi
  if [ -f production/QUESTIONS.md ]; then
    blocked=$(grep -E '^### Q-[0-9]+.*status: blocked' production/QUESTIONS.md | sed 's/^### //')
    open=$(grep -E '^### Q-[0-9]+.*status: open' production/QUESTIONS.md | sed 's/^### //')
    [ -n "$blocked" ] && { echo "ENGELLEYEN sorular (görev durduruyor):"; echo "$blocked" | sed 's/^/- /'; }
    [ -n "$open" ] && { echo "Açık tasarım kararları (engellemiyor, izleniyor):"; echo "$open" | sed 's/^/- /'; }
  fi
  for f in $(ls -t artifacts/verify/*-latest.json 2>/dev/null | head -n1); do
    res=$(jq -r '"\(.mode) \(.result) @ \(.started_at)"' "$f" 2>/dev/null)
    fp=$(jq -r '.fingerprint' "$f" 2>/dev/null)
    now=$([ -x tools/fingerprint.sh ] && tools/fingerprint.sh 2>/dev/null)
    [ "$fp" = "$now" ] && st="kod o zamandan beri aynı" || st="kod o zamandan beri DEĞİŞTİ — yeniden doğrula"
    echo "Son doğrulama: $res ($st)"
  done
  tools/canon-check.sh >/dev/null 2>&1 || echo "UYARI: design/foundation manifestle eşleşmiyor (tools/canon-check.sh)."
  echo "İş akışı: /dev-task, plan-milestone, handoff. Kanon: design/CANON.md. Haiku kullanma."
} > "$tmp" 2>/dev/null
jq -n --rawfile c "$tmp" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
rm -f "$tmp"
