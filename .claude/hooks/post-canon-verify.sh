#!/bin/bash
# PostToolUse: her araç çağrısından sonra design/foundation/ manifest SHA-256'larıyla eşleşiyor mu?
# Eşleşmiyorsa (PreToolUse'un göremediği dolaylı yazma: parçalı yol, base64, betik, komut ikamesi…) izlenen
# dosyalar HEAD'den geri yüklenir, manifest dışı dosyalar bildirilir ve ajan durdurulur. Sağlam kanonda sessizdir (~0.2 sn).
in=$(cat)
# Kök: oturumun gerçek cwd'si (worktree'de $CLAUDE_PROJECT_DIR ana checkout'a işaret edebilir); yoksa $CLAUDE_PROJECT_DIR.
cwd=$(jq -r '.cwd // empty' <<<"$in")
top=$(git -C "${cwd:-${CLAUDE_PROJECT_DIR:-.}}" rev-parse --show-toplevel 2>/dev/null) && cd "$top" || exit 0
[ -x tools/canon-check.sh ] || exit 0
tools/canon-check.sh >/dev/null 2>&1 && exit 0

before=$(tools/canon-check.sh 2>&1 >/dev/null | grep -v '^canon-check:' | head -8)
restored="HAYIR"
if git cat-file -e HEAD:design/foundation/manifest.json 2>/dev/null; then
  git checkout HEAD -- design/foundation >/dev/null 2>&1 && restored="EVET"
fi
# Manifest dışı yeni dosyalar: silme, karantinaya al (kullanıcı verisini sessizce yok etme; geri alınabilir).
quarantined=""
extras=$(tools/canon-check.sh 2>&1 >/dev/null | sed -n 's/^canon-check: manifest dışı dosya: //p')
if [ -n "$extras" ]; then
  q="$(git rev-parse --git-common-dir)/canon-quarantine/$(date +%Y%m%d-%H%M%S)"
  while IFS= read -r f; do
    [ -f "design/foundation/$f" ] || continue
    mkdir -p "$q/$(dirname "$f")" && mv "design/foundation/$f" "$q/$f" && quarantined="$quarantined $f"
  done <<<"$extras"
  [ -n "$quarantined" ] && quarantined="
Manifest dışı dosya(lar) karantinaya alındı ($q):$quarantined"
fi
if tools/canon-check.sh >/dev/null 2>&1; then
  state="Kanon manifestle eşleşiyor (tools/canon-check.sh).$quarantined"
else
  extra=$(tools/canon-check.sh 2>&1 >/dev/null | grep -v '^canon-check:' | head -8)
  state="Kanon HÂLÂ bozuk (geri yükleme: $restored). Kalan sorun:
$extra
Manifest dışı dosyaysa onu sil; değilse kullanıcıya bildir. Kanon için tools/canon-check.sh 11/11 olmadan ilerleme."
fi
reason="design/foundation/ değiştirilemez kanondur; son araç çağrısı onu değiştirdi.
Tespit edilen: ${before:-(ayrıntı yok)}
$state
Bu değişikliği kasıtlı yapmadıysan neden olduğunu bul; kasıtlıysa DURDUR ve kullanıcıya production/QUESTIONS.md üzerinden sor."
jq -n --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
