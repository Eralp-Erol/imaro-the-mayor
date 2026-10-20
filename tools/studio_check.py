#!/usr/bin/env python3
"""Stüdyo harness'inin yapılandırma denetimi (tools/verify.sh quick içinde çalışır).

Ajan/skill frontmatter'ı, model politikası (yalnız opus/sonnet, Haiku yok), skill atıfları,
kural dosyaları, hook bağlantıları ve sabitlenmiş MCP sürümleri. Çıkış 0 = sağlam, 1 = sorun var.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLAUDE = os.path.join(ROOT, ".claude")
MODELS = {"opus", "sonnet"}
EFFORTS = {"low", "medium", "high", "xhigh", "max"}
problems = []


def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        problems.append(f"{rel(path)}: frontmatter yok")
        return {}, text
    data, key = {}, None
    for line in m.group(1).splitlines():
        item = re.match(r"^\s+-\s+(.*)$", line)
        if item and key:
            data.setdefault(key, [])
            if isinstance(data[key], list):
                data[key].append(item.group(1).strip().strip('"'))
            continue
        kv = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if kv:
            key, val = kv.group(1), kv.group(2).strip()
            data[key] = [] if val == "" else ("" if val in (">", "|", ">-", "|-") else val)
        elif key and line.startswith("  "):
            prev = data.get(key) or ""
            data[key] = (str(prev) + " " + line.strip()).strip()
    return data, text


def rel(p):
    return os.path.relpath(p, ROOT)


skills_dir = os.path.join(CLAUDE, "skills")
skills = sorted(d for d in os.listdir(skills_dir) if os.path.isfile(os.path.join(skills_dir, d, "SKILL.md")))
for s in skills:
    p = os.path.join(skills_dir, s, "SKILL.md")
    fm, _ = frontmatter(p)
    if fm.get("name") != s:
        problems.append(f"{rel(p)}: name '{fm.get('name')}' klasör adıyla aynı değil")
    desc = str(fm.get("description", ""))
    if not desc:
        problems.append(f"{rel(p)}: description yok")
    elif len(desc) > 1024:
        problems.append(f"{rel(p)}: description {len(desc)} karakter (>1024)")
    if fm.get("model") and fm["model"] not in MODELS | {"inherit"}:
        problems.append(f"{rel(p)}: izin verilmeyen model '{fm['model']}'")

agents_dir = os.path.join(CLAUDE, "agents")
agents = []
for f in sorted(os.listdir(agents_dir)):
    if not f.endswith(".md"):
        continue
    p = os.path.join(agents_dir, f)
    fm, _ = frontmatter(p)
    agents.append(fm.get("name"))
    if fm.get("name") != f[:-3]:
        problems.append(f"{rel(p)}: name dosya adıyla aynı değil")
    if not fm.get("description"):
        problems.append(f"{rel(p)}: description yok")
    if fm.get("model") not in MODELS:
        problems.append(f"{rel(p)}: model açıkça opus/sonnet olmalı (bulunan: {fm.get('model')!r})")
    if fm.get("effort") and fm["effort"] not in EFFORTS:
        problems.append(f"{rel(p)}: geçersiz effort {fm['effort']!r}")
    for sk in [x.strip() for x in str(fm.get("skills", "")).split(",") if x.strip()]:
        if sk not in skills:
            problems.append(f"{rel(p)}: olmayan skill '{sk}'")

# Haiku yasağı: hiçbir yapılandırmada model olarak geçmemeli.
for dirpath, _, files in os.walk(CLAUDE):
    for f in files:
        if f.endswith((".md", ".json")):
            p = os.path.join(dirpath, f)
            for n, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
                if re.search(r"(model\"?\s*[:=]\s*\"?haiku|claude-haiku)", line, re.I):
                    problems.append(f"{rel(p)}:{n}: Haiku model ataması")

# CLAUDE.md yönlendirme tablosundaki ajanlar gerçekten var mı?
claude_md = open(os.path.join(ROOT, "CLAUDE.md"), encoding="utf-8").read()
for name in sorted(set(re.findall(r"`([a-z]+(?:-[a-z]+)+)`", claude_md))):
    if name.endswith(("-director", "-engineer", "-designer", "-artist")) and name not in agents:
        problems.append(f"CLAUDE.md: tanımsız ajan '{name}'")

rules_dir = os.path.join(CLAUDE, "rules")
for f in sorted(os.listdir(rules_dir)):
    fm, _ = frontmatter(os.path.join(rules_dir, f))
    if not fm.get("paths"):
        problems.append(f".claude/rules/{f}: paths frontmatter'ı yok (her oturumda yüklenir)")

settings = json.load(open(os.path.join(CLAUDE, "settings.json"), encoding="utf-8"))
if settings.get("env", {}).get("ANTHROPIC_DEFAULT_HAIKU_MODEL", "").find("sonnet") < 0:
    problems.append("settings.json: ANTHROPIC_DEFAULT_HAIKU_MODEL Sonnet'e yönlendirilmemiş")
for event, groups in settings.get("hooks", {}).items():
    for g in groups:
        for h in g.get("hooks", []):
            script = h.get("command", "").replace('"$CLAUDE_PROJECT_DIR"', ROOT).split()[0]
            if not os.access(script, os.X_OK):
                problems.append(f"settings.json {event}: hook çalıştırılamaz: {script}")

mcp_path = os.path.join(ROOT, ".mcp.json")
if os.path.exists(mcp_path):
    for name, srv in json.load(open(mcp_path, encoding="utf-8")).get("mcpServers", {}).items():
        args = " ".join(srv.get("args", []))
        if "@latest" in args or (srv.get("command") in ("uvx", "npx") and not re.search(r"(==|@)\d", args)):
            problems.append(f".mcp.json: '{name}' sürümü sabitlenmemiş ({args})")

if problems:
    print("studio-check: SORUN")
    print("\n".join("  - " + p for p in problems))
    sys.exit(1)
print(f"studio-check: {len(agents)} ajan, {len(skills)} skill, kurallar/hook/MCP sağlam")
