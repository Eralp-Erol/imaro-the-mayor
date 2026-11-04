"""T-057 LOD2 experiment (Teknik karar 4, 4.2): visibility-ordered bit-exact subset of the plane-tree LOD1.

Run: uv run --with pillow==11.3.0 python experiments/t057-lod2/build.py [--out-dir D] [--prov-dir D]
Pure Python (Pillow only reads the atlas). Deterministic: no timestamps, no randomness, no absolute paths.
Fixed constants (VIEWS=17, PX_PER_M=24, ALPHA=0.45, COVER 0.98, CLUSTER 0.90, WOOD 0.95) are NOT tunable.
Any structural deviation from the expected 64 leaf x 2 tri + 20 wood x 8 tri raises and stops (no heuristics).
"""
import argparse
import hashlib
import json
import math
import struct
import sys
from array import array
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VEG = ROOT / 'assets/hero/vegetation'
SRC_GLB = VEG / 'veg_hero_plane_a_lod1.glb'
ATLAS = VEG / 'vegetation_atlas.png'
LAYOUT = VEG / 'atlas_layout.json'
OUT_DEFAULT = VEG / 'lod2_experiment'
PROV_DEFAULT = Path(__file__).resolve().parent

# ---- fixed constants (spec 4.2 step 4/5), never changed after seeing results ----
PX_PER_M = 24
ALPHA_CUT = 0.45
COVER_NUM, COVER_DEN = 98, 100      # total alpha coverage >= 0.98 x LOD1
CLUSTER_NUM, CLUSTER_DEN = 90, 100  # per-cluster card union >= 0.90 x LOD1
WOOD_NUM, WOOD_DEN = 95, 100        # front-visible wood pixels >= 0.95 x LOD1
VIEWS = [(az, el) for el in (12, 40) for az in range(0, 360, 45)] + [(0, 90)]
assert len(VIEWS) == 17
EXPECT_LEAF, EXPECT_WOOD, ALPHA_BYTE_MIN = 64, 20, math.ceil(ALPHA_CUT * 255 - 1e-9)  # 115


class SpecStop(Exception):
    """Structure differs from the spec's expectation: stop, no heuristic repair."""


# ------------------------------------------------------------------ GLB read
def read_glb(path):
    raw = Path(path).read_bytes()
    magic, version, total = struct.unpack_from('<4sII', raw, 0)
    assert magic == b'glTF' and version == 2 and total == len(raw)
    jl, jt = struct.unpack_from('<I4s', raw, 12)
    assert jt == b'JSON'
    gj = json.loads(raw[20:20 + jl])
    bo = 20 + jl
    bl, bt = struct.unpack_from('<I4s', raw, bo)
    assert bt == b'BIN\x00'
    binary = raw[bo + 8:bo + 8 + bl]
    return gj, binary, raw


def accessor_bytes(gj, binary, idx):
    a = gj['accessors'][idx]
    v = gj['bufferViews'][a['bufferView']]
    size = {'VEC3': 12, 'VEC2': 8, 'SCALAR': 2}[a['type']]
    assert 'byteStride' not in v and a.get('byteOffset', 0) == 0
    off = v.get('byteOffset', 0)
    return binary[off:off + a['count'] * size], a['count']


def load_mesh(path):
    gj, binary, raw = read_glb(path)
    prim = gj['meshes'][0]['primitives'][0]
    assert len(gj['meshes']) == 1 and len(gj['meshes'][0]['primitives']) == 1
    pb, n = accessor_bytes(gj, binary, prim['attributes']['POSITION'])
    nb, _ = accessor_bytes(gj, binary, prim['attributes']['NORMAL'])
    ub, _ = accessor_bytes(gj, binary, prim['attributes']['TEXCOORD_0'])
    ib, ni = accessor_bytes(gj, binary, prim['indices'])
    assert gj['accessors'][prim['indices']]['componentType'] == 5123
    pos = [struct.unpack_from('<3f', pb, 12 * i) for i in range(n)]
    uv = [struct.unpack_from('<2f', ub, 8 * i) for i in range(n)]
    idx = list(struct.unpack('<%dH' % ni, ib))
    tris = [tuple(idx[i:i + 3]) for i in range(0, ni, 3)]
    return dict(gj=gj, raw=raw, pb=pb, nb=nb, ub=ub, pos=pos, uv=uv, tris=tris, n=n)


def to_blender(p):
    """glTF (x, y_up, z) -> Blender Z-up (x, -z, y)."""
    return (p[0], -p[2], p[1])


# ------------------------------------------------------------------ atlas
def load_alpha():
    from PIL import Image
    im = Image.open(ATLAS).convert('RGBA')
    assert im.size == (1024, 1024)
    return im.getchannel('A').tobytes(), im.tobytes()


def tri_region(uvs, regions):
    for name in ('bark', 'plane'):
        x, y, w, h = regions[name]
        if all(x <= u * 1024 <= x + w and y <= v * 1024 <= y + h for u, v in uvs):
            return name
    return None


# ------------------------------------------------------------------ step 2: components / elements
def parse_elements(m):
    """Weld by exact float32 position, extract components, classify, derive segments/clusters."""
    regions = json.loads(LAYOUT.read_text())['regions']
    tris, pos, uv = m['tris'], m['pos'], m['uv']
    parent = list(range(len(tris)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    first_by_pos = {}
    for ti, t in enumerate(tris):
        for vi in t:
            k = pos[vi]
            if k in first_by_pos:
                ra, rb = find(first_by_pos[k]), find(ti)
                if ra != rb:
                    parent[max(ra, rb)] = min(ra, rb)
            else:
                first_by_pos[k] = ti
    groups = {}
    for ti in range(len(tris)):
        groups.setdefault(find(ti), []).append(ti)
    comps = sorted(groups.values(), key=lambda g: g[0])  # GLB triangle order
    elements = []
    for c in comps:
        classes = {tri_region([uv[v] for v in tris[ti]], regions) for ti in c}
        if len(classes) != 1 or None in classes:
            raise SpecStop('component with mixed/unknown atlas region: tris %s -> %s' % (c[:3], classes))
        elements.append(dict(tris=c, kind=classes.pop()))
    leaf = [e for e in elements if e['kind'] == 'plane']
    wood = [e for e in elements if e['kind'] == 'bark']
    if not (len(leaf) == EXPECT_LEAF and all(len(e['tris']) == 2 for e in leaf)
            and len(wood) == EXPECT_WOOD and all(len(e['tris']) == 8 for e in wood)):
        raise SpecStop('P1: expected 64 leaf x2 + 20 wood x8, got leaf=%s wood=%s' % (
            sorted(Counter(len(e['tris']) for e in leaf).items()),
            sorted(Counter(len(e['tris']) for e in wood).items())))
    for i, e in enumerate(elements):
        e['id'] = i
    # wood segments: rings are the two groups of unique positions that share a UV row (v)
    for e in wood:
        # rings = the vertex records sharing one UV row (v). The tube seam duplicates one ring position with
        # a ~1e-16 difference (exact welding keeps it split), so rings are averaged over vertex records (8 per ring).
        rows = {}
        for vi in sorted({vi for ti in e['tris'] for vi in tris[ti]}):
            rows.setdefault(uv[vi][1], []).append(pos[vi])
        if sorted(len(r) for r in rows.values()) != [8, 8]:
            raise SpecStop('wood segment rings are not 8+8 vertex records: %s' % e['id'])
        rings = []
        for r in rows.values():
            bp = [to_blender(p) for p in r]
            c = tuple(sum(q[i] for q in bp) / 8 for i in range(3))
            rad = sum(math.dist(q, c) for q in bp) / 8
            rings.append((rad, c, bp))
        rings.sort(key=lambda t: -t[0])  # larger radius = proximal
        if abs(rings[0][0] - rings[1][0]) < 1e-6:
            raise SpecStop('segment has no radius gradient: %s' % e['id'])
        e['prox'], e['dist'] = rings[0][1], rings[1][1]
        e['prox_r'], e['dist_r'] = rings[0][0], rings[1][0]
        e['min_z'] = min(q[2] for q in rings[0][2] + rings[1][2])
    # parent relation: proximal centre vs parent's distal centre <= 1 mm
    for e in wood:
        e['parents'] = [p['id'] for p in wood if p is not e and math.dist(e['prox'], p['dist']) <= 1e-3]
        e['children'] = []
    for e in wood:
        if len(e['parents']) > 1:
            raise SpecStop('segment %s has >1 parents' % e['id'])
        for p in e['parents']:
            elements[p]['children'].append(e['id'])
    for e in wood:
        if len(e['children']) > 1:
            raise SpecStop('segment %s has >1 children' % e['id'])
    roots = [e for e in wood if not e['parents']]
    trunk_roots = [e for e in roots if e['min_z'] <= 0.0]
    branch_roots = [e for e in roots if e['min_z'] > 0.0]
    if len(trunk_roots) != 1 or len(branch_roots) != 8:
        raise SpecStop('expected 1 ground-touching root + 8 branch roots, got %d + %d' % (len(trunk_roots), len(branch_roots)))

    def chain(root):
        out = [root['id']]
        while elements[out[-1]]['children']:
            out.append(elements[out[-1]]['children'][0])
        return out
    trunk_chain = chain(trunk_roots[0])
    branch_chains = [chain(r) for r in branch_roots]  # GLB order of root triangle
    if len(trunk_chain) != 4 or any(len(c) != 2 for c in branch_chains):
        raise SpecStop('expected trunk chain 4 + 8 branch chains of 2')
    if len(set(trunk_chain) | {i for c in branch_chains for i in c}) != 20:
        raise SpecStop('chains do not cover all 20 wood segments')
    for ci, c in enumerate(branch_chains):
        for i in c:
            elements[i]['role'] = 'branch'
            elements[i]['branch'] = ci
    for i in trunk_chain:
        elements[i]['role'] = 'trunk'
    # clusters: card centroid -> nearest branch distal end, ties -> lowest branch index (GLB order)
    tips = [elements[c[-1]]['dist'] for c in branch_chains]
    for e in leaf:
        pts = {pos[vi] for ti in e['tris'] for vi in tris[ti]}
        if len(pts) != 4:
            raise SpecStop('card %s has %d positions' % (e['id'], len(pts)))
        bp = [to_blender(p) for p in sorted(pts)]
        cen = tuple(sum(q[i] for q in bp) / 4 for i in range(3))
        d = [math.dist(cen, t) for t in tips]
        e['cluster'] = d.index(min(d))
        e['role'] = 'card'
        e['centroid'] = cen
    # step 3: unremovable
    max_branch_base_z = max(elements[c[0]]['prox'][2] for c in branch_chains)
    for e in elements:
        e['pinned'] = None
        if e['kind'] != 'bark':
            continue
        if e['min_z'] <= 0.0:
            e['pinned'] = 'touches ground'
        elif e['role'] == 'trunk' and e['prox'][2] < max_branch_base_z:
            e['pinned'] = 'trunk proximal end below highest branch base'
        elif e['role'] == 'branch' and e['id'] in [c[0] for c in branch_chains]:
            e['pinned'] = 'first branch segment attached to trunk'
    return elements, dict(trunk_chain=trunk_chain, branch_chains=branch_chains, max_branch_base_z=max_branch_base_z,
                          cluster_sizes=sorted(Counter(e['cluster'] for e in leaf).items()))


# ------------------------------------------------------------------ step 4: raster
def view_basis(az, el):
    a, e = math.radians(az), math.radians(el)
    d = (math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))
    if el == 90:
        r = (1.0, 0.0, 0.0)
    else:
        n = math.hypot(d[0], d[1])
        r = (-d[1] / n, d[0] / n, 0.0)
    u = (d[1] * r[2] - d[2] * r[1], d[2] * r[0] - d[0] * r[2], d[0] * r[1] - d[1] * r[0])
    return d, r, u


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


class View:
    def __init__(self, az, el, all_pos_b):
        self.az, self.el = az, el
        self.d, self.r, self.u = view_basis(az, el)
        xs = [dot(p, self.r) * PX_PER_M for p in all_pos_b]
        ys = [dot(p, self.u) * PX_PER_M for p in all_pos_b]
        self.x0, self.y0 = math.floor(min(xs)) - 1, math.floor(min(ys)) - 1
        self.w = math.ceil(max(xs)) + 2 - self.x0
        self.h = math.ceil(max(ys)) + 2 - self.y0

    def project(self, p):
        return (dot(p, self.r) * PX_PER_M - self.x0, dot(p, self.u) * PX_PER_M - self.y0, dot(p, self.d))


def rasterize(view, pb, uvs3, alpha):
    """Return (pixels_all_count, pass_pixels array('i'), pass_depth array('d')). Inclusive edges, no culling."""
    P = [view.project(p) for p in pb]
    (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = P
    den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
    if abs(den) < 1e-12:
        return 0, array('i'), array('d')
    inv = 1.0 / den
    xmin = max(0, math.floor(min(x0, x1, x2) - 0.5))
    xmax = min(view.w - 1, math.ceil(max(x0, x1, x2) - 0.5))
    ymin = max(0, math.floor(min(y0, y1, y2) - 0.5))
    ymax = min(view.h - 1, math.ceil(max(y0, y1, y2) - 0.5))
    (u0, v0), (u1, v1), (u2, v2) = uvs3
    cnt = 0
    pp, pd = array('i'), array('d')
    for py in range(ymin, ymax + 1):
        cy = py + 0.5
        for px in range(xmin, xmax + 1):
            cx = px + 0.5
            l0 = ((y1 - y2) * (cx - x2) + (x2 - x1) * (cy - y2)) * inv
            l1 = ((y2 - y0) * (cx - x2) + (x0 - x2) * (cy - y2)) * inv
            l2 = 1.0 - l0 - l1
            if l0 < 0.0 or l1 < 0.0 or l2 < 0.0:
                continue
            cnt += 1
            u = l0 * u0 + l1 * u1 + l2 * u2
            v = l0 * v0 + l1 * v1 + l2 * v2
            tx = min(1023, max(0, math.floor(u * 1024)))
            ty = min(1023, max(0, math.floor(v * 1024)))
            if alpha[ty * 1024 + tx] >= ALPHA_BYTE_MIN:
                pp.append(py * view.w + px)
                pd.append(l0 * z0 + l1 * z1 + l2 * z2)
    return cnt, pp, pd


class Scene:
    """Per-view, per-triangle fragment tables for the full LOD1 (computed once)."""

    def __init__(self, m, elements, alpha):
        self.m, self.elements = m, elements
        posb = [to_blender(p) for p in m['pos']]
        self.views = [View(az, el, posb) for az, el in VIEWS]
        self.frag = []   # [view][tri] = (count_all, pix, depth)
        for v in self.views:
            row = []
            for t in m['tris']:
                row.append(rasterize(v, [posb[i] for i in t], [m['uv'][i] for i in t], alpha))
            self.frag.append(row)
        self.tri_elem = {}
        for e in elements:
            for ti in e['tris']:
                self.tri_elem[ti] = e['id']

    def metrics(self, active):
        """active: set of element ids. Returns per-view metrics, element front-pixel scores."""
        elements = self.elements
        order = sorted(ti for e in active for ti in elements[e]['tris'])
        scores = Counter()
        views = []
        for vi, v in enumerate(self.views):
            zb = [-1e300] * (v.w * v.h)
            ids = [-1] * (v.w * v.h)
            allpix = set()
            clus = {}
            for ti in order:
                _, pp, pd = self.frag[vi][ti]
                el = self.tri_elem[ti]
                allpix.update(pp)
                if elements[el]['kind'] == 'plane':
                    clus.setdefault(elements[el]['cluster'], set()).update(pp)
                for p, d in zip(pp, pd):
                    if d > zb[p]:
                        zb[p] = d
                        ids[p] = el
            c = Counter(ids)
            c.pop(-1, None)
            scores.update(c)
            wood_front = sum(n for e, n in c.items() if elements[e]['kind'] == 'bark')
            views.append(dict(coverage=len(allpix), wood_front=wood_front,
                              cluster={k: len(s) for k, s in sorted(clus.items())},
                              _ids=ids))
        return views, scores

    def fragment_area(self, active):
        tot = 0
        per = []
        for vi in range(len(self.views)):
            s = sum(self.frag[vi][ti][0] for e in active for ti in self.elements[e]['tris'])
            per.append(s)
            tot += s
        return tot, per


def violation(base, cur):
    """Return list of violated conditions (integers only, exact rational compare)."""
    bad = []
    for vi, (b, c) in enumerate(zip(base, cur)):
        if c['coverage'] * COVER_DEN < b['coverage'] * COVER_NUM:
            bad.append(dict(cond='a_total_coverage', view=vi, base=b['coverage'], now=c['coverage']))
        for k, bn in b['cluster'].items():
            cn = c['cluster'].get(k, 0)
            if cn * CLUSTER_DEN < bn * CLUSTER_NUM:
                bad.append(dict(cond='b_cluster_union', view=vi, cluster=k, base=bn, now=cn))
        if c['wood_front'] * WOOD_DEN < b['wood_front'] * WOOD_NUM:
            bad.append(dict(cond='c_wood_front', view=vi, base=b['wood_front'], now=c['wood_front']))
    return bad


def strip(vs):
    return [{k: v for k, v in x.items() if not k.startswith('_')} for x in vs]


# ------------------------------------------------------------------ step 5: greedy
def greedy(scene, elements):
    active = {e['id'] for e in elements}
    removable = [e['id'] for e in elements if e['pinned'] is None]
    base_views, scores = scene.metrics(active)
    history = {e['id']: [] for e in elements}
    removed, step, stop = [], 0, None
    cur_views = base_views
    while True:
        for e in active:
            history[e].append(scores.get(e, 0))
        cands = []
        for e in removable:
            if e not in active:
                continue
            if elements[e]['kind'] == 'bark' and any(c in active for c in elements[e]['children']):
                continue  # distal child still present
            cands.append(e)
        if not cands:
            stop = dict(step=step, reason='no removable element left')
            break
        pick = min(cands, key=lambda e: (scores.get(e, 0), elements[e]['tris'][0]))
        trial = active - {pick}
        tviews, tscores = scene.metrics(trial)
        bad = violation(base_views, tviews)
        if bad:
            stop = dict(step=step, reason='next removal would violate fixed coverage condition', candidate=pick,
                        candidate_score=scores.get(pick, 0), violations=bad)
            break
        removed.append(dict(step=step, element=pick, score=scores.get(pick, 0),
                            tris_after=sum(len(elements[e]['tris']) for e in trial)))
        active, scores, cur_views = trial, tscores, tviews
        step += 1
    return active, removed, stop, base_views, cur_views, history


# ------------------------------------------------------------------ step 6: GLB writer
def f32json(x):
    return float(x)


def write_glb(m, kept_tris, out_path, name_from='veg_hero_plane_a_lod1', name_to='veg_hero_plane_a_lod2'):
    remap, order = {}, []
    idx = []
    for t in kept_tris:
        for vi in m['tris'][t]:
            if vi not in remap:
                remap[vi] = len(order)
                order.append(vi)
            idx.append(remap[vi])
    pb = b''.join(m['pb'][12 * i:12 * i + 12] for i in order)
    nb = b''.join(m['nb'][12 * i:12 * i + 12] for i in order)
    ub = b''.join(m['ub'][8 * i:8 * i + 8] for i in order)
    ib = struct.pack('<%dH' % len(idx), *idx)
    ib_pad = ib + b'\0' * (-len(ib) % 4)
    g = json.loads(json.dumps(m['gj']))  # deep copy, key order preserved
    n = len(order)
    pos = [struct.unpack_from('<3f', pb, 12 * i) for i in range(n)]
    g['accessors'][0]['count'] = n
    g['accessors'][0]['min'] = [min(p[i] for p in pos) for i in range(3)]
    g['accessors'][0]['max'] = [max(p[i] for p in pos) for i in range(3)]
    g['accessors'][1]['count'] = n
    g['accessors'][2]['count'] = n
    g['accessors'][3]['count'] = len(idx)
    o = 0
    for bv, data in zip(g['bufferViews'], (pb, nb, ub, ib)):
        bv['byteOffset'], bv['byteLength'] = o, len(data)
        o += len(data)
    g['buffers'][0]['byteLength'] = len(pb) + len(nb) + len(ub) + len(ib_pad)
    assert len(pb) % 4 == len(nb) % 4 == len(ub) % 4 == 0
    g['images'][0]['uri'] = '../vegetation_atlas.png'
    for node in g['nodes']:
        node['name'] = node['name'].replace(name_from, name_to)
    for mesh in g['meshes']:
        mesh['name'] = mesh['name'].replace(name_from, name_to)
    js = json.dumps(g, separators=(',', ':'), ensure_ascii=False).encode()
    js += b' ' * (-len(js) % 4)
    bin_ = pb + nb + ub + ib_pad
    out = struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(bin_))
    out += struct.pack('<I4s', len(js), b'JSON') + js + struct.pack('<I4s', len(bin_), b'BIN\0') + bin_
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_bytes(out)
    return out, n


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out-dir', default=str(OUT_DEFAULT))
    ap.add_argument('--prov-dir', default=str(PROV_DEFAULT))
    a = ap.parse_args()
    alpha, rgba = load_alpha()
    m = load_mesh(SRC_GLB)
    elements, structure = parse_elements(m)
    scene = Scene(m, elements, alpha)
    active, removed, stop, base_views, final_views, history = greedy(scene, elements)
    kept_tris = sorted(ti for e in active for ti in elements[e]['tris'])
    glb_path = Path(a.out_dir) / 'veg_hero_plane_a_lod2.glb'
    data, nverts = write_glb(m, kept_tris, glb_path)
    frag1, per1 = scene.fragment_area(set(e['id'] for e in elements))
    frag2, per2 = scene.fragment_area(active)
    tri1, tri2 = len(m['tris']), len(kept_tris)

    def view_rows(vs):
        return [dict(view=VIEWS[i], coverage=v['coverage'], wood_front=v['wood_front'],
                     cluster=v['cluster']) for i, v in enumerate(strip(vs))]

    def ratios(vs, bs):
        rows = []
        for i, (v, b) in enumerate(zip(strip(vs), strip(bs))):
            rows.append(dict(view=VIEWS[i], az_el=list(VIEWS[i]),
                             coverage_ratio=v['coverage'] / b['coverage'],
                             wood_ratio=(v['wood_front'] / b['wood_front']) if b['wood_front'] else None,
                             cluster_ratio_min=min(v['cluster'][k] / b['cluster'][k] for k in b['cluster']),
                             cluster_ratio={str(k): v['cluster'][k] / b['cluster'][k] for k in b['cluster']}))
        return rows
    prov = dict(
        schema='t057-lod2-provenance-v1',
        spec='production/qa/T-057-technical-review.md Teknik karar 4 / 4.2',
        inputs={'veg_hero_plane_a_lod1.glb': sha(SRC_GLB), 'vegetation_atlas.png': sha(ATLAS),
                'atlas_layout.json': sha(LAYOUT), 'build.py': sha(__file__)},
        constants=dict(views=VIEWS, px_per_m=PX_PER_M, alpha_cut=ALPHA_CUT, alpha_byte_min=ALPHA_BYTE_MIN,
                       coverage_min=COVER_NUM / COVER_DEN, cluster_min=CLUSTER_NUM / CLUSTER_DEN, wood_min=WOOD_NUM / WOOD_DEN,
                       view_convention='Blender Z-up; camera direction d=(cos el cos az, cos el sin az, sin el); view 0 = az0/el12 ("front" for albedo diagnostic)',
                       alpha_model='alpha-passing fragments (nearest texel, base level, >=115/255) write depth/ID; failing fragments neither cover nor occlude'),
        structure=dict(leaf_components=EXPECT_LEAF, wood_components=EXPECT_WOOD, tri_per_leaf=2, tri_per_wood=8,
                       trunk_chain=structure['trunk_chain'], branch_chains=structure['branch_chains'],
                       max_branch_base_z_blender=structure['max_branch_base_z'], cluster_sizes=structure['cluster_sizes']),
        elements=[dict(id=e['id'], type=('leaf_card' if e['kind'] == 'plane' else 'wood_segment'), role=e['role'],
                       cluster=e.get('cluster', e.get('branch')), triangles=e['tris'],
                       parent=(e['parents'][0] if e.get('parents') else None),
                       pinned=e['pinned'], score_history=history[e['id']],
                       removed_step=next((r['step'] for r in removed if r['element'] == e['id']), None))
                  for e in elements],
        removal_order=removed,
        stop=stop,
        lod1=dict(triangles=tri1, vertices=m['n'], views=view_rows(base_views), fragment_area_px=frag1,
                  fragment_area_per_view=per1),
        lod2=dict(triangles=tri2, vertices=nverts, glb_bytes=len(data), views=view_rows(final_views), fragment_area_px=frag2,
                  fragment_area_per_view=per2, kept_triangle_indices=kept_tris, glb_sha256=hashlib.sha256(data).hexdigest()),
        ratios=ratios(final_views, base_views),
        fragment_area_ratio=frag2 / frag1,
        fragment_area_m2=dict(lod1=frag1 / PX_PER_M ** 2, lod2=frag2 / PX_PER_M ** 2),
        gain_gate=dict(cap=math.floor(0.6 * tri1), tri_ok=tri2 <= math.floor(0.6 * tri1), fragment_ratio_max=0.80,
                       fragment_ok=frag2 * 10 <= frag1 * 8),
        albedo_front_linear_mean=albedo_diag(scene, m, final_views, base_views, active, rgba, alpha),
    )
    pp = Path(a.prov_dir) / 'provenance.json'
    pp.parent.mkdir(parents=True, exist_ok=True)
    pp.write_text(json.dumps(prov, indent=1, sort_keys=False) + '\n')
    print('LOD1 tris', tri1, 'LOD2 tris', tri2, 'cap', prov['gain_gate']['cap'], 'fragment ratio %.4f' % prov['fragment_area_ratio'])
    print('removed', len(removed), 'stop:', stop['reason'] if stop else None)
    print('glb', glb_path, len(data), 'bytes')


def albedo_diag(scene, m, final_views, base_views, active, rgba, alpha):
    """Informational only: mean linear RGB of front-most fragments in view 0 (LOD1 vs LOD2)."""
    out = {}
    v = scene.views[0]
    posb = [to_blender(p) for p in m['pos']]

    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    lut = [lin(i) for i in range(256)]
    for label, act in (('lod1', {e['id'] for e in scene.elements}), ('lod2', active)):
        order = sorted(ti for e in act for ti in scene.elements[e]['tris'])
        zb, col = {}, {}
        for ti in order:
            t = m['tris'][ti]
            P = [v.project(posb[i]) for i in t]
            (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = P
            den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            if abs(den) < 1e-12:
                continue
            inv = 1.0 / den
            for py in range(max(0, math.floor(min(y0, y1, y2) - .5)), min(v.h - 1, math.ceil(max(y0, y1, y2) - .5)) + 1):
                for px in range(max(0, math.floor(min(x0, x1, x2) - .5)), min(v.w - 1, math.ceil(max(x0, x1, x2) - .5)) + 1):
                    cx, cy = px + .5, py + .5
                    l0 = ((y1 - y2) * (cx - x2) + (x2 - x1) * (cy - y2)) * inv
                    l1 = ((y2 - y0) * (cx - x2) + (x0 - x2) * (cy - y2)) * inv
                    l2 = 1.0 - l0 - l1
                    if l0 < 0 or l1 < 0 or l2 < 0:
                        continue
                    uu = sum(w * m['uv'][i][0] for w, i in zip((l0, l1, l2), t))
                    vv = sum(w * m['uv'][i][1] for w, i in zip((l0, l1, l2), t))
                    tx, ty = min(1023, max(0, math.floor(uu * 1024))), min(1023, max(0, math.floor(vv * 1024)))
                    o = (ty * 1024 + tx) * 4
                    if rgba[o + 3] < ALPHA_BYTE_MIN:
                        continue
                    d = l0 * z0 + l1 * z1 + l2 * z2
                    k = py * v.w + px
                    if d > zb.get(k, -1e300):
                        zb[k] = d
                        col[k] = (lut[rgba[o]], lut[rgba[o + 1]], lut[rgba[o + 2]])
        n = len(col)
        out[label] = dict(pixels=n, mean_rgb=[sum(c[i] for c in col.values()) / n for i in range(3)])
    return out


if __name__ == '__main__':
    try:
        main()
    except SpecStop as e:
        print('SPEC_STOP:', e, file=sys.stderr)
        sys.exit(2)
