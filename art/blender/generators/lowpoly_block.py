"""Parametric low-poly apartment block -> glTF binary (.glb). Deterministic, no randomness.

Run:
  Blender --background --factory-startup --python art/blender/generators/lowpoly_block.py -- \
      --floors 5 --width 14 --depth 10 --out experiments/asset-pipeline-smoke/assets/bld_smoke_5f.glb

Conventions: Blender units = metres, Z up (glTF exporter converts to Y up). Origin = ground centre
(x/y centred, z=0 at ground). Front facade faces -Y in Blender (+Z in glTF). Two flat matte
materials: mat_wall (walls) and mat_trim (balcony recesses, parapet cap, roof deck). No UVs, no
textures, no bottom face. Triangles: 36 per floor + 28 for the roof (208 for 5 floors).
"""
import argparse
import os
import sys

import bmesh
import bpy
from mathutils import Vector

FLOOR_H = 3.0     # storey height (m)
BAL_SILL = 0.9    # balcony recess starts this high above the floor (m)
BAL_H = 1.6       # recess height (m)
BAL_MARGIN = 1.5  # solid wall left/right of the recess (m), clamped to 20% of width
RECESS = 0.6      # recess depth (m)
PARAPET_H = 0.9
PARAPET_T = 0.3

WALL_COLOR = (0.86, 0.80, 0.70, 1.0)  # warm plaster, linear
TRIM_COLOR = (0.22, 0.26, 0.30, 1.0)  # dark slate, linear


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(prog="lowpoly_block")
    ap.add_argument("--floors", type=int, default=5)
    ap.add_argument("--width", type=float, default=14.0, help="X size in metres")
    ap.add_argument("--depth", type=float, default=10.0, help="Y size in metres")
    ap.add_argument("--out", required=True, help="output .glb path")
    a = ap.parse_args(argv)
    if not 1 <= a.floors <= 40:
        ap.error("--floors must be 1..40")
    if a.width < 6 or a.depth < 4:
        ap.error("--width must be >= 6 and --depth >= 4")
    return a


def make_material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Specular IOR Level"].default_value = 0.0
    mat.diffuse_color = color
    return mat


class Builder:
    """Tiny bmesh helper: shared vertices by rounded coordinate, faces oriented by expected normal."""

    def __init__(self):
        self.bm = bmesh.new()
        self._v = {}

    def vert(self, x, y, z):
        key = (round(x, 5), round(y, 5), round(z, 5))
        if key not in self._v:
            self._v[key] = self.bm.verts.new(key)
        return self._v[key]

    def face(self, pts, outward, mat_index):
        vs = [self.vert(*p) for p in pts]
        n = Vector((0, 0, 0))  # Newell normal
        for i, a in enumerate(pts):
            b = pts[(i + 1) % len(pts)]
            n.x += (a[1] - b[1]) * (a[2] + b[2])
            n.y += (a[2] - b[2]) * (a[0] + b[0])
            n.z += (a[0] - b[0]) * (a[1] + b[1])
        if n.dot(Vector(outward)) < 0:
            vs.reverse()
        f = self.bm.faces.new(vs)
        f.material_index = mat_index
        f.smooth = False
        return f


WALL, TRIM = 0, 1


def build_mesh(floors, width, depth):
    b = Builder()
    hx, hy = width / 2.0, depth / 2.0
    height = floors * FLOOR_H
    m = min(BAL_MARGIN, width * 0.2)
    xs = [-hx, -hx + m, hx - m, hx]          # front columns
    yf, yr = -hy, -hy + RECESS               # front plane, recess back plane
    down, up, left, right = (0, -1, 0), (0, 1, 0), (-1, 0, 0), (1, 0, 0)

    for i in range(floors):
        z0 = i * FLOOR_H
        zs = [z0, z0 + BAL_SILL, z0 + BAL_SILL + BAL_H, z0 + FLOOR_H]
        # Front facade: 3x3 cells, centre cell recessed (mat_trim).
        for r in range(3):
            for c in range(3):
                if r == 1 and c == 1:
                    continue
                b.face([(xs[c], yf, zs[r]), (xs[c + 1], yf, zs[r]),
                        (xs[c + 1], yf, zs[r + 1]), (xs[c], yf, zs[r + 1])], down, WALL)
        x1, x2, zb, zt = xs[1], xs[2], zs[1], zs[2]
        b.face([(x1, yr, zb), (x2, yr, zb), (x2, yr, zt), (x1, yr, zt)], down, TRIM)        # back panel
        b.face([(x1, yf, zb), (x2, yf, zb), (x2, yr, zb), (x1, yr, zb)], (0, 0, 1), TRIM)   # balcony floor
        b.face([(x1, yf, zt), (x2, yf, zt), (x2, yr, zt), (x1, yr, zt)], (0, 0, -1), TRIM)  # soffit
        b.face([(x1, yf, zb), (x1, yr, zb), (x1, yr, zt), (x1, yf, zt)], right, TRIM)       # left reveal
        b.face([(x2, yf, zb), (x2, yr, zb), (x2, yr, zt), (x2, yf, zt)], left, TRIM)        # right reveal
        # Back wall (one quad per floor).
        b.face([(-hx, hy, z0), (hx, hy, z0), (hx, hy, z0 + FLOOR_H), (-hx, hy, z0 + FLOOR_H)], up, WALL)
        # Side walls: ngon whose front edge carries the facade's extra verts (no T-junctions).
        for sx, n in ((-hx, left), (hx, right)):
            pts = [(sx, yf, zs[0]), (sx, yf, zs[1]), (sx, yf, zs[2]), (sx, yf, zs[3]),
                   (sx, hy, zs[3]), (sx, hy, zs[0])]
            b.face(pts, n, WALL)

    # Roof: parapet (outer = wall, cap + deck = trim).
    zh, zp = height, height + PARAPET_H
    ix, iy = hx - PARAPET_T, hy - PARAPET_T
    ztop = [(xs[0], yf), (xs[1], yf), (xs[2], yf), (xs[3], yf)]
    b.face([(x, y, zh) for x, y in ztop] + [(hx, yf, zp), (-hx, yf, zp)], down, WALL)   # front outer (carries facade verts)
    b.face([(hx, yf, zh), (hx, hy, zh), (hx, hy, zp), (hx, yf, zp)], right, WALL)
    b.face([(hx, hy, zh), (-hx, hy, zh), (-hx, hy, zp), (hx, hy, zp)], up, WALL)
    b.face([(-hx, hy, zh), (-hx, yf, zh), (-hx, yf, zp), (-hx, hy, zp)], left, WALL)
    # cap ring
    b.face([(-hx, yf, zp), (hx, yf, zp), (ix, -iy, zp), (-ix, -iy, zp)], (0, 0, 1), TRIM)
    b.face([(hx, yf, zp), (hx, hy, zp), (ix, iy, zp), (ix, -iy, zp)], (0, 0, 1), TRIM)
    b.face([(hx, hy, zp), (-hx, hy, zp), (-ix, iy, zp), (ix, iy, zp)], (0, 0, 1), TRIM)
    b.face([(-hx, hy, zp), (-hx, yf, zp), (-ix, -iy, zp), (-ix, iy, zp)], (0, 0, 1), TRIM)
    # inner parapet faces
    b.face([(-ix, -iy, zh), (ix, -iy, zh), (ix, -iy, zp), (-ix, -iy, zp)], up, WALL)
    b.face([(ix, -iy, zh), (ix, iy, zh), (ix, iy, zp), (ix, -iy, zp)], left, WALL)
    b.face([(ix, iy, zh), (-ix, iy, zh), (-ix, iy, zp), (ix, iy, zp)], down, WALL)
    b.face([(-ix, iy, zh), (-ix, -iy, zh), (-ix, -iy, zp), (-ix, iy, zp)], right, WALL)
    # roof deck
    b.face([(-ix, -iy, zh), (ix, -iy, zh), (ix, iy, zh), (-ix, iy, zh)], (0, 0, 1), TRIM)
    return b.bm


def main():
    args = parse_args()
    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)

    # Clean slate (factory startup scene has Cube/Light/Camera).
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            coll.remove(d)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    name = f"bld_block_{args.floors}f"
    bm = build_mesh(args.floors, args.width, args.depth)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(make_material("mat_wall", WALL_COLOR))
    mesh.materials.append(make_material("mat_trim", TRIM_COLOR))
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    bpy.ops.export_scene.gltf(
        filepath=out, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_materials="EXPORT", export_image_format="NONE",
        export_texcoords=False, export_normals=True, export_cameras=False,
        export_lights=False, export_extras=False, export_draco_mesh_compression_enable=False)

    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    dims = obj.dimensions
    print(f"lowpoly_block: {name} tris={tris} verts={len(mesh.vertices)} "
          f"size(m)={dims.x:.3f}x{dims.y:.3f}x{dims.z:.3f} -> {out}")


main()
