"""T-077: raw/*.json -> özet tabloları (stdout, markdown). Salt okunur. Çalıştır: python3 -I summarize.py"""
import glob
import json
import os

RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")
REG = ["D1", "D2", "D3", "D4", "D5", "D6"]


def load(name):
    p = os.path.join(RAW, name + ".json")
    return json.load(open(p)) if os.path.exists(p) else None


def ev_total(d, key):
    out = {r: 0 for r in REG}
    for y, row in d["events_by_year"].items():
        for r, n in row.get(key, {}).items():
            if r in out:
                out[r] += n
    return out


def census_new(d):
    """Başlangıca göre vacant dışı parsel artışı (planned+uc+built+stalled) bölge başına."""
    out = {}
    for r in REG:
        s, e = d["census_start"][r], d["census_end"][r]
        nv = lambda c: c["planned"] + c["under_construction"] + c["built"] + c["stalled"]
        out[r] = nv(e) - nv(s)
    return out


def main():
    seeds = [1467, 7, 31337]
    print("## İlçe başına yeni yapı (5 yıl) — olay sayımı: yatırım onayı / inşaat başladı / tamamlandı")
    print("| koşu | " + " | ".join(REG) + " | toplam |")
    print("|---|" + "---|" * 7)
    for s in seeds:
        for mode in ("player", "none"):
            d = load("%s-s%d" % (mode, s))
            if not d:
                continue
            for key, label in (("event.investor.develop", "onay"), ("event.construction.started", "başladı"),
                               ("event.construction.completed", "tamam")):
                t = ev_total(d, key)
                print("| %s s%d %s | %s | %d |" % (mode, s, label, " | ".join(str(t[r]) for r in REG), sum(t.values())))
    print()
    print("## Parsel sütunu farkı (vacant dışına geçen parsel; census_end - census_start) ve bina/birim farkı (region_stats)")
    print("| koşu | " + " | ".join(REG) + " |")
    print("|---|" + "---|" * 6)
    for s in seeds:
        for mode in ("player", "none"):
            d = load("%s-s%d" % (mode, s))
            if not d:
                continue
            c = census_new(d)
            print("| %s s%d parsel | %s |" % (mode, s, " | ".join(str(c[r]) for r in REG)))
            rs, re_ = d["region_stats_start"], d["region_stats_end"]
            print("| %s s%d res_built Δ | %s |" % (mode, s, " | ".join(str(re_[r]["res_built"] - rs[r]["res_built"]) for r in REG)))
            print("| %s s%d com_built Δ | %s |" % (mode, s, " | ".join(str(re_[r]["com_built"] - rs[r]["com_built"]) for r in REG)))
    print()
    print("## Bölge başına reddedilen değerlendirme (next_review artışı, 5 yıl toplam) ve bitişte boş parsel son kodu")
    for s in seeds:
        for mode in ("player", "none"):
            d = load("%s-s%d" % (mode, s))
            if not d:
                continue
            tot = {r: 0 for r in REG}
            for y, row in d.get("declined_evals_by_year", {}).items():
                for r, n in row.items():
                    if r in tot:
                        tot[r] += n
            print("- %s s%d reddedilen değerlendirme: %s" % (mode, s, json.dumps(tot)))
            print("  son kod (bitişte boş): %s" % json.dumps(d["vacant_last_code_end"], ensure_ascii=False))
    print()
    print("## Yıl yıl onay (event.investor.develop) bölge başına")
    for s in seeds:
        for mode in ("player", "none"):
            d = load("%s-s%d" % (mode, s))
            if not d:
                continue
            for y, row in sorted(d["events_by_year"].items()):
                print("- %s s%d %s: %s" % (mode, s, y, json.dumps(row.get("event.investor.develop", {}))))
    print()
    print("## Bütçe (max_reviews_per_tick)")
    print("| koşu | cap | gün | gün başına ort. | kullanım % | cap'te gün % | imleç ilerleme/gün | tam tarama (gün) |")
    print("|---|---|---|---|---|---|---|---|")
    for name in sorted(glob.glob(os.path.join(RAW, "*.json"))):
        n = os.path.basename(name)[:-5]
        d = load(n)
        b = d["budget"]
        print("| %s | %d | %d | %s | %s | %s | %s | %s |" % (n, b["cap"], b["days"], b["evaluations_per_day_mean"], b["usage_pct_of_cap"],
              b["days_at_cap_pct"], b["review_cursor_adv_per_day_mean"], b["implied_full_scan_cycle_days"]))
    print()
    print("## Tick süresi (ms, ilk tick hariç)")
    print("| koşu | ilk tick | ort | medyan | p95 | p99 | maks | ay sonu ort/p95/maks | çeyrek sonu ort/maks | >8,33 ms | >16,6 ms |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for name in sorted(glob.glob(os.path.join(RAW, "*.json"))):
        n = os.path.basename(name)[:-5]
        d = load(n)
        t = d["timing_ms"]
        a, m, q = t["all_excl_first"], t["month_end_excl_quarter"], t["quarter_end"]
        print("| %s | %s | %s | %s | %s | %s | %s | %s/%s/%s | %s/%s | %s | %s |" % (n, t["first_tick_ms"], a["mean"], a["median"], a["p95"], a["p99"],
              a["max"], m["mean"], m["p95"], m["max"], q["mean"], q["max"], t["ticks_over_8_33ms"], t["ticks_over_16_6ms"]))
    print()
    print("## Tick süresi yıl yıl ort/p95/maks")
    for name in sorted(glob.glob(os.path.join(RAW, "*.json"))):
        n = os.path.basename(name)[:-5]
        d = load(n)
        print("- %s: %s" % (n, "; ".join("%s %s/%s/%s" % (y, v["mean"], v["p95"], v["max"]) for y, v in sorted(d["timing_ms"]["per_year"].items()))))
    d = load("player-s1467-profile")
    if d:
        print()
        print("## Sistem profili (player s1467, --profile)")
        for k, v in sorted(d["profile_ms"].items(), key=lambda kv: -kv[1]["mean_ms"] * kv[1]["n"]):
            print("- %s: ort %s ms · n %s · maks %s ms (tick %s)" % (k, v["mean_ms"], v["n"], v["max_ms"], v["max_tick"]))
    print()
    print("## Komutlar (player s1467) ve yetki yoklaması")
    d = load("player-s1467")
    if d:
        for c in d["commands"]:
            print("- %s" % json.dumps(c, ensure_ascii=False))
        print("- authority_probe: %s" % json.dumps(d["authority_probe"], ensure_ascii=False))
    print()
    print("## state_hash")
    for name in sorted(glob.glob(os.path.join(RAW, "*.json"))):
        n = os.path.basename(name)[:-5]
        print("- %s: %s (end_tick %s)" % (n, load(n)["state_hash"], load(n)["end_tick"]))


main()
