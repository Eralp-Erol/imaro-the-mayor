"""Patch Godot .glb.import files of the kit with the spec section 8 import settings (T-004).

  python3 art/blender/set_import_params.py            # after the first `godot --headless --editor --import --quit`
  tools/godot.sh --headless --path . --editor --import --quit   # re-import with the new params

Settings: root_scale 1.0, generate_lods false (LODs are authored), ensure_tangents false, light_baking disabled,
shadow meshes off, no animation. Idempotent; touches only the listed keys.
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PARAMS = {
    "nodes/root_scale": "1.0",
    "meshes/generate_lods": "false",
    "meshes/ensure_tangents": "false",
    "meshes/light_baking": "0",
    "meshes/create_shadow_meshes": "false",
    "animation/import": "false",
}


def patch(path):
    with open(path) as f:
        text = f.read()
    out = text
    for key, val in PARAMS.items():
        pat = re.compile(r"^%s=.*$" % re.escape(key), re.M)
        if pat.search(out):
            out = pat.sub("%s=%s" % (key, val), out)
        else:
            out = out.replace("[params]\n", "[params]\n\n%s=%s\n" % (key, val), 1)
    if out != text:
        with open(path, "w") as f:
            f.write(out)
        return True
    return False


def main():
    files = sorted(glob.glob(os.path.join(ROOT, "assets", "models", "**", "*.glb.import"), recursive=True))
    changed = sum(1 for p in files if patch(p))
    print("set_import_params: %d .glb.import files, %d patched" % (len(files), changed))
    if not files:
        sys.exit(1)


main()
