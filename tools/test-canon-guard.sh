#!/bin/bash
# C-07 savunma testi: design/foundation (değiştirilemez kanon) korumasını doğrudan ve DOLAYLI senaryolarla sınar.
# Gerçek kanona dokunmaz: foundation'ın bir kopyasını geçici bir git deposunda kurar ve komutları orada çalıştırır.
# Katmanlar: (1) PreToolUse guard-canon.sh  (2) PostToolUse post-canon-verify.sh (tespit + HEAD'den geri yükleme)
#            (3) Stop kapısı (stop-verify-gate.sh) bozuk kanonda durdurur.
# Her "boru hattı" senaryosu: pre-hook → (izin verdiyse) komutu çalıştır → post-hook → kanon sağlam mı?
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
guard="$here/.claude/hooks/guard-canon.sh"
post="$here/.claude/hooks/post-canon-verify.sh"
stop="$here/.claude/hooks/stop-verify-gate.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/canon-guard-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0; failed=()

setup() {
  rm -rf "$work/repo" "$work/s.sh"; mkdir -p "$work/repo/tools" "$work/repo/design/specs" "$work/repo/docs"
  cp -R "$here/design/foundation" "$work/repo/design/foundation"
  cp "$here/tools/canon-check.sh" "$work/repo/tools/"
  echo "spec" > "$work/repo/design/specs/a.md"
  ( cd "$work/repo" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm base )
}
bash_in() { jq -cn --arg c "$1" '{command:$c}'; }
pre_decision() { # $1 = tool_input JSON, $2 = tool adı → deny | allow
  local out
  out=$(jq -n --arg t "$2" --argjson i "$1" --arg c "$work/repo" '{tool_name:$t,tool_input:$i,cwd:$c}' | "$guard" 2>/dev/null)
  [ "$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out" 2>/dev/null)" = "deny" ] && echo deny || echo allow
}
run_post() { jq -n --arg c "$work/repo" --arg t "${1:-Bash}" '{tool_name:$t,cwd:$c}' | CLAUDE_PROJECT_DIR="$work/repo" "$post" 2>/dev/null; }
canon_ok() { ( cd "$work/repo" && tools/canon-check.sh >/dev/null 2>&1 ); }
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); failed+=("$1"); printf '  FAIL  %s  (%s)\n' "$1" "$2"; }

# ---- A. Pre-hook birim kararları ---------------------------------------------------
echo "A. PreToolUse kararları (deny beklenen = kanona yazma yolu; allow beklenen = meşru iş)"
setup
decide() { # etiket beklenen araç json
  local got; got=$(pre_decision "$4" "$3")
  [ "$got" = "$2" ] && ok "$1" || bad "$1" "beklenen $2, gelen $got"
}
D() { decide "$1" deny Bash "$(bash_in "$2")"; }
A() { decide "$1" allow Bash "$(bash_in "$2")"; }

for t in Edit Write MultiEdit; do
  decide "$t doğrudan yol" deny $t '{"file_path":"design/foundation/README.md"}'
  decide "$t mutlak yol" deny $t "{\"file_path\":\"$work/repo/design/foundation/README.md\"}"
  decide "$t .. ile dolaylı yol" deny $t '{"file_path":"design/specs/../foundation/README.md"}'
  decide "$t büyük/küçük harf (APFS duyarsız)" deny $t '{"file_path":"Design/Foundation/README.md"}'
  decide "$t çift eğik çizgi ve ./" deny $t '{"file_path":"design//./foundation/README.md"}'
done
decide "NotebookEdit notebook_path" deny NotebookEdit '{"notebook_path":"design/foundation/x.ipynb"}'
ln -s "$work/repo/design/foundation" "$work/repo/link-to-canon"
decide "Write sembolik bağ üzerinden" deny Write '{"file_path":"link-to-canon/README.md"}'
decide "Write design/specs serbest" allow Write '{"file_path":"design/specs/new.md"}'
decide "Edit foundation'a benzer ad serbest" allow Edit '{"file_path":"docs/foundation-notes.md"}'

D "doğrudan yönlendirme"                 'echo x >> design/foundation/README.md'
D "sed -i"                               "sed -i '' 's/a/b/' design/foundation/README.md"
D "rm -rf dizin"                         'rm -rf design/foundation'
D "mv"                                   'mv design/foundation/README.md /tmp/x'
D "cp hedefi kanon"                      'cp /tmp/x design/foundation/README.md'
D "cp -t hedef"                          'cp -t design/foundation /tmp/x'
D "rsync --delete hedef kanon"           'rsync -a --delete /tmp/empty/ design/foundation/'
D "python open(...,'a')"                 "python3 -c \"open('design/foundation/README.md','a').write('x')\""
D "perl -pi"                             "perl -pi -e 's/a/b/' design/foundation/README.md"
D "tee"                                  'echo x | tee -a design/foundation/README.md'
D "truncate"                             'truncate -s 0 design/foundation/README.md'
D "dd of="                               'dd if=/dev/zero of=design/foundation/README.md count=1'
D "chmod"                                'chmod 000 design/foundation/README.md'
D "touch"                                'touch design/foundation/new.md'
D "ln -s"                                'ln -sf /tmp/x design/foundation/README.md'
D "find -delete"                         'find design/foundation -name "*.md" -delete'
D "find -exec"                           'find design/foundation -type f -exec rm {} +'
D "git checkout (başka sürüm)"           'git checkout abc123 -- design/foundation'
D "git rm"                               'git rm -r design/foundation'
D "git restore --source"                 'git restore --source=HEAD~3 design/foundation'
D "git -C ile"                           'git -C design/foundation checkout .'
D "cd + yönlendirme"                     'cd design/foundation && echo x >> README.md'
D "cd + göreli rm"                       'cd design/foundation; rm README.md'
D "cd .. ile kardeş dizin"               'cd design/specs && echo x >> ../foundation/README.md'
D "cd + python (yol anılmıyor)"          "cd design/foundation && python3 -c \"open('README.md','w').write('')\""
D "cd + glob rm"                         'cd design/foundation && rm -f *.md'
D "glob design/f*"                       'rm -rf design/f*'
D "glob */foundation"                    'rm -rf */foundation'
D "glob design/*/README.md"              'echo x >> design/*/README.md'
D "süslü ayraç"                          'rm -r design/{foundation,zzz}'
D "değişkenle yol"                       'd=design; f=foundation; echo x >> $d/$f/README.md'
D "değişken (süslü) ile yol"             'D=design/foundation; rm -rf "${D}"'
D "export ile yol"                       'export P=design/foundation/README.md && echo x >> "$P"'
D "tırnak bölme fo''undation"            "echo x >> design/fo''undation/README.md"
D "ters eğik çizgi foun\\dation"         'echo x >> design/foun\dation/README.md'
D "büyük harf Design/Foundation"         'echo x >> Design/Foundation/README.md'
D "çift eğik çizgi"                      'echo x >> design//foundation/README.md'
D "design/./foundation"                  'echo x >> design/./foundation/README.md'
D "bash -c iç komut"                     "bash -c 'echo x >> design/foundation/README.md'"
D "xargs ile silme"                      'ls design/foundation/*.md | xargs rm'
D "awk çıktı yönlendirme"                "awk 'BEGIN{print \"x\" > \"design/foundation/README.md\"}'"
D "heredoc ile yazma"                    $'cat > design/foundation/README.md <<EOF\nx\nEOF'
D "ln ile yan kapı"                      'ln -s design/foundation /tmp/canon-link'
D "install"                              'install -m 644 /tmp/x design/foundation/README.md'

A "cat okuma"                            'cat design/foundation/README.md'
A "rg okuma"                             'rg -n "Ismeral" design/foundation'
A "ls / head / wc boru hattı"            'ls design/foundation | head -3 | wc -l'
A "find (salt okuma)"                    'find design/foundation -name "*.md" -type f'
A "sed -n okuma"                         "sed -n '1,20p' design/foundation/README.md"
A "git log / diff"                       'git log --oneline -3 -- design/foundation && git diff --stat -- design/foundation'
A "git show"                             'git show HEAD:design/foundation/manifest.json | jq .files'
A "canon-check çağrısı"                  'tools/canon-check.sh'
A "shasum okuma"                         'shasum -a 256 design/foundation/README.md'
A "jq okuma"                             'jq ".files|length" design/foundation/manifest.json'
A "cd + cat"                             'cd design/foundation && cat README.md'
A "cp kanondan dışarı (kaynak)"          'cp design/foundation/README.md /tmp/ref.md'
A "git commit mesajında yol geçer"       'git commit -m "protect design/foundation with a post-hook"'
A "git add"                              'git add -A'
A "design/specs yazma"                   'echo x >> design/specs/a.md'
A "design/specs heredoc"                 $'cat > design/specs/b.md <<EOF\nhello\nEOF'
A "kanon dışı foundation adı"            'echo x >> docs/foundation-notes.md'
A "alakasız komut"                       'tools/verify.sh quick'
A "echo metin (yönlendirme yok)"         'echo "design/foundation is immutable"'
A "stderr yönlendirme /dev/null"         'cat design/foundation/README.md 2>/dev/null >/dev/null'
A "2>&1"                                 'rg x design/foundation 2>&1 | head'

# ---- B. Boru hattı: pre → çalıştır → post → kanon sağlam mı? ----------------------
echo "B. Boru hattı (pre-hook atlatılsa bile post-hook kanonu geri yüklemeli)"
pipeline() { # etiket komut
  setup
  local label="$1" cmd="$2" layer pre out
  pre=$(pre_decision "$(bash_in "$cmd")" Bash)
  if [ "$pre" = deny ]; then layer=pre
  else
    ( cd "$work/repo" && bash -c "$cmd" >/dev/null 2>&1 )
    out=$(run_post Bash)
    if canon_ok && [ "$(jq -r '.decision // ""' <<<"$out" 2>/dev/null)" = "block" ]; then layer=post
    elif canon_ok; then layer=değişmedi
    else layer=BREACH; fi
  fi
  if canon_ok && [ "$layer" != BREACH ]; then ok "$label → katman: $layer"; else bad "$label" "kanon bozuk kaldı"; fi
}
# Yol metin olarak görünmediği için pre-hook'un göremeyeceği dolaylı yazma yolları:
pipeline "python ile parçalı yol"        "python3 -c \"import os; p=os.path.join('de'+'sign','foun'+'dation','README.md'); open(p,'a').write('x')\""
pipeline "base64 ile gizlenmiş yol"      "echo ZGVzaWduL2ZvdW5kYXRpb24vUkVBRE1FLm1k | base64 -D | xargs -I{} sh -c 'echo x >> {}'"
pipeline "komut ikamesi ile yol"         'echo x >> $(printf "design/%s/README.md" "$(echo foundatio)n")'
pipeline "betik dosyası aracılığıyla"    "printf 'echo x >> design/fo%s/README.md\n' undation > ../s.sh; sh ../s.sh"
pipeline "dizin adı keşfedip rm"         "cd design && d=\$(ls | grep -i ^fou); rm -rf \"\$d\""
pipeline "mv ile dizin yer değiştirme"   "mv design/foundation design/foundation.bak && mkdir design/foundation"
pipeline "dosya silme (rm)"              "rm design/foundation/README.md"
pipeline "manifest dışı dosya ekleme"    "echo x > design/foundation/extra.md"
pipeline "chmod + yazma"                 "chmod u+w design/foundation/README.md; echo x >> design/foundation/README.md"
pipeline "find -exec sh"                 "find design -iname 'f*ation' -exec sh -c 'echo x >> {}/README.md' \\;"
pipeline "alakasız komut (kanon sağlam)" "echo hi > design/specs/c.md"

# ---- C. Post-hook ve Stop kapısı ayrıntıları --------------------------------------
echo "C. Post-hook ve Stop kapısı ayrıntıları"
setup; echo "kirli" >> "$work/repo/design/foundation/README.md"
out=$(run_post Edit)
canon_ok && ok "post-hook değişen dosyayı HEAD'den geri yükledi" || bad "post geri yükleme" "kanon hâlâ bozuk"
grep -q "README.md" <<<"$(jq -r '.reason // ""' <<<"$out")" && ok "post-hook neyin geri yüklendiğini söylüyor" || bad "post-hook mesajı" "dosya adı yok"
setup; out=$(run_post Bash)
[ -z "$out" ] && ok "sağlam kanonda post-hook sessiz" || bad "sessizlik" "çıktı: $out"
setup; echo x > "$work/repo/design/foundation/extra.md"; out=$(run_post Write)
canon_ok && ok "manifest dışı yeni dosya kaldırıldı" || bad "manifest dışı dosya" "kaldı"
setup; echo x >> "$work/repo/design/foundation/README.md"
out=$(echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$work/repo" "$stop" 2>/dev/null)
[ "$(jq -r '.decision // ""' <<<"$out")" = "block" ] && ok "Stop kapısı bozuk kanonda durduruyor" || bad "Stop kapısı" "kanon bozukken geçti"

# ---- D. SessionStart hook: hız (20 sn timeout'u) ve eski-taban uyarısı -------------
echo "D. SessionStart hook (C-02 kök nedenleri: timeout ve eski worktree tabanı)"
ss="$here/.claude/hooks/session-start.sh"
t0=$(date +%s); ctx=$(jq -n --arg c "$here" '{cwd:$c}' | "$ss" | jq -r '.hookSpecificOutput.additionalContext'); t1=$(date +%s)
[ $((t1 - t0)) -le 5 ] && ok "gerçek depoda SessionStart $((t1 - t0)) sn (timeout 20 sn; tavan 5 sn)" || bad "SessionStart yavaş" "$((t1 - t0)) sn"
grep -q "Imaro stüdyo durumu" <<<"$ctx" && ok "SessionStart bağlamı üretiyor" || bad "SessionStart bağlamı" "başlık yok"
setup; ( cd "$work/repo" && git branch -m main 2>/dev/null; echo more > design/specs/a.md && git add -A && git -c user.name=t -c user.email=t@t commit -qm second \
  && git checkout -q --detach HEAD~1 )
ctx=$(jq -n --arg c "$work/repo" '{cwd:$c}' | "$ss" | jq -r '.hookSpecificOutput.additionalContext')
grep -q "main'in GERİSİNDE" <<<"$ctx" && ok "main'in gerisindeki HEAD için UYARI üretiyor" || bad "eski taban uyarısı" "uyarı yok"
( cd "$work/repo" && git checkout -q main )
ctx=$(jq -n --arg c "$work/repo" '{cwd:$c}' | "$ss" | jq -r '.hookSpecificOutput.additionalContext')
grep -q "GERİSİNDE" <<<"$ctx" && bad "güncel HEAD" "gereksiz uyarı" || ok "güncel HEAD'de uyarı yok"
ctx=$(CLAUDE_PROJECT_DIR=/nonexistent jq -n --arg c "$work/repo" '{cwd:$c}' | CLAUDE_PROJECT_DIR=/nonexistent "$ss" | jq -r '.hookSpecificOutput.additionalContext')
grep -q "Dal: main" <<<"$ctx" && ok "CLAUDE_PROJECT_DIR ana checkout'u gösterse bile oturum cwd'si kullanılıyor" || bad "cwd önceliği" "yanlış kök"

echo
echo "canon-guard testi: $pass PASS, $fail FAIL"
[ "$fail" -eq 0 ] || { printf ' - %s\n' "${failed[@]}"; exit 1; }
