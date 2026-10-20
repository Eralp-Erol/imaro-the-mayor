#!/usr/bin/env python3
"""PreToolUse koruması: design/foundation/ değiştirilemez kanondur.

Girdi: stdin'de hook JSON'u. Çıktı: deny gerekiyorsa permissionDecision=deny JSON'u, yoksa boş.

Dosya araçları (Edit/Write/MultiEdit/NotebookEdit): yol normalleştirilir (.., ./, //, büyük/küçük harf,
sembolik bağ) ve kanon dizinine düşerse reddedilir.

Bash: komut shlex ile ayrıştırılır; segment başına şunlar izlenir: cd/pushd ile sanal çalışma dizini,
NAME=değer atamaları ($NAME ikamesi), glob + süslü ayraç genişletmesi, yönlendirme hedefleri.
Bir segment kanona dokunuyorsa (yol çözümü, glob, "design/foundation" metni, kanon içinde çalışma dizini)
VE salt-okunur değilse reddedilir. Bu katman en iyi çabadır; yolun metinde görünmediği durumlar
(parçalı dize, base64, komut ikamesi) post-canon-verify.sh tarafından yakalanıp geri yüklenir.
"""
import glob
import json
import os
import re
import shlex
import sys
import unicodedata

CANON = ["design", "foundation"]
SEPARATORS = {";", "&&", "||", "|", "&", "|&", "(", ")", ";;"}
INTERPRETERS = {"python", "python3", "perl", "ruby", "node", "php", "osascript", "bash", "sh", "zsh", "eval", "awk", "gawk"}
WRAPPERS = {"sudo", "command", "builtin", "exec", "env", "time", "nohup", "nice", "xargs"}
READONLY = {
    "cat", "ls", "head", "tail", "wc", "grep", "egrep", "fgrep", "rg", "jq", "shasum", "sha256sum", "md5", "diff",
    "cmp", "stat", "file", "pwd", "echo", "printf", "test", "[", "true", "false", "basename", "dirname",
    "realpath", "readlink", "du", "tree", "cd", "pushd", "popd", "export", "unset", "type", "which", "date",
    "nl", "od", "cut", "tr", "column", "less", "more", "bat", "wait", "set", "local", "declare",
}
GIT_MUTATING = {
    "checkout", "restore", "reset", "clean", "stash", "merge", "rebase", "rm", "mv", "apply", "am", "cherry-pick",
    "pull", "revert", "switch", "sparse-checkout", "read-tree", "submodule", "filter-branch", "worktree", "bisect",
}
PIPE_WRITERS = {"xargs", "tee", "sh", "bash", "zsh", "dd", "sponge", "parallel"}
FIND_WRITERS = {"-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprint0", "-fprintf", "-fls"}
SAFE_REDIRECT_TARGETS = {"/dev/null", "1", "2", "&1", "&2", "-"}
TEXT_MENTION = re.compile(r"design\s*/+\s*foundation")


def norm(s):
    return unicodedata.normalize("NFC", s).casefold()


def in_canon_path(p):
    parts = [x for x in norm(p).split("/") if x not in ("", ".")]
    return any(parts[i:i + 2] == CANON for i in range(len(parts) - 1))


def resolve(tok, cwd):
    tok = os.path.expanduser(tok)
    full = tok if os.path.isabs(tok) else os.path.join(cwd, tok)
    return [os.path.normpath(full), os.path.realpath(full)]


def path_in_canon(tok, cwd):
    return any(in_canon_path(r) for r in resolve(tok, cwd))


def expand_braces(s):
    m = re.search(r"\{([^{}]*)\}", s)
    if not m or "," not in m.group(1):
        return [s]
    out = []
    for alt in m.group(1).split(","):
        out.extend(expand_braces(s[:m.start()] + alt + s[m.end():]))
    return out


def glob_touches_canon(tok, cwd):
    if not re.search(r"[*?\[{]", tok):
        return False
    for pat in expand_braces(os.path.expanduser(tok)):
        if in_canon_path(pat):
            return True
        full = pat if os.path.isabs(pat) else os.path.join(cwd, pat)
        try:
            hits = glob.glob(full, recursive=True)
        except Exception:
            hits = []
        if any(path_in_canon(h, cwd) for h in hits):
            return True
    return False


def touches(tok, cwd, head):
    t = norm(tok)
    if TEXT_MENTION.search(t):
        return True
    if "foundation" in t and head in INTERPRETERS:
        return True
    return path_in_canon(tok, cwd) or glob_touches_canon(tok, cwd)


def is_assignment(tok):
    return re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok) is not None


def substitute(tok, env):
    def repl(m):
        name = m.group(1) or m.group(2)
        return env.get(name, m.group(0))
    return re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)", repl, tok)


def tokenize(cmd):
    lex = shlex.shlex(cmd.replace("\r", " ").replace("\n", " ; "), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def split_segments(tokens):
    """[(segment, ayraç)] — ayraç, bu segmentten ÖNCEKİ operatör (';', '|', '&&' …)."""
    segs, cur, sep = [], [], ""
    for t in tokens:
        if t in SEPARATORS or re.fullmatch(r"[;&|()]+", t):
            if cur:
                segs.append((cur, sep))
            cur, sep = [], t
        else:
            cur.append(t)
    if cur:
        segs.append((cur, sep))
    return segs


def split_redirects(seg):
    """(argümanlar, yönlendirme hedefleri, güvensiz_yönlendirme_var_mı)"""
    args, targets, unsafe = [], [], False
    i = 0
    while i < len(seg):
        t = seg[i]
        if re.fullmatch(r"[0-9]*[<>]+[&|]?", t) or re.fullmatch(r"&>>?", t):
            op = t
            nxt = seg[i + 1] if i + 1 < len(seg) else ""
            if ">" in op or op.startswith("&>"):
                if not (nxt in SAFE_REDIRECT_TARGETS):
                    unsafe = True
                    targets.append(nxt)
            elif op.endswith("<") and op.count("<") >= 2:  # heredoc/herestring: sonraki jeton ayraç/metin
                pass
            i += 2
            continue
        if re.match(r"^[0-9]*>{1,2}[^&]", t) and not re.match(r"^[0-9]*>&", t):
            unsafe = True
            targets.append(re.sub(r"^[0-9]*>{1,2}", "", t))
            i += 1
            continue
        args.append(t)
        i += 1
    return args, targets, unsafe


def git_sub(args):
    i = 1
    while i < len(args):
        a = args[i]
        if a in ("-C", "-c", "--git-dir", "--work-tree", "--namespace"):
            i += 2
        elif a.startswith("-"):
            i += 1
        else:
            return a, args[i + 1:]
    return "", []


def drop_commit_messages(sub_args):
    out, skip = [], False
    for a in sub_args:
        if skip:
            skip = False
            continue
        if a in ("-m", "-F", "--message", "--file", "-t"):
            skip = True
            continue
        if a.startswith("--message=") or a.startswith("--file="):
            continue
        if re.fullmatch(r"-[a-zA-Z]*m", a):
            skip = True
            continue
        out.append(a)
    return out


def segment_readonly(head, args, unsafe_redirect):
    if unsafe_redirect:
        return False
    base = os.path.basename(head)
    if base in READONLY:
        return True
    rest = args[1:]
    if base == "find":
        return not any(a in FIND_WRITERS for a in rest)
    if base == "sed":
        scripts = [a for a in rest if not a.startswith("-")]
        flags = [a for a in rest if a.startswith("-")]
        return (
            "-n" in flags
            and not any(f.startswith("-i") or f == "--in-place" for f in flags)
            and all(re.fullmatch(r"[0-9$,]*p", s) or os.path.exists(s) for s in scripts)
        )
    if base == "rg":
        return not any(a.startswith("--pre") for a in rest)
    if base == "git":
        sub, sub_args = git_sub(args)
        if sub in GIT_MUTATING:
            return False
        return not any(a.startswith("--output") for a in sub_args)
    if base in ("canon-check.sh", "test-canon-guard.sh"):
        return True
    return False


def cp_like_dest(base, args):
    """cp/rsync: yalnız HEDEF kanona düşüyorsa yazma sayılır (kaynak olarak okumak serbest)."""
    rest = [a for a in args[1:]]
    for i, a in enumerate(rest):
        if a in ("-t", "--target-directory") and i + 1 < len(rest):
            return rest[i + 1]
        if a.startswith("--target-directory="):
            return a.split("=", 1)[1]
    pos = [a for a in rest if not a.startswith("-")]
    return pos[-1] if pos else None


def check_bash(cmd, cwd):
    flat = re.sub(r"[\\'\"]", "", norm(cmd))
    if "foundation" not in flat and not re.search(r"[*?\[{]|\$|`|cd\s|pushd|\.\.", flat):
        return None
    tokens = tokenize(cmd)
    env, vcwd = {}, cwd
    prev_mention = False
    for seg, sep in split_segments(tokens):
        piped_canon = prev_mention and sep in ("|", "|&")
        prev_mention = False
        args, targets, unsafe = split_redirects(seg)
        # değişken atamaları (önek veya tek başına)
        while args and is_assignment(args[0]):
            k, v = args[0].split("=", 1)
            env[k] = substitute(v, env)
            args = args[1:]
        if args and args[0] == "export":
            for a in args[1:]:
                if is_assignment(a):
                    k, v = a.split("=", 1)
                    env[k] = substitute(v, env)
        while args and os.path.basename(args[0]) in WRAPPERS and os.path.basename(args[0]) != "xargs":
            args = [a for a in args[1:] if not (a.startswith("-") or is_assignment(a))] if len(args) > 1 else []
        if not args:
            continue
        args = [substitute(a, env) for a in args]
        targets = [substitute(t, env) for t in targets]
        head = args[0]
        base = os.path.basename(head)
        body = args[1:]
        if base == "git":
            sub, sub_args = git_sub(args)
            if sub in ("commit", "tag", "notes"):
                body = [args[0]] + [a for a in args[1:] if a in ("-C", "-c")] + [sub] + drop_commit_messages(sub_args)
                body = body[1:]
        if base in ("cd", "pushd"):
            if body and not body[0].startswith("-"):
                vcwd = resolve(body[0], vcwd)[0]
            continue
        in_canon_cwd = in_canon_path(vcwd) or in_canon_path(os.path.realpath(vcwd))
        if base in ("cp", "rsync", "scp"):
            dest = cp_like_dest(base, args)
            mention = in_canon_cwd or (dest is not None and touches(dest, vcwd, base)) \
                or any(touches(t, vcwd, base) for t in targets)
            if base == "rsync" and "--delete" in " ".join(body):
                mention = mention or any(touches(a, vcwd, base) for a in body)
        else:
            mention = in_canon_cwd or any(touches(a, vcwd, base) for a in body) \
                or any(touches(t, vcwd, base) for t in targets) or touches(head, vcwd, base)
        prev_mention = mention
        if piped_canon and base in PIPE_WRITERS:
            return "Kanon içeriği (design/foundation/) bir yazma/yürütme komutuna borulanıyor. Yalnızca okuma yapılabilir."
        if mention and not segment_readonly(head, [head] + body, unsafe):
            return "Bu komut design/foundation/ (değiştirilemez kanon) içeriğini değiştirebilir. Yalnızca okuma yapılabilir."
    return None


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                             "permissionDecisionReason": reason}}))
    sys.exit(0)


def main():
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    ti = data.get("tool_input") or {}
    cwd = data.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    msg_file = ("design/foundation/ değiştirilemez kanondur (design/CANON.md). Değişiklik gerekiyorsa "
                "production/QUESTIONS.md üzerinden kullanıcıya sor; onaylı kararlar design/decisions/ içine yazılır.")
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        for key in ("file_path", "notebook_path", "path"):
            p = ti.get(key)
            if p and path_in_canon(p, cwd):
                deny(msg_file)
        for e in ti.get("edits", []) or []:
            p = e.get("file_path") if isinstance(e, dict) else None
            if p and path_in_canon(p, cwd):
                deny(msg_file)
    elif tool == "Bash":
        cmd = ti.get("command", "")
        try:
            reason = check_bash(cmd, cwd)
        except Exception:
            # ayrıştırılamayan komut: kanondan söz ediyorsa kapalı davran (fail-closed), değilse geç
            reason = "Komut ayrıştırılamadı ve design/foundation'dan söz ediyor; güvenli biçimde yeniden yaz." \
                if "foundation" in norm(cmd) else None
        if reason:
            deny(reason)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)  # hook arızası işi kilitlemesin; post-canon-verify.sh ve Stop kapısı arkada
