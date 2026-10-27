#!/usr/bin/env python3
"""Build the offline user-approval page: artifacts/library/approval.html (single file, no CDN).

The page only COLLECTS decisions (localStorage + copy/download JSON). It writes nothing to the catalog;
decisions take effect when applied with tools/library/apply_approvals.py.

Usage: python3 tools/library/build_approval_page.py [--out PATH]
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_catalog as bc  # noqa: E402
from apply_approvals import content_hashes, SHA_FIELD  # noqa: E402

SHEETS = "design/library/sheets"
OUT = "artifacts/library/approval.html"
Q018_CATEGORIES = {"human", "vehicle", "road_section", "vegetation", "ground", "street_furniture", "marking"}
Q018_TEXT = ("Q-018 acik: bu kategorinin sablon/stil kararlari (production/QUESTIONS.md) kullanici cevabi bekliyor; "
             "onay yalniz bu gorunumu kapsar.")
CATEGORY_ORDER = ["building", "roof_equipment", "vegetation", "street_furniture", "human", "vehicle", "road_section",
                  "ground", "marking"]


def load(root, rel):
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        return None
    with open(p, "r", encoding="utf-8") as fh:
        return json.load(fh)


def image_for(e, root, sheet_index, hero_index):
    """Return (relative path from artifacts/library, caption) or (None, None)."""
    ident, kind = e["id"], e["source"].get("kind")
    cands = []
    if kind == "hero":
        base = ident.rsplit("_", 1)[0]
        info = hero_index.get(base) or hero_index.get(base.replace("bld_hero_", "bld_hero_hero_", 1))
        if info:
            cands.append((SHEETS + "/" + info["sheet"], "aile sayfasi (3 varyant)"))
    elif kind in ("hero_vegetation", "hero_furniture", "hero_human"):
        folder = {"hero_vegetation": "vegetation-hero", "hero_furniture": "furniture-hero", "hero_human": "human-hero"}[kind]
        cands.append((SHEETS + "/%s/%s.png" % (folder, ident), "kontak sayfasi"))
    elif kind == "texture":
        cands.append((SHEETS + "/ground-textures.png", "14 doku ortak sayfa"))
    else:
        info = sheet_index.get(ident)
        if info:
            cands.append((SHEETS + "/" + info["sheet"], "ortak sayfa, satir %s" % info.get("row", "?")))
    for rel, cap in cands:
        if os.path.isfile(os.path.join(root, rel)):
            return "../../" + rel, cap
    return None, None


def context_images(root):
    out = {}
    for cat, folder in (("vegetation", "vegetation-hero"), ("street_furniture", "furniture-hero"), ("human", "human-hero")):
        d = os.path.join(root, SHEETS, folder)
        if os.path.isdir(d):
            out[cat] = ["../../%s/%s/%s" % (SHEETS, folder, f) for f in sorted(os.listdir(d))
                        if f.startswith(("context-", "style-")) and f.endswith(".png")]
    return out


def build_data(root):
    catalog = load(root, bc.CATALOG)
    sheet_index = load(root, SHEETS + "/index.json") or {}
    hero_index = load(root, SHEETS + "/hero-index.json") or {}
    cats = {c["id"]: c["label_tr"] for c in catalog["categories"]}
    items = []
    for e in catalog["entries"]:
        img, cap = image_for(e, root, sheet_index, hero_index)
        d = e.get("dimensions_m") or {}
        tri = e.get("triangles") or {}
        hashes = content_hashes(e)
        warn = []
        if e["category"] in Q018_CATEGORIES or "Q-018" in json.dumps(e, ensure_ascii=False):
            warn.append(Q018_TEXT)
        if e.get("approval") == "approved" and e.get(SHA_FIELD) not in (None, hashes):
            warn.append("Onayli kayit ama icerik hash'i onaydan sonra degismis; yeniden onay uygulayici tarafindan reddedilir.")
        items.append({
            "id": e["id"], "label": e.get("label_tr") or "", "category": e["category"],
            "category_label": cats.get(e["category"], e["category"]), "family": e.get("family"),
            "dims": [d.get("width_x"), d.get("depth_z"), d.get("height_above_ground")] if d else None,
            "lod0": tri.get("LOD0"), "lod1": tri.get("LOD1"), "status": e.get("approval"),
            "sha8": (hashes.get("glb") or hashes.get("png") or "")[:8], "n_hashes": len(hashes),
            "sha256": hashes, "image": img, "image_caption": cap, "warn": warn, "user_note": e.get("user_note", ""),
        })
    order = {c: i for i, c in enumerate(CATEGORY_ORDER)}
    items.sort(key=lambda x: (order.get(x["category"], 99), x["family"] or "", x["id"]))
    return {"catalog_version": catalog["catalog_version"], "categories": [
        {"id": c, "label": cats.get(c, c)} for c in CATEGORY_ORDER if any(i["category"] == c for i in items)],
        "items": items, "context": context_images(root)}


CSS = r"""
:root{color-scheme:light dark;--bg:#f4f1ea;--fg:#23211d;--card:#fff;--line:#d6d0c4;--mut:#6b665c;--ok:#2e7d4f;--no:#b3392f;--hold:#a87a12;--warn:#fff1c9;--warnfg:#5a4300}
@media(prefers-color-scheme:dark){:root{--bg:#1c1b19;--fg:#ece8df;--card:#272521;--line:#3d3a34;--mut:#a39d90;--ok:#59b87f;--no:#e0675c;--hold:#d9a93a;--warn:#4a3b10;--warnfg:#f3dfa0}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.4 system-ui,sans-serif;padding:16px}
h1{font-size:1.3rem;margin:0 0 8px}h2{font-size:1.1rem;margin:24px 0 8px;border-bottom:1px solid var(--line);padding-bottom:4px}
.banner{background:var(--warn);color:var(--warnfg);padding:10px 12px;border-radius:6px;margin-bottom:16px}
.bar{position:sticky;top:0;background:var(--bg);padding:8px 0;z-index:5;display:flex;flex-wrap:wrap;gap:8px 16px;align-items:center;border-bottom:1px solid var(--line)}
.counts span{margin-right:12px;white-space:nowrap}
select,button,input{font:inherit;color:inherit;background:var(--card);border:1px solid var(--line);border-radius:6px;padding:6px 10px}
button{cursor:pointer;min-height:36px}button:hover{border-color:var(--mut)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,300px),1fr));gap:16px}
.card{background:var(--card);border:2px solid var(--line);border-radius:8px;padding:12px;display:flex;flex-direction:column;gap:6px}
.card.approved{border-color:var(--ok)}.card.rejected{border-color:var(--no)}.card.hold{border-color:var(--hold)}
.card img{width:100%;height:auto;max-height:260px;object-fit:contain;background:#8884;border-radius:4px}
.noimg{padding:28px 8px;text-align:center;background:#8883;border-radius:4px;color:var(--mut)}
.cap{font-size:.8rem;color:var(--mut)}.id{font-weight:600;word-break:break-all}.meta{font-size:.85rem;color:var(--mut)}
.warn{background:var(--warn);color:var(--warnfg);padding:6px 8px;border-radius:4px;font-size:.82rem}
.btns{display:flex;gap:6px}.btns button{flex:1}
.btns .a.on{background:var(--ok);color:#fff}.btns .r.on{background:var(--no);color:#fff}.btns .h.on{background:var(--hold);color:#fff}
.note{width:100%}.ctx{display:flex;gap:8px;overflow-x:auto;margin-bottom:8px}.ctx img{height:140px;border-radius:4px}
code{font-size:.8rem}
"""

JS = r"""
(function(){
var D=JSON.parse(document.getElementById('data').textContent);
var KEY='imaro-approval-decisions/1:v'+D.catalog_version;
var state={};
try{state=JSON.parse(localStorage.getItem(KEY)||'{}')||{};}catch(e){state={};}
function save(){try{localStorage.setItem(KEY,JSON.stringify(state));}catch(e){}}
var LBL={approved:'Onaylandi',rejected:'Reddedildi',hold:'Beklemede',none:'Karar yok'};
function el(t,c,x){var n=document.createElement(t);if(c)n.className=c;if(x!=null)n.textContent=x;return n;}
var fc=document.getElementById('fcat'),fd=document.getElementById('fdec'),root=document.getElementById('root');
fc.appendChild(new Option('Tum kategoriler','all'));
D.categories.forEach(function(c){fc.appendChild(new Option(c.label,c.id));});
[['all','Tum kararlar'],['none','Karar yok'],['approved','Onay'],['rejected','Red'],['hold','Bekle']].forEach(function(p){fd.appendChild(new Option(p[1],p[0]));});
function dec(id){return (state[id]&&state[id].decision)||'none';}
function counts(){var c={approved:0,rejected:0,hold:0,none:0};D.items.forEach(function(i){c[dec(i.id)]++;});
 document.getElementById('counts').textContent='';
 ['approved','rejected','hold','none'].forEach(function(k){var s=el('span',null,LBL[k]+': '+c[k]);document.getElementById('counts').appendChild(s);});}
function card(it){
 var d=dec(it.id),c=el('div','card '+(d==='none'?'':d));
 if(it.image){var im=el('img');im.loading='lazy';im.alt=it.id;im.src=it.image;
  im.onerror=function(){var n=el('div','noimg','gorsel yok (dosya acilamadi)');im.replaceWith(n);};c.appendChild(im);
  c.appendChild(el('div','cap',it.image_caption||''));}
 else c.appendChild(el('div','noimg','gorsel yok'));
 c.appendChild(el('div','id',it.id));
 if(it.label)c.appendChild(el('div','meta',it.label));
 var dim=it.dims?it.dims.map(function(v){return v==null?'?':v;}).join(' x ')+' m (g x d x y)':'olcu yok';
 c.appendChild(el('div','meta',it.category_label+' | '+dim));
 c.appendChild(el('div','meta','LOD0 '+(it.lod0==null?'-':it.lod0)+' / LOD1 '+(it.lod1==null?'-':it.lod1)+' ucgen | statu: '+it.status));
 c.appendChild(el('div','meta','sha '+(it.sha8||'-')+' ('+it.n_hashes+' hash)'));
 it.warn.forEach(function(w){c.appendChild(el('div','warn',w));});
 var b=el('div','btns');
 [['approved','Onayla','a'],['rejected','Reddet','r'],['hold','Bekle','h']].forEach(function(p){
  var x=el('button',p[2]+(d===p[0]?' on':''),p[1]);x.type='button';
  x.onclick=function(){var n=(state[it.id]&&state[it.id].note)||'';
   if(d===p[0]){delete state[it.id];}else{state[it.id]={decision:p[0],note:n};}save();render();};b.appendChild(x);});
 c.appendChild(b);
 var n=el('input','note');n.type='text';n.placeholder='kisa not (istege bagli)';n.maxLength=300;n.value=(state[it.id]&&state[it.id].note)||(d==='none'?'':'');
 n.oninput=function(){if(!state[it.id])return;state[it.id].note=n.value;save();};
 if(d==='none'){n.disabled=true;n.placeholder='once bir karar sec';}
 c.appendChild(n);return c;}
function render(){
 counts();root.textContent='';
 D.categories.forEach(function(cat){
  if(fc.value!=='all'&&fc.value!==cat.id)return;
  var its=D.items.filter(function(i){return i.category===cat.id&&(fd.value==='all'||dec(i.id)===fd.value);});
  if(!its.length)return;
  root.appendChild(el('h2',null,cat.label+' ('+its.length+')'));
  var cx=D.context[cat.id];if(cx&&cx.length){var r=el('div','ctx');cx.forEach(function(s){var i=el('img');i.src=s;i.alt='baglam';i.loading='lazy';i.onerror=function(){i.remove();};r.appendChild(i);});root.appendChild(r);}
  var g=el('div','grid');its.forEach(function(i){g.appendChild(card(i));});root.appendChild(g);});}
function payload(){
 var out=[];D.items.forEach(function(i){var s=state[i.id];if(!s)return;
  out.push({id:i.id,decision:s.decision,sha256:i.sha256,note:s.note||''});});
 return {schema:'imaro-approval-decisions/1',decided_by:'user',decided_at:new Date().toISOString(),catalog_version:D.catalog_version,decisions:out};}
var msg=document.getElementById('msg');
document.getElementById('copy').onclick=function(){var t=JSON.stringify(payload(),null,2);
 function fb(){var a=el('textarea');a.value=t;document.body.appendChild(a);a.select();var ok=false;try{ok=document.execCommand('copy');}catch(e){}a.remove();msg.textContent=ok?'Kopyalandi.':'Kopyalanamadi; JSON indir kullan.';}
 if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t).then(function(){msg.textContent='Kopyalandi ('+payload().decisions.length+' karar).';},fb);}else fb();};
document.getElementById('dl').onclick=function(){var t=JSON.stringify(payload(),null,2);
 var a=el('a');a.href=URL.createObjectURL(new Blob([t],{type:'application/json'}));a.download='imaro-approval-decisions.json';document.body.appendChild(a);a.click();a.remove();msg.textContent='Indirildi.';};
document.getElementById('clr').onclick=function(){if(confirm('Tum kararlar bu tarayicidan silinsin mi?')){state={};save();render();}};
fc.onchange=fd.onchange=render;render();
})();
"""


def render_html(data):
    blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    return """<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Imaro varlik onay sayfasi</title><style>%s</style></head><body>
<h1>Imaro varlik kutuphanesi - onay sayfasi</h1>
<div class="banner">Bu sayfa karar toplar; kayit sohbette yapistirdiginda uygulanir. Sayfa katalogu degistirmez; onay oyuna baglanmaz.</div>
<div class="bar"><select id="fcat" aria-label="Kategori"></select><select id="fdec" aria-label="Karar durumu"></select>
<span class="counts" id="counts"></span>
<button id="copy" type="button">Kararlari kopyala</button><button id="dl" type="button">JSON indir</button><button id="clr" type="button">Temizle</button><span id="msg"></span></div>
<div id="root"></div>
<script id="data" type="application/json">%s</script>
<script>%s</script></body></html>
""" % (CSS, blob, JS)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=bc.ROOT)
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)
    out = args.out or os.path.join(root, OUT)
    data = build_data(root)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(render_html(data))
    noimg = [i["id"] for i in data["items"] if not i["image"]]
    print("wrote %s: %d entries, %d without image" % (out, len(data["items"]), len(noimg)))
    if noimg:
        print("no image: " + ", ".join(noimg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
