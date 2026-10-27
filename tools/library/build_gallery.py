#!/usr/bin/env python3
"""Build the offline Imaro visual review gallery; never writes approval records.
Run from any directory: python3 tools/library/build_gallery.py [--out PATH]
"""
import argparse
from collections import Counter
from html import escape
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FAMILIES = {"old_core": "Tarihî çekirdek", "bazaar": "Çarşı", "res_mid": "Orta dönem apartman", "res_late": "Geç dönem apartman", "house": "Müstakil ev", "industrial": "Sanayi", "civic": "Kamu ve saat kulesi"}
GROUPS = {"building": "Binalar", "ground": "Zeminler", "lod": "Bina LOD", "vegetation": "Bitkiler", "furniture": "Donatılar", "human": "İnsanlar", "vehicle": "Araçlar", "road": "Yol kesitleri"}
FOLDERS = {"vegetation-hero": "vegetation", "furniture-hero": "furniture", "human-hero": "human", "vehicle-hero": "vehicle", "road-hero": "road"}
PLANT_LABELS = {"plane": "Çınar", "palm_date": "Geniş taçlı palmiye", "palm_slender": "İnce uzun palmiye", "pine_brutia": "Kızılçam", "pine_stone": "Fıstık çamı", "olive_open": "Açık taçlı zeytin", "olive_twisted": "Burgulu gövdeli zeytin", "cypress": "Servi", "maquis": "Maki / çalı kümesi", "hedge": "Budanmış çit"}


def records(root=ROOT):
    base = root / "design/library/sheets"
    result = []
    for key, label in FAMILIES.items():
        result.append((base / ("hero-" + key + ".png"), label, "building", "Bina ailesi · üç varyant"))
    result.append((base / "ground-textures.png", "Zemin dokuları", "ground", "14 doku · kullanıcı değerlendirmesi açık"))
    for path in sorted((base / "hero-lod").glob("*.png")):
        key = next((key for key in FAMILIES if path.stem.startswith(key + "-")), None)
        label = FAMILIES[key] if key else path.stem
        note = path.stem[len(key) + 1:] if key else path.stem
        result.append((path, label, "lod", note + " · yakın / orta / uzak"))
    for folder, group in FOLDERS.items():
        for path in sorted((base / folder).glob("*.png")):
            label = PLANT_LABELS.get(path.stem.removeprefix("veg_hero_").removesuffix("_a"), path.stem.replace("_", " ").replace("-", " · ")) if group == "vegetation" else path.stem.replace("_", " ").replace("-", " · ")
            result.append((path, label, group, "Kütüphane önerisi · onay aktarılmaz"))
    return result


def build(out, root=ROOT):
    rows = records(root)
    missing = [str(row[0]) for row in rows if not row[0].is_file()]
    if missing:
        raise ValueError("Eksik görsel: " + ", ".join(missing))
    cards = []
    for path, title, group, note in rows:
        url = escape(os.path.relpath(path, out.parent).replace(os.sep, "/"), quote=True)
        cards.append('<article data-group="%s"><a href="%s" target="_blank" rel="noopener"><img src="%s" alt="%s" loading="lazy"><div class="caption"><span>%s</span><h2>%s</h2><p>Tam boy görüntüle ↗</p></div></a></article>' % (group, url, url, escape(title, quote=True), escape(note), escape(title)))
    counts = Counter(row[2] for row in rows)
    buttons = '<button type="button" data-filter="all" aria-pressed="true">Tümü</button>'
    for group, label in GROUPS.items():
        if counts[group]:
            buttons += '<button type="button" data-filter="%s" aria-pressed="false">%s <small>%s</small></button>' % (group, label, counts[group])
    page = """<!doctype html><html lang="tr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Imaro — Varlık kütüphanesi</title><style>
:root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#222922;background:#f5f3ed}*{box-sizing:border-box}body{margin:0}header,main{max-width:1440px;margin:auto;padding:32px}header{padding-top:52px;padding-bottom:20px}.eyebrow{font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:#5c685d}h1{font-size:clamp(30px,5vw,50px);letter-spacing:-.045em;margin:12px 0}header p{color:#586158;line-height:1.6;max-width:780px}nav{display:flex;flex-wrap:wrap;gap:8px;margin:26px 0 12px}button{font:inherit;padding:11px 17px;border:1px solid #c9cec4;border-radius:7px;color:inherit;background:transparent;cursor:pointer}button[aria-pressed=true]{color:#fff;background:#324837;border-color:#324837}small{opacity:.7;margin-left:6px}button:focus-visible,a:focus-visible{outline:3px solid #b47c39;outline-offset:4px}main{padding-top:8px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,370px),1fr));gap:22px}article{background:white;border:1px solid #d9ddd3;border-radius:10px;overflow:hidden}article[hidden]{display:none}a{color:inherit;text-decoration:none;display:block}img{display:block;width:100%;height:auto;aspect-ratio:4/3;object-fit:contain;background:#e7e7df}.caption{padding:18px 20px}.caption span{font-size:12px;color:#697367}.caption h2{font-size:19px;margin:8px 0}.caption p{font-size:13px;color:#426747;margin:12px 0 0}.count{font-size:13px;color:#697367;margin-bottom:18px}@media(max-width:600px){header,main{padding:20px}header{padding-top:30px}.grid{gap:16px}}
</style><header><div class="eyebrow">Imaro / Varlık kütüphanesi</div><h1>Şehrin parçaları.</h1><p>Binalar, zeminler ve yeni varlık önerileri. Görsele tıklayarak tam boy açabilirsin. LOD sayfalarında soldan sağa yakın, orta ve uzak model gösterilir. Yeni öneriler kullanıcı onayı değildir.</p><nav aria-label="Kategoriler">""" + buttons + """</nav></header><main><p class="count" aria-live="polite"></p><div class="grid">""" + "".join(cards) + """</div></main><script>
const buttons=[...document.querySelectorAll('button[data-filter]')],cards=[...document.querySelectorAll('article[data-group]')];
function select(filter){if(!buttons.some(b=>b.dataset.filter===filter))filter='all';buttons.forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.filter===filter)));cards.forEach(card=>card.hidden=filter!=='all'&&card.dataset.group!==filter);document.querySelector('.count').textContent=cards.filter(c=>!c.hidden).length+' görsel';}
buttons.forEach(button=>button.addEventListener('click',()=>{const filter=button.dataset.filter;history.replaceState(null,'','#'+filter);select(filter);}));select(location.hash.slice(1)||'all');
</script></html>"""
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page, encoding="utf-8")
    return len(rows), counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "artifacts/library/t056-gallery.html")
    args = parser.parse_args()
    out = args.out.resolve()
    count, groups = build(out)
    print("gallery:", out, "images:", count, "groups:", dict(groups))


if __name__ == "__main__":
    main()
