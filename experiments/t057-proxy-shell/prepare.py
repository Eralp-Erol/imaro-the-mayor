from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'artifacts/verify/t057/shell';out.mkdir(parents=True,exist_ok=True)
(out/'source_rgba.bin').write_bytes(Image.open(ROOT/'assets/hero/vegetation/vegetation_atlas.png').convert('RGBA').tobytes())
