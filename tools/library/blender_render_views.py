"""Blender (headless) worker for the library contact sheets (T-052). Run via tools/library/render_sheets.py:

  Blender --background --factory-startup --python tools/library/blender_render_views.py -- --job job.json

Job JSON: {"palette": path, "human_glb": path, "out_dir": dir, "size": px, "assets": [
  {"id", "glb", "rows": {"wall": "W2", "roof": "R3", "accent": "A1"}, "tier_m": 32, "views": [...]}]}

Colours come from the real game palette (assets/kit/kit_palette.json) and the glTF UV0 convention of the kit:
u = (part_id + 0.5) / 16 selects the part, v encodes the shade multiplier. Wall/roof/accent parts use the asset's
representative rows (first listed row of each kind in the manifest). Flat per-face shading, one fixed sun,
Standard view transform (no filmic/AgX), emissive flat ground in the neutral background colour.
Deterministic: no random, fixed camera/light.
"""
import json
import math
import sys

import bpy
from mathutils import Vector

BG_SRGB = (0.545, 0.565, 0.58)  # neutral cool grey, same value used by the PIL composer
SUN_ELEV_DEG = 52.0
SUN_AZ_DEG = -35.0  # fixed in world space: from front-left, so right/front facades are lit and left ones shaded


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


class Palette:
    def __init__(self, path):
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        self.rows = {}
        self.by_name = {}
        for r in data["rows"]:
            self.rows[r["row"]] = hex_rgb(r["hex"])
            self.by_name[r["name"]] = r["row"]
        self.parts = {p["id"]: p for p in data["parts"]}

    def part_color(self, part_id, rows):
        """sRGB colour (0..1) for a part id given the instance rows {'wall','roof','accent'} (row names)."""
        p = self.parts.get(part_id)
        if p is None:
            return (1.0, 0.0, 1.0)  # magenta = unknown part id (visible failure)
        if "row" in p:
            base = self.rows[p["row"]]
        else:
            kind = {"x": "wall", "y": "roof", "z": "accent"}[p["src"]]
            base = self.rows[self.by_name[rows[kind]]]
        m = p.get("mul", 1.0)
        return tuple(min(1.0, c * m) for c in base)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path, keep_suffix="_LOD0"):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    keep = []
    for o in new:
        if o.type == "MESH" and o.name.endswith(keep_suffix):
            keep.append(o)
        elif o.type == "MESH" and any(o.name.endswith(s) for s in ("_LOD1", "_PROXY")):
            bpy.data.objects.remove(o, do_unlink=True)
    return keep


def paint(obj, palette, rows, shade_flip=True):
    """Write a linear FLOAT_COLOR attribute from UV0 (part id in u, shade in v)."""
    mesh = obj.data
    uv = mesh.uv_layers.active
    if uv is None:
        return
    n = len(mesh.loops)
    uvs = [0.0] * (2 * n)
    uv.data.foreach_get("uv", uvs)  # read BEFORE adding the attribute (adding one invalidates `uv`)
    attr = mesh.color_attributes.new(name="lib_col", type="FLOAT_COLOR", domain="CORNER")
    cols = []
    for i in range(n):
        u, v = uvs[2 * i], uvs[2 * i + 1]
        part = int(math.floor(u * 16.0))
        shade = (1.0 - v) if shade_flip else v  # glTF importer flips V; the kit stores shade in glTF v
        c = palette.part_color(part, rows)
        cols.append([srgb_to_linear(c[0]) * shade, srgb_to_linear(c[1]) * shade, srgb_to_linear(c[2]) * shade, 1.0])
    flat = [x for c in cols for x in c]
    attr.data.foreach_set("color", flat)
    mesh.color_attributes.active_color = attr
    # Emission-free material that reads the vertex colour (diffuse only, matte).
    mat = bpy.data.materials.new("lib_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "lib_col"
    nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    for name in ("Specular IOR Level", "Metallic"):
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = 0.0
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def world_bbox(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for corner in o.bound_box:
            w = o.matrix_world @ Vector(corner)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def setup_world_and_light():
    scn = bpy.context.scene
    world = bpy.data.worlds.new("lib_world")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    lin = tuple(srgb_to_linear(c) for c in BG_SRGB)
    bg.inputs["Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    bg.inputs["Strength"].default_value = 0.55  # ambient fill
    scn.world = world
    sun = bpy.data.lights.new("lib_sun", "SUN")
    sun.energy = 3.2
    sun.angle = math.radians(12.0)  # soft edge
    sun.color = (1.0, 0.98, 0.94)  # plain daylight, slightly warm-neutral; NOT golden hour
    so = bpy.data.objects.new("lib_sun", sun)
    scn.collection.objects.link(so)
    # Sun points along -Z of its object; place it by rotation: elevation above horizon, azimuth from +Z (front) axis.
    el = math.radians(SUN_ELEV_DEG)
    az = math.radians(SUN_AZ_DEG)
    # direction the light travels (from sun to ground), game frame: x right, y up, z front. Blender: x, -z(front→y)...
    # We build in Blender coords (Z up, +Y = glTF -Z). Light comes FROM direction d_from (glTF frame):
    d_from_gltf = Vector((math.sin(az) * math.cos(el), math.sin(el), math.cos(az) * math.cos(el)))
    d_from = Vector((d_from_gltf.x, -d_from_gltf.z, d_from_gltf.y))  # glTF (x,y,z) -> Blender (x,-z,y)
    to = -d_from
    so.rotation_euler = to.to_track_quat("-Z", "Y").to_euler()
    # flat emissive ground in exact background colour (hides the foundation skirt, no horizon)
    bpy.ops.mesh.primitive_plane_add(size=1000.0, location=(0, 0, 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("lib_ground")
    gm.use_nodes = True
    nt = gm.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    ground.data.materials.append(gm)
    ground.visible_shadow = False
    return ground


def configure_render(size):
    scn = bpy.context.scene
    engines = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else engines[0]
    scn.render.resolution_x = size
    scn.render.resolution_y = size
    scn.render.resolution_percentage = 100
    scn.render.image_settings.file_format = "PNG"
    scn.render.film_transparent = False
    scn.view_settings.view_transform = "Standard"
    scn.view_settings.look = "None"
    scn.display_settings.display_device = "sRGB"
    try:
        scn.eevee.taa_render_samples = 32
        scn.eevee.use_shadows = True
    except AttributeError:
        pass


def make_camera(kind, center, tier, dist=200.0):
    cam_data = bpy.data.cameras.new("lib_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = tier
    cam_data.clip_start = 1.0
    cam_data.clip_end = 1000.0
    cam = bpy.data.objects.new("lib_cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    # views: (azimuth deg from +Z front axis, pitch deg above horizon); top = 90
    table = {"front": (0.0, 14.0), "fr34": (38.0, 30.0), "rl34": (218.0, 30.0), "top": (0.0, 90.0),
             "scale": (0.0, 10.0)}
    az, pitch = table[kind]
    a, p = math.radians(az), math.radians(pitch)
    d_gltf = Vector((math.sin(a) * math.cos(p), math.sin(p), math.cos(a) * math.cos(p)))
    d = Vector((d_gltf.x, -d_gltf.z, d_gltf.y))
    cam.location = center + d * dist
    direction = (center - cam.location).normalized()
    up = Vector((0, 0, 1))
    if kind == "top":
        pass
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    if kind == "top":
        cam.rotation_euler = (0.0, 0.0, 0.0)  # looking down -Z with +Y up in the image = front (-Y blender) at bottom
        cam.location = center + Vector((0, 0, dist))
    return cam


def render_asset(a, palette, human_glb, out_dir, size):
    reset_scene()
    configure_render(size)
    setup_world_and_light()
    objs = import_glb(a["glb"])
    for o in objs:
        paint(o, palette, a["rows"])
    lo, hi = world_bbox(objs)
    # Human reference (1.75 m) beside the front-right corner, standing on the ground, facing the viewer (+Z front).
    human = import_glb(human_glb)
    for o in human:
        paint(o, palette, {"wall": "W5", "roof": "R7", "accent": "A2"})
        pass
    # glTF (x,y,z) -> Blender (x,-z,y): front (+Z glTF) is Blender -Y. Front-right corner = (hi.x, min Blender y).
    for o in human:
        o.location = Vector((hi.x + 1.4, lo.y - 1.2, 0.0))
    center_xy = Vector(((lo.x + hi.x) / 2.0 + 0.7, (lo.y + hi.y) / 2.0 - 0.6, 0.0))
    center = Vector((center_xy.x, center_xy.y, max(hi.z, 1.75) / 2.0))
    out = {}
    human_pos = Vector((hi.x + 1.4, lo.y - 1.2, 1.3))
    for kind in a["views"]:
        if kind == "top":
            cam = make_camera(kind, Vector((center_xy.x, center_xy.y, 0.0)), a["tier_m"])
        elif kind == "scale":  # close-up: human next to the building's front-right corner, fixed 7 m frame
            cam = make_camera(kind, Vector((human_pos.x - 1.2, human_pos.y, 2.6)), 7.0)
        else:
            cam = make_camera(kind, center, a["tier_m"])
        path = "%s/%s__%s.png" % (out_dir, a["id"], kind)
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        out[kind] = path
        bpy.data.objects.remove(cam, do_unlink=True)
    return out


def main():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    job_path = argv[argv.index("--job") + 1]
    with open(job_path, "r", encoding="utf-8") as fh:
        job = json.load(fh)
    palette = Palette(job["palette"])
    for a in job["assets"]:
        render_asset(a, palette, job["human_glb"], job["out_dir"], job["size"])
        print("rendered", a["id"])


main()
