#!/usr/bin/env python3
"""Imaro: The Mayor — M01 (ROADMAP "M1") kabul doğrulayıcısı.

Agent Handover'ın işin bitip bitmediğini anlaması için. NESNEL kontroller koşar; manuel/kullanıcı onayı gereken
koşulları ayrıca raporlar. Bir DONE/işaret dosyası varlığı ASLA başarı sayılmaz.

Çıkış kodu:
  0  M01 doğrulandı: tüm otomatik kontroller PASS, tüm manuel onaylar kayıtlı (docs/agent-handoff/M01_MANUAL_SIGNOFF.json)
  1  en az bir otomatik kontrol FAIL (iş bitmemiş / bozuk)
  2  otomatik kontroller PASS ama manuel/kullanıcı onayı eksik (M01 henüz doğrulanmadı)
  3  kullanım/ortam hatası (repo kökü, godot yok)
  4  koşu eksik: bazı kontroller atlandı (--quick vb.), M01 doğrulanmış sayılmaz
Öncelik: 3 > 1 > 4 > 2 > 0.

Kullanım:
  python3 scripts/verify_imaro_m01.py            # AUTO (Agent Handover bunu argümansız çağırır): ağır adımlar için aynı HEAD + temiz ağaçta
                                                 #   yapılmış tam koşunun önbelleğini kullanır, yoksa tam koşar (dakikalar; handover --verify-timeout >=1800)
  python3 scripts/verify_imaro_m01.py --full     # önbelleği yok say, ağır adımları (Godot import + GdUnit4 tam + gdlint + smoke) yeniden koş
  python3 scripts/verify_imaro_m01.py --quick    # ağır adımları atlar (exit 4'ten iyisi çıkmaz)
  python3 scripts/verify_imaro_m01.py --list     # kontrol listesini yazar
Rapor: artifacts/verify/m01-report.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PASS, FAIL, MANUAL, SKIP = "PASS", "FAIL", "MANUAL", "SKIP"

# M01 = ROADMAP M1 teknik kapanış + T-030 entegre demo. Kaynak: production/ROADMAP.md, production/LANES.md, T-030.md.
REQUIRED_TASKS = ["T-001", "T-002", "T-003", "T-004", "T-005", "T-007", "T-011", "T-012", "T-013", "T-015", "T-016",
                  "T-017", "T-018", "T-019", "T-021", "T-022", "T-023", "T-025", "T-027", "T-029", "T-030", "T-006"]
REQUIRED_FILES = [
    "project.godot", "CLAUDE.md", "design/CANON.md", "design/REQUIREMENTS.md", "production/ROADMAP.md",
    "scenes/game/playable.tscn", "src/game/playable.gd", "tools/smoke_playable.sh",
    "scenes/dev/world_preview.tscn", "scenes/dev/kit_lab.tscn", "scenes/dev/ui_lab.tscn", "scenes/dev/topology_map.tscn",
    "src/world/world_generator.gd", "src/world/network/world_network.gd", "src/world/settlement/t0_settlement.gd",
    "src/view/terrain/terrain_view.gd", "src/view/buildings/building_view.gd", "src/view/camera/camera_rig.gd",
    "src/sim/core/game_state.gd", "src/sim/facade/sim_facade_impl.gd", "src/sim/economy/economy_bootstrap.gd",
    "src/sim/actors/actor_system.gd", "src/sim/politics/politics_bootstrap.gd",
    "src/ui/hud/hud_root.gd", "src/app/platform_profile.gd", "src/contracts/sim_facade.gd",
    "data/world/ismeral/settlement.json", "data/sim/economy/economy_config.json", "data/politics/council.json",
]
# Nesnel performans/ölçüm kabulü: T-030 smoke betiği bunu artifacts/verify/m01-perf.json olarak yazar.
PERF_FILE = "artifacts/verify/m01-perf.json"
PERF_LIMITS = {  # anahtar: (üst sınır, kaynak)
    "frame_avg_ms": (8.0, "ADR-0001 ort <=8 ms (render+sim birlikte)"),
    "frame_p95_ms": (16.6, "ADR-0001 p95 <=16,6 ms"),
    "draw_calls_max": (600, "ADR-0001 draw call <=600"),
    "local_phase_triangles_max": (900000, "T-012 yerel evre <=900k üçgen"),
    "k8_lod0_lod1_diff_pct": (5.0, "T-012 K8 LOD0<->LOD1 <=%5"),
    "state_hash_ms_10k_parcels": (500.0, "T-029 tam state_hash <=~500 ms (10k parsel)"),
    "save_load_ms_10k_parcels": (1500.0, "T-029 kayıt+yükleme <=~1,5 s"),
}
SIGNOFF_FILE = "docs/agent-handoff/M01_MANUAL_SIGNOFF.json"
SIGNOFF_KEYS = {
    "q015_geography_decision": "Kullanıcı Ismeral coğrafya kararı (Q-015)",
    "t008_ipad_device_test": "iPad cihaz duman testi (T-008)",
    "t009_cross_platform_determinism": "Çapraz platform determinizm (T-009)",
    "t010_renderer_comparison": "Renderer/kalite profili karşılaştırması (T-010)",
    "t007_windows_run": "Windows .exe çalıştırma testi (T-007 eksiği)",
    "t012_visual_gate_art_director": "Yapı render görsel kapısı (art-director, T-012/VIS-04)",
    "user_playable_review": "Kullanıcının entegre demoyu bizzat incelemesi (M1 sonu kararı)",
}
IGNORED_PREFIXES = ("artifacts/", ".agents/", "IMARO_GAME_DESIGN_FOUNDATION_", ".claude/worktrees/", "build/", ".godot/")

HEAVY_IDS = ("godot.import", "godot.gdunit", "godot.gdlint", "smoke.playable")
HEAVY_CACHE = ROOT / "artifacts/verify/m01-heavy-cache.json"

results: list[dict] = []


def head_sha() -> str:
    return run(["git", "rev-parse", "HEAD"], 15)[1].strip()


def tree_is_clean() -> bool:
    return any(r["id"] == "git.clean" and r["status"] == PASS for r in results)


def load_heavy_cache() -> list[dict] | None:
    """Önbellek yalnız TAM koşudan yazılır; aynı HEAD + o an ve o zaman temiz ağaç gerekir (sahte başarı taşımaz)."""
    try:
        c = json.loads(HEAVY_CACHE.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return None
    if c.get("head") != head_sha() or not c.get("tree_clean") or not tree_is_clean():
        return None
    got = {r["id"] for r in c.get("results", [])}
    return c["results"] if got == set(HEAVY_IDS) else None


def store_heavy_cache(heavy: list[dict]) -> None:
    HEAVY_CACHE.parent.mkdir(parents=True, exist_ok=True)
    HEAVY_CACHE.write_text(json.dumps({"head": head_sha(), "tree_clean": tree_is_clean(), "results": heavy}, ensure_ascii=False, indent=1), encoding="utf-8")


def add(cid: str, title: str, status: str, detail: str = "") -> None:
    results.append({"id": cid, "title": title, "status": status, "detail": detail})


def run(cmd: list[str], timeout: int, env_extra: dict | None = None) -> tuple[int, str]:
    env = dict(os.environ)
    env.update(env_extra or {})
    try:
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout, env=env)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, f"zaman aşımı ({timeout} s)"
    except FileNotFoundError as e:
        return 127, str(e)


def strip_ansi(s: str) -> str:
    return re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", s)


def godot_path() -> str | None:
    rc, out = run(["tools/godot.sh", "--print-path"], 30)
    return out.strip().splitlines()[-1] if rc == 0 and out.strip() else None


def check_env() -> bool:
    ok = (ROOT / "project.godot").exists() and (ROOT / "tools/godot.sh").exists()
    if not ok:
        add("env.repo", "Repo kökü ve araçlar", FAIL, f"{ROOT}: project.godot/tools/godot.sh yok")
        return False
    gp = godot_path()
    if gp is None:
        add("env.godot", "Godot 4.7.2 ikilisi", FAIL, "tools/godot.sh --print-path başarısız")
        return False
    rc, out = run([gp, "--version"], 30)
    add("env.godot", "Godot 4.7.2 ikilisi", PASS if "4.7.2" in out else FAIL, out.strip()[:80])
    return "4.7.2" in out


def check_git() -> None:
    rc, branch = run(["git", "branch", "--show-current"], 15)
    rc2, head = run(["git", "rev-parse", "HEAD"], 15)
    add("git.head", "Dal ve HEAD kaydı", PASS, f"{branch.strip()} @ {head.strip()[:12]}")
    _, st = run(["git", "status", "--porcelain", "-uall"], 60)
    dirty = [ln for ln in st.splitlines() if ln[3:] and not ln[3:].startswith(IGNORED_PREFIXES)]
    add("git.clean", "Kaynak ağacı commit'li (yarım/commit'siz iş yok)", PASS if not dirty else FAIL,
        "temiz" if not dirty else f"{len(dirty)} commit'siz dosya, örn: " + "; ".join(d.strip() for d in dirty[:6]))


def check_guards() -> None:
    rc, out = run(["tools/canon-check.sh"], 120)
    add("guard.canon", "Kanon bütünlüğü (design/foundation manifest)", PASS if rc == 0 else FAIL, out.strip().splitlines()[-1][:120] if out.strip() else "")
    py = shutil.which("python3.14") or sys.executable
    rc, out = run([py, "-I", "tools/studio_check.py"], 120)
    add("guard.studio", "Studio harness kuralları (model politikası, Haiku yok)", PASS if rc == 0 else FAIL, out.strip()[:160])


def task_status(tid: str) -> tuple[str, str] | None:
    p = ROOT / "production/tasks" / f"{tid}.md"
    if not p.exists():
        return None
    txt = p.read_text(encoding="utf-8")
    m = re.search(r"^- Durum:\s*(.+)$", txt, re.M)
    ev = re.search(r"^## Kanıt\s*\n(.*)\Z", txt, re.M | re.S)
    evidence = (ev.group(1).strip() if ev else "")
    evidence_ok = bool(evidence) and not re.fullmatch(r"(- (Doğrulama|Görüntüler?|Ölçüm|İnceleme|QA|Doğrulanmamış)[^\n]*—[^\n]*\n?)+", evidence)
    return (m.group(1).strip() if m else "?", "kanıt var" if evidence_ok else "KANIT BOŞ")


def check_tasks() -> None:
    bad = []
    for tid in REQUIRED_TASKS:
        st = task_status(tid)
        if st is None:
            bad.append(f"{tid}: görev dosyası yok")
        else:
            status, ev = st
            if not status.lower().startswith("done") or ev != "kanıt var":
                bad.append(f"{tid}: durum='{status[:48]}' / {ev}")
    add("tasks.required", f"Zorunlu M01 görevleri done + kanıtlı ({len(REQUIRED_TASKS)})", PASS if not bad else FAIL,
        "hepsi done" if not bad else f"{len(bad)} eksik: " + " | ".join(bad))


def check_files() -> None:
    missing = [f for f in REQUIRED_FILES if not (ROOT / f).exists()]
    _, tracked = run(["git", "ls-files"] + [f for f in REQUIRED_FILES if (ROOT / f).exists()], 60)
    tracked_set = set(tracked.split())
    untracked = [f for f in REQUIRED_FILES if (ROOT / f).exists() and f not in tracked_set]
    add("files.required", "Gerekli sahneler/sistemler var ve git'te izleniyor", PASS if not (missing or untracked) else FAIL,
        "tamam" if not (missing or untracked) else f"eksik: {missing} | izlenmiyor: {untracked}")


def scan_godot_errors(text: str) -> list[str]:
    return [ln for ln in strip_ansi(text).splitlines() if re.search(r"SCRIPT ERROR|Parse Error|Abnormal exit|(^|[^A-Za-z])ERROR:", ln)]


def check_godot_heavy(gp: str) -> None:
    rc, out = run([gp, "--headless", "--path", str(ROOT), "--editor", "--import", "--quit"], 400)
    errs = scan_godot_errors(out)
    add("godot.import", "Proje headless açılır / içe aktarma temiz", PASS if rc == 0 and not errs else FAIL,
        "temiz" if rc == 0 and not errs else f"çıkış {rc}; {len(errs)} hata satırı: {errs[:2]}")
    shutil.rmtree(ROOT / "artifacts/verify/m01-gdunit", ignore_errors=True)
    rc, out = run([gp, "--headless", "--path", str(ROOT), "-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd", "-a", "res://tests", "-c",
                   "--ignoreHeadlessMode", "-rd", "artifacts/verify/m01-gdunit", "-rc", "1"], 1500)
    clean = strip_ansi(out)
    m = re.search(r"Overall Summary:\s*(\d+) test cases \| (\d+) errors \| (\d+) failures \| (\d+) flaky \| (\d+) skipped \| (\d+) orphans", clean)
    crash = scan_godot_errors(out)
    if not m:
        add("godot.gdunit", "GdUnit4 tam test koşusu", FAIL, f"özet yok (çıkış {rc}); {crash[:2]}")
    else:
        n, e, f, fl, sk, orph = map(int, m.groups())
        ok = e == 0 and f == 0 and n > 0 and not crash and rc in (0, 101)
        add("godot.gdunit", "GdUnit4 tam test koşusu (GDScript parse + testler)", PASS if ok else FAIL,
            f"{n} test, {e} hata, {f} başarısız, {sk} atlandı, {orph} orphan; çıkış {rc}; {crash[:2]}")
    if shutil.which("uvx"):
        rc, out = run(["uvx", "--from", "gdtoolkit==4.5.0", "gdlint", "src", "tests"], 600)
        add("godot.gdlint", "gdlint temiz (src, tests)", PASS if rc == 0 else FAIL, out.strip().splitlines()[-1][:120] if out.strip() else "")
    else:
        add("godot.gdlint", "gdlint temiz (src, tests)", SKIP, "uvx yok")


def check_smoke() -> None:
    sh = ROOT / "tools/smoke_playable.sh"
    if not sh.exists():
        add("smoke.playable", "T-030 entegre demo otomatik smoke", FAIL, "tools/smoke_playable.sh yok (T-030 smoke tanımı: bkz. IMARO_NEXT_TASK.md)")
        return
    rc, out = run(["bash", str(sh)], 1500)
    ok = rc == 0 and "SMOKE_OK" in out
    add("smoke.playable", "T-030 entegre demo otomatik smoke (pencereli + başsız)", PASS if ok else FAIL,
        "SMOKE_OK" if ok else f"çıkış {rc}; SMOKE_OK yok: {out.strip()[-160:]}")


def check_perf() -> None:
    p = ROOT / PERF_FILE
    if not p.exists():
        add("perf.measured", "Birleşik yük + kayıt/hash ölçümü (m01-perf.json)", FAIL, f"{PERF_FILE} yok (smoke betiği üretmeli)")
        return
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception as ex:  # noqa: BLE001
        add("perf.measured", "Birleşik yük + kayıt/hash ölçümü", FAIL, f"okunamadı: {ex}")
        return
    bad = []
    for k, (limit, why) in PERF_LIMITS.items():
        v = data.get(k)
        if not isinstance(v, (int, float)):
            bad.append(f"{k}: ölçüm yok ({why})")
        elif v > limit:
            bad.append(f"{k}={v} > {limit} ({why})")
    add("perf.measured", "Perf kabulü: birleşik yük, T-012 açık kriterleri, T-029 kayıt/hash", PASS if not bad else FAIL,
        "tüm sınırlar içinde" if not bad else " | ".join(bad))


def check_signoff() -> None:
    p = ROOT / SIGNOFF_FILE
    data: dict = {}
    if p.exists():
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            data = {}
    for key, title in SIGNOFF_KEYS.items():
        e = data.get(key) if isinstance(data, dict) else None
        ok = (isinstance(e, dict) and e.get("status") in ("approved", "passed", "waived") and e.get("by") and e.get("date")
              and e.get("evidence") and (e["status"] != "waived" or e.get("by") == "user"))
        add(f"manual.{key}", title, PASS if ok else MANUAL,
            "kayıtlı" if ok else f"onay/kanıt yok ({SIGNOFF_FILE}; waived yalnız by='user' ile geçerli)")


def verdict() -> int:
    st = [r["status"] for r in results]
    if any(r["id"].startswith("env.") and r["status"] == FAIL for r in results):
        return 3
    if FAIL in st:
        return 1
    if SKIP in st:
        return 4
    if MANUAL in st:
        return 2
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Imaro M01 kabul doğrulayıcısı")
    ap.add_argument("--quick", action="store_true", help="Godot gerektiren ağır adımları atla (exit 4)")
    ap.add_argument("--full", action="store_true", help="ağır adımları önbelleği yok sayarak yeniden koş")
    ap.add_argument("--list", action="store_true", help="kontrol listesini yaz")
    a = ap.parse_args()
    if a.list:
        print("Zorunlu görevler:", ", ".join(REQUIRED_TASKS))
        print("Zorunlu dosyalar:", len(REQUIRED_FILES), "| Perf sınırları:", ", ".join(PERF_LIMITS))
        print("Manuel onaylar:", ", ".join(SIGNOFF_KEYS))
        return 0
    t0 = time.time()
    env_ok = check_env()
    if env_ok or (ROOT / "project.godot").exists():
        check_git()
        check_guards()
        check_tasks()
        check_files()
        if a.quick or not env_ok:
            for cid, title in (("godot.import", "Proje headless açılır / içe aktarma"), ("godot.gdunit", "GdUnit4 tam test koşusu"),
                               ("godot.gdlint", "gdlint")):
                add(cid, title, SKIP, "--quick ile atlandı" if a.quick else "Godot yok")
            add("smoke.playable", "T-030 entegre demo otomatik smoke", SKIP, "--quick ile atlandı" if a.quick else "Godot yok")
        else:
            cached = None if a.full else load_heavy_cache()
            if cached:
                for r in cached:
                    results.append(dict(r, detail="(önbellek: aynı HEAD + temiz ağaç, tam koşudan) " + r.get("detail", "")))
            else:
                n0 = len(results)
                check_godot_heavy(godot_path() or "")
                check_smoke()
                store_heavy_cache([r for r in results[n0:] if r["id"] in HEAVY_IDS])
        check_perf()
        check_signoff()
    code = verdict()
    names = {0: "M01 DOĞRULANDI", 1: "M01 BAŞARISIZ (otomatik kontrol FAIL)", 2: "M01 DOĞRULANMADI (manuel/kullanıcı onayı eksik)",
             3: "ORTAM HATASI", 4: "KOŞU EKSİK (atlanan kontroller var)"}
    for r in results:
        print(f"{r['status']:<6} {r['id']:<34} {r['title']}")
        if r["status"] != PASS and r["detail"]:
            print(f"       -> {r['detail']}")
    print(f"\nSONUÇ: {names[code]} (çıkış {code}) · {time.time() - t0:.0f} s")
    out = ROOT / "artifacts/verify/m01-report.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"exit_code": code, "verdict": names[code], "results": results}, ensure_ascii=False, indent=1), encoding="utf-8")
    return code


if __name__ == "__main__":
    sys.exit(main())
