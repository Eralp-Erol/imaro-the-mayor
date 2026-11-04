"""T-055 yan yana kiyas: [eski tek-renk zemin (lab simulasyonu) | yeni lab zemini | referans kirpintisi] -> design/specs/art/ground/.
Kullanim: python3 art/blender/ground/ground_compare.py <captures_dir> <suffix_new> <suffix_old> <out_dir>
Yakalama adlari: *-<suffix_new>-<shot>.png ve *-<suffix_old>-<shot>.png (en yenisi). Referans: kanon klasorunden SALT OKUNUR kirpinti."""
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

REF = "design/foundation/visual-references/"
# (shot, referans dosyasi, kirpinti kutusu (oranlar), etiket)
JOBS = [
    ("eye", "03_ismeral_mature_architecture_DIRECTION.png", (0.75, 0.58, 1.0, 1.0), "ref 03 ZOOM 4 sokak: acik kaldirim, sicak tas"),
    ("street", "03_ismeral_mature_architecture_DIRECTION.png", (0.44, 0.62, 0.75, 0.98), "ref 03 ZOOM 3 ana meydan: acik tas meydan + kiyi kaldirimi"),
    ("district", "02_ismeral_t0_vs_mature_SELECTED.jpg", (0.25, 0.0, 0.7, 0.25), "ref 02 D4 ova: tarla mozaigi, kuru yamac"),
]


def newest(d, name):
    f = sorted(glob.glob(os.path.join(d, "*-%s.png" % name)))
    return f[-1] if f else None


def main():
    cap, sn, so, out = sys.argv[1:5]
    os.makedirs(out, exist_ok=True)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 20)
    except Exception:
        font = ImageFont.load_default(20)
    H = 450
    for shot, ref, box, label in JOBS:
        a, b = newest(cap, "%s-old-%s" % (so, shot)), newest(cap, "%s-%s" % (sn, shot))
        if not a or not b:
            print("eksik", shot, a, b)
            continue
        r = Image.open(REF + ref).convert("RGB")
        w, h = r.size
        r = r.crop((int(w * box[0]), int(h * box[1]), int(w * box[2]), int(h * box[3])))
        panels = []
        for im in (Image.open(a).convert("RGB"), Image.open(b).convert("RGB"), r):
            panels.append(im.resize((int(im.width * H / im.height), H), Image.LANCZOS))
        W = sum(p.width for p in panels) + 20
        sheet = Image.new("RGB", (W, H + 40), (24, 24, 24))
        x = 0
        d = ImageDraw.Draw(sheet)
        for p, t in zip(panels, ["ONCE: eski tek-renk zemin (lab simulasyonu)", "SONRA: T-055 lab zemini", label]):
            sheet.paste(p, (x, 40))
            d.text((x + 6, 8), t, fill=(240, 240, 235), font=font)
            x += p.width + 10
        path = os.path.join(out, "compare-%s.png" % shot)
        sheet.save(path)
        print(path, sheet.size)


if __name__ == "__main__":
    main()
