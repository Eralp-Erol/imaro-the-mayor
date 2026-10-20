#!/bin/bash
# Stop: commit edilmemiş oyun dosyası değişikliği varsa ve son BAŞARILI doğrulamadan sonra kod değiştiyse bir kez durdurur.
in=$(cat)
[ "$(jq -r '.stop_hook_active // false' <<<"$in")" = "true" ] && exit 0
cwd=$(jq -r '.cwd // empty' <<<"$in")
root=$(git -C "${cwd:-${CLAUDE_PROJECT_DIR:-.}}" rev-parse --show-toplevel 2>/dev/null || echo "${CLAUDE_PROJECT_DIR:-.}")
cd "$root" 2>/dev/null || exit 0
# Kanon bütünlüğü her durumda önce: bozuksa (post-hook'u atlatan bir değişiklik) bitirmeye izin verme.
if [ -x tools/canon-check.sh ] && ! tools/canon-check.sh >/dev/null 2>&1; then
  jq -n --arg r "design/foundation/ manifestle eşleşmiyor (değiştirilemez kanon bozulmuş). tools/canon-check.sh çıktısına bak; git checkout HEAD -- design/foundation ile geri yükle ve nedenini kullanıcıya bildir." '{decision:"block",reason:$r}'
  exit 0
fi
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
