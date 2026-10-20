#!/bin/bash
# Stop: commit edilmemiş oyun dosyası değişikliği varsa ve son BAŞARILI doğrulamadan sonra kod değiştiyse bir kez durdurur.
in=$(cat)
[ "$(jq -r '.stop_hook_active // false' <<<"$in")" = "true" ] && exit 0
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
cd "$root" 2>/dev/null || exit 0
[ -x tools/fingerprint.sh ] || exit 0
paths=""; for p in src scenes tests addons assets project.godot; do [ -e "$p" ] && paths="$paths $p"; done
[ -z "$paths" ] && exit 0
changed=$(git status --porcelain -- $paths 2>/dev/null | head -5)
[ -z "$changed" ] && exit 0
now=$(tools/fingerprint.sh 2>/dev/null) || exit 0
for m in quick full; do
  f="artifacts/verify/$m-latest.json"
  [ -f "$f" ] && [ "$(jq -r '.result' "$f")" = "pass" ] && [ "$(jq -r '.fingerprint' "$f")" = "$now" ] && exit 0
done
reason="Oyun dosyaları son başarılı doğrulamadan sonra değişti:
$changed
Tamamlandı/çalışıyor demeden önce tools/verify.sh quick çalıştır (sunuma duyarlıysa visual-gate). Doğrulama şimdi mümkün değilse yanıtında değişikliğin DOĞRULANMADIĞINI açıkça yaz."
jq -n --arg r "$reason" '{decision:"block",reason:$r}'
