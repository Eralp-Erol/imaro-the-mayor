#!/bin/bash
# PreToolUse: design/foundation/ değiştirilemez kanondur. Yazma/düzenleme ve onu değiştiren shell komutlarını reddeder.
in=$(cat)
tool=$(jq -r '.tool_name' <<<"$in")
deny() { jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit)
    p=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$in")
    case "$p" in *design/foundation/*) deny "design/foundation/ değiştirilemez kanondur (design/CANON.md). Değişiklik gerekiyorsa production/QUESTIONS.md üzerinden kullanıcıya sor; onaylı kararlar design/decisions/ içine yazılır.";; esac ;;
  Bash)
    c=$(jq -r '.tool_input.command // ""' <<<"$in")
    if grep -q 'design/foundation' <<<"$c" && grep -Eq '(^|[;&|[:space:]])(rm|mv|truncate|chmod|unlink|tee)[[:space:]]|sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|>[[:space:]]*[^&]*design/foundation|git[[:space:]]+(rm|mv|checkout|restore)' <<<"$c"; then
      deny "Bu komut design/foundation/ (değiştirilemez kanon) içeriğini değiştirebilir. Yalnızca okuma yapılabilir."
    fi ;;
esac
exit 0
