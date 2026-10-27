"""T-057 LOD2 pre-gates P1..P5 and negatives N1/N2 (independent re-implementation, no import of build.py).

Run: uv run --with pillow==11.3.0 python experiments/t057-lod2/audit.py
  default            -> P1..P5 + both negatives, writes audit.json / negative-results.json / determinism.json
  --negative=vertex  -> N1 (perturb one LOD2 vertex by 1e-4 m, P2 must fail; exit 1 when it fails)
  --negative=card    -> N2 (delete the most visible kept card, P3 must fail; exit 1 when it fails)
Exit code is non-zero if any positive gate fails (including P4).
"""
import hashlib
import json
import math
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
VEG = ROOT / 'assets/hero/vegetation'
LOD1 = VEG / 'veg_hero_plane_a_lod1.glb'
LOD2 = VEG / 'lod2_experiment/veg_hero_plane_a_lod2.glb'
PROV = HERE / 'provenance.json'
SCRATCH = Path('/private/tmp/claude-501/-Users-eralperol-Documents-Projects-imaro-the-mayor-handover-imaro-m01-349562fb/4befd413-b71d-4411-9c44-6e96f796ef86/scratchpad')

# The six fixed constants are repeated here on purpose (independent of build.py).
PXM, ACUT = 24, 0.45
VIEWS = [(az, el) for el in (12, 40) for az in range(0, 360, 45)] + [(0, 90)]


def glb(path):
    raw = Path(path).read_bytes()
    jl = struct.unpack_from('<I', raw, 12)[0]
    j = json.loads(raw[20:20 + jl])
    bl = struct.unpack_from('<I', raw, 20 + jl)[0]
    b = raw[28 + jl:28 + jl + bl]

    def view(i, sz):
        a = j['accessors'][i]
        o = j['bufferViews'][a['bufferView']]['byteOffset']
        return [b[o + k * sz:o + (k + 1) * sz] for k in range(a['count'])]
    p = j['meshes'][0]['primitives'][0]
    P, N, U = (view(p['attributes'][k], s) for k, s in (('POSITION', 12), ('NORMAL', 12), ('TEXCOORD_0', 8)))
    ib = view(p['indices'], 2)
    idx = [struct.unpack('<H', x)[0] for x in ib]
    tris = [tuple(idx[i:i + 3]) for i in range(0, len(idx), 3)]
    return dict(j=j, P=P, N=N, U=U, tris=tris, raw=raw)


def f3(bts):
    return struct.unpack('<3f', bts)


def f2(bts):
    return struct.unpack('<2f', bts)


def tri_key(g, t):
    return tuple((g['P'][i], g['N'][i], g['U'][i]) for i in t)


def region_of(uvs, regions):
    for nm in ('bark', 'plane'):
        x, y, w, h = regions[nm]
        if all(x <= u * 1024 <= x + w and y <= v * 1024 <= y + h for u, v in uvs):
            return nm
    return None


# -------------------------------------------------- P1
def p1(g1):
    regions = json.loads((VEG / 'atlas_layout.json').read_text())['regions']
    comp = {}
    for ti, t in enumerate(g1['tris']):
        for i in t:
            comp.setdefault(f3(g1['P'][i]), set()).add(ti)
    seen, comps = set(), []
    for ti in range(len(g1['tris'])):
        if ti in seen:
            continue
        st, grp = [ti], set()
        while st:
            x = st.pop()
            if x in grp:
                continue
            grp.add(x)
            for i in g1['tris'][x]:
                st.extend(comp[f3(g1['P'][i])] - grp)
        seen |= grp
        comps.append(sorted(grp))
    leaf = [c for c in comps if {region_of([f2(g1['U'][i]) for i in g1['tris'][t]], regions) for t in c} == {'plane'}]
    wood = [c for c in comps if {region_of([f2(g1['U'][i]) for i in g1['tris'][t]], regions) for t in c} == {'bark'}]
    ok = len(leaf) == 64 and all(len(c) == 2 for c in leaf) and len(wood) == 20 and all(len(c) == 8 for c in wood) and len(leaf) + len(wood) == len(comps)
    return dict(ok=ok, leaf_components=len(leaf), wood_components=len(wood), total_components=len(comps))


# -------------------------------------------------- P2
def p2(g1, g2):
    pool = {}
    for ti, t in enumerate(g1['tris']):
        pool.setdefault(tri_key(g1, t), []).append(ti)
    match, missing, dup = [], 0, 0
    used = set()
    for t in g2['tris']:
        c = [x for x in pool.get(tri_key(g2, t), []) if x not in used]
        if not c:
            missing += 1
            match.append(None)
            continue
        used.add(c[0])
        match.append(c[0])
    mat_same = g1['j']['materials'] == g2['j']['materials'] and g1['j']['samplers'] == g2['j']['samplers']
    uri_ok = g2['j']['images'][0]['uri'] == '../vegetation_atlas.png'
    in_order = all(a < b for a, b in zip([m for m in match if m is not None], [m for m in match if m is not None][1:]))
    used_verts = {i for t in g2['tris'] for i in t}
    return dict(ok=missing == 0 and mat_same and uri_ok and in_order and len(used_verts) == len(g2['P']),
                lod2_triangles=len(g2['tris']), not_bit_equal_in_lod1=missing, material_json_identical=mat_same,
                uri_ok=uri_ok, order_preserved=in_order, no_unused_vertices=len(used_verts) == len(g2['P'])), match


# -------------------------------------------------- P3: independent raster (per-pixel plane equations)
def basis(az, el):
    a, e = math.radians(az), math.radians(el)
    d = (math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))
    if el == 90:
        r = (1.0, 0.0, 0.0)
    else:
        h = math.hypot(d[0], d[1])
        r = (-d[1] / h, d[0] / h, 0.0)
    u = (d[1] * r[2] - d[2] * r[1], d[2] * r[0] - d[0] * r[2], d[0] * r[1] - d[1] * r[0])
    return d, r, u


def to_b(p):
    return (p[0], -p[2], p[1])


def dt(a, b):
    return sum(x * y for x, y in zip(a, b))


def load_alpha():
    from PIL import Image
    return Image.open(VEG / 'vegetation_atlas.png').convert('RGBA').getchannel('A').tobytes()


def raster_mesh(g, ref_pts_b, alpha, regions, extra_skip=()):
    """Per view: front-id map (alpha-passing only), all-fragment count. Returns list of dict."""
    n = len(g['tris'])
    P = [[to_b(f3(g['P'][i])) for i in t] for t in g['tris']]
    U = [[f2(g['U'][i]) for i in t] for t in g['tris']]
    kind = [region_of(u, regions) for u in U]
    out = []
    for az, el in VIEWS:
        d, r, u = basis(az, el)
        xs = [dt(p, r) * PXM for p in ref_pts_b]
        ys = [dt(p, u) * PXM for p in ref_pts_b]
        x0, y0 = math.floor(min(xs)) - 1, math.floor(min(ys)) - 1
        W, H = math.ceil(max(xs)) + 2 - x0, math.ceil(max(ys)) + 2 - y0
        best = {}
        frag_all = 0
        for ti in range(n):
            if ti in extra_skip:
                continue
            q = [(dt(p, r) * PXM - x0, dt(p, u) * PXM - y0, dt(p, d)) for p in P[ti]]
            (ax, ay, az_), (bx, by, bz), (cx, cy, cz) = q
            area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
            if abs(area) < 1e-12:
                continue
            # depth plane z = z_a + gx*(x-ax) + gy*(y-ay)
            gx = ((bz - az_) * (cy - ay) - (cz - az_) * (by - ay)) / area
            gy = ((cz - az_) * (bx - ax) - (bz - az_) * (cx - ax)) / area
            (ua, va), (ub, vb), (uc, vc) = U[ti]
            ux = ((ub - ua) * (cy - ay) - (uc - ua) * (by - ay)) / area
            uy = ((uc - ua) * (bx - ax) - (ub - ua) * (cx - ax)) / area
            vx = ((vb - va) * (cy - ay) - (vc - va) * (by - ay)) / area
            vy = ((vc - va) * (bx - ax) - (vb - va) * (cx - ax)) / area
            for py in range(max(0, math.floor(min(ay, by, cy))), min(H - 1, math.ceil(max(ay, by, cy))) + 1):
                for px in range(max(0, math.floor(min(ax, bx, cx))), min(W - 1, math.ceil(max(ax, bx, cx))) + 1):
                    X, Y = px + .5, py + .5
                    s0 = (bx - ax) * (Y - ay) - (by - ay) * (X - ax)
                    s1 = (cx - bx) * (Y - by) - (cy - by) * (X - bx)
                    s2 = (ax - cx) * (Y - cy) - (ay - cy) * (X - cx)
                    if area > 0:
                        inside = s0 >= 0 and s1 >= 0 and s2 >= 0
                    else:
                        inside = s0 <= 0 and s1 <= 0 and s2 <= 0
                    if not inside:
                        continue
                    frag_all += 1
                    uu = ua + ux * (X - ax) + uy * (Y - ay)
                    vv = va + vx * (X - ax) + vy * (Y - ay)
                    tx, ty = min(1023, max(0, int(math.floor(uu * 1024)))), min(1023, max(0, int(math.floor(vv * 1024))))
                    if alpha[ty * 1024 + tx] / 255.0 < ACUT:
                        continue
                    zz = az_ + gx * (X - ax) + gy * (Y - ay)
                    k = py * W + px
                    if k not in best or zz > best[k][0]:
                        best[k] = (zz, ti)
        out.append(dict(best=best, frag_all=frag_all, kind=kind))
    return out


def metrics(raster, card_cluster):
    """card_cluster: {tri index -> cluster}. Union masks need per-tri pixels -> recomputed from 'best'? No: need all alpha-passing
    fragments of each cluster, regardless of occlusion; handled in cluster_union()."""
    res = []
    for v in raster:
        wood = sum(1 for (_, ti) in v['best'].values() if v['kind'][ti] == 'bark')
        res.append(dict(coverage=len(v['best']), wood=wood, frag_all=v['frag_all']))
    return res


def cluster_union(g, ref_pts_b, alpha, regions, card_cluster):
    P = [[to_b(f3(g['P'][i])) for i in t] for t in g['tris']]
    U = [[f2(g['U'][i]) for i in t] for t in g['tris']]
    out = []
    for az, el in VIEWS:
        d, r, u = basis(az, el)
        xs = [dt(p, r) * PXM for p in ref_pts_b]
        ys = [dt(p, u) * PXM for p in ref_pts_b]
        x0, y0 = math.floor(min(xs)) - 1, math.floor(min(ys)) - 1
        W = math.ceil(max(xs)) + 2 - x0
        H = math.ceil(max(ys)) + 2 - y0
        sets = {}
        for ti, cl in card_cluster.items():
            q = [(dt(p, r) * PXM - x0, dt(p, u) * PXM - y0) for p in P[ti]]
            (ax, ay), (bx, by), (cx, cy) = q
            area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
            if abs(area) < 1e-12:
                continue
            (ua, va), (ub, vb), (uc, vc) = U[ti]
            ux = ((ub - ua) * (cy - ay) - (uc - ua) * (by - ay)) / area
            uy = ((uc - ua) * (bx - ax) - (ub - ua) * (cx - ax)) / area
            vx = ((vb - va) * (cy - ay) - (vc - va) * (by - ay)) / area
            vy = ((vc - va) * (bx - ax) - (vb - va) * (cx - ax)) / area
            s = sets.setdefault(cl, set())
            for py in range(max(0, math.floor(min(ay, by, cy))), min(H - 1, math.ceil(max(ay, by, cy))) + 1):
                for px in range(max(0, math.floor(min(ax, bx, cx))), min(W - 1, math.ceil(max(ax, bx, cx))) + 1):
                    X, Y = px + .5, py + .5
                    s0 = (bx - ax) * (Y - ay) - (by - ay) * (X - ax)
                    s1 = (cx - bx) * (Y - by) - (cy - by) * (X - bx)
                    s2 = (ax - cx) * (Y - cy) - (ay - cy) * (X - cx)
                    if not ((s0 >= 0 and s1 >= 0 and s2 >= 0) if area > 0 else (s0 <= 0 and s1 <= 0 and s2 <= 0)):
                        continue
                    uu = ua + ux * (X - ax) + uy * (Y - ay)
                    vv = va + vx * (X - ax) + vy * (Y - ay)
                    tx, ty = min(1023, max(0, int(math.floor(uu * 1024)))), min(1023, max(0, int(math.floor(vv * 1024))))
                    if alpha[ty * 1024 + tx] / 255.0 >= ACUT:
                        s.add(py * W + px)
        out.append({k: len(v) for k, v in sets.items()})
    return out


def p3(g1, g2, match, prov, alpha, skip_lod2=()):
    regions = json.loads((VEG / 'atlas_layout.json').read_text())['regions']
    ref = [to_b(f3(p)) for p in g1['P']]
    elem_of = {}
    for e in prov['elements']:
        for t in e['triangles']:
            elem_of[t] = e
    cl1 = {t: e['cluster'] for t, e in elem_of.items() if e['type'] == 'leaf_card'}
    cl2 = {i: cl1[m] for i, m in enumerate(match) if m is not None and m in cl1}
    r1 = raster_mesh(g1, ref, alpha, regions)
    r2 = raster_mesh(g2, ref, alpha, regions, extra_skip=set(skip_lod2))
    m1, m2 = metrics(r1, cl1), metrics(r2, cl2)
    c1 = cluster_union(g1, ref, alpha, regions, cl1)
    c2 = cluster_union(g2, ref, alpha, regions, {k: v for k, v in cl2.items() if k not in set(skip_lod2)})
    rows, ok = [], True
    for vi in range(len(VIEWS)):
        cov_ok = m2[vi]['coverage'] * 100 >= m1[vi]['coverage'] * 98
        wood_ok = m2[vi]['wood'] * 100 >= m1[vi]['wood'] * 95
        clu = {k: (c2[vi].get(k, 0), c1[vi][k], c2[vi].get(k, 0) * 100 >= c1[vi][k] * 90) for k in c1[vi]}
        clu_ok = all(x[2] for x in clu.values())
        ok &= cov_ok and wood_ok and clu_ok
        rows.append(dict(view=VIEWS[vi], coverage=[m2[vi]['coverage'], m1[vi]['coverage'], m2[vi]['coverage'] / m1[vi]['coverage']],
                         cov_ok=cov_ok, wood=[m2[vi]['wood'], m1[vi]['wood'], (m2[vi]['wood'] / m1[vi]['wood']) if m1[vi]['wood'] else None],
                         wood_ok=wood_ok, cluster_min_ratio=min(x[0] / x[1] for x in clu.values()), cluster_ok=clu_ok))
    frag1 = sum(m['frag_all'] for m in m1)
    frag2 = sum(m['frag_all'] for m in m2)
    # provenance cross-check (informational delta)
    pv = prov['lod2']['views']
    delta = max(abs(rows[i]['coverage'][0] - pv[i]['coverage']) for i in range(17))
    return dict(ok=ok, views=rows, fragment_px=[frag2, frag1], fragment_ratio=frag2 / frag1,
                max_abs_coverage_px_delta_vs_build=delta), r2, cl2


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def p5():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    outs = []
    for k in (1, 2):
        d = SCRATCH / ('run%d' % k)
        d.mkdir(exist_ok=True)
        r = subprocess.run([sys.executable, '-I', str(HERE / 'build.py'), '--out-dir', str(d / 'glb'), '--prov-dir', str(d / 'prov')],
                           capture_output=True, text=True)
        outs.append((r.returncode, d / 'glb/veg_hero_plane_a_lod2.glb', d / 'prov/provenance.json'))
    h = [(sha(g), sha(p)) for rc, g, p in outs]
    final = (sha(LOD2), sha(PROV))
    return dict(ok=all(o[0] == 0 for o in outs) and h[0] == h[1] == final, return_codes=[o[0] for o in outs],
                run1=dict(glb=h[0][0], provenance=h[0][1]), run2=dict(glb=h[1][0], provenance=h[1][1]),
                repo=dict(glb=final[0], provenance=final[1]), byte_equal_runs=h[0] == h[1], byte_equal_repo=h[0] == final)


def negative(kind):
    g1, g2 = glb(LOD1), glb(LOD2)
    prov = json.loads(PROV.read_text())
    alpha = load_alpha()
    failed = []
    if kind == 'vertex':
        x = f3(g2['P'][0])
        g2['P'][0] = struct.pack('<3f', x[0] + 1e-4, x[1], x[2])
        r, match = p2(g1, g2)
        if not r['ok']:
            failed.append('P2')
        print('N1 vertex[0].x %r -> %r ; P2 ok=%s not_bit_equal=%d' % (x[0], f3(g2['P'][0])[0], r['ok'], r['not_bit_equal_in_lod1']))
    else:
        # clean P2 first
        r2, match = p2(g1, g2)
        assert r2['ok']
        _, rast, cl2 = p3(g1, g2, match, prov, alpha)
        score = {}
        for v in rast:
            for _, ti in v['best'].values():
                score[ti] = score.get(ti, 0) + 1
        cards = [(score.get(i, 0), -i, i) for i in cl2]
        _, _, victim = max(cards)
        e = next(e for e in prov['elements'] if match[victim] in e['triangles'])
        skip = [i for i, mm in enumerate(match) if mm in e['triangles']]
        r, _, _ = p3(g1, g2, match, prov, alpha, skip_lod2=skip)
        if not r['ok']:
            failed.append('P3')
        bad = [(x['view'], x['cov_ok'], x['wood_ok'], x['cluster_ok']) for x in r['views'] if not (x['cov_ok'] and x['wood_ok'] and x['cluster_ok'])]
        print('N2 deleted LOD2 tris %s (element %d, cluster %s, front score %d); P3 ok=%s; failing views %s' % (
            skip, e['id'], e['cluster'], score.get(victim, 0), r['ok'], bad[:5]))
        json.dump(dict(deleted_lod2_triangles=skip, element=e['id'], front_score_px=score.get(victim, 0),
                       failing_views=bad), open(SCRATCH / 'n2_detail.json', 'w'), indent=1)
    print('FAILED_CHECKS', failed)
    sys.exit(1 if failed else 0)


def main():
    for a in sys.argv[1:]:
        if a.startswith('--negative='):
            negative(a.split('=')[1])
    g1, g2 = glb(LOD1), glb(LOD2)
    prov = json.loads(PROV.read_text())
    alpha = load_alpha()
    res = {}
    res['P1'] = p1(g1)
    res['P2'], match = p2(g1, g2)
    res['P3'], _, _ = p3(g1, g2, match, prov, alpha)
    tri1, tri2 = len(g1['tris']), len(g2['tris'])
    res['P4'] = dict(lod1_triangles=tri1, lod2_triangles=tri2, cap=math.floor(0.6 * tri1), tri_ok=tri2 <= math.floor(0.6 * tri1),
                     fragment_ratio=res['P3']['fragment_ratio'], fragment_limit=0.80,
                     fragment_ok=res['P3']['fragment_px'][0] * 10 <= res['P3']['fragment_px'][1] * 8)
    res['P4']['ok'] = res['P4']['tri_ok'] and res['P4']['fragment_ok']
    res['P5'] = p5()
    (HERE / 'determinism.json').write_text(json.dumps(res['P5'], indent=1) + '\n')
    negs = {}
    for kind, expect in (('vertex', 'P2'), ('card', 'P3')):
        r = subprocess.run([sys.executable, '-I', str(Path(__file__)), '--negative=' + kind], capture_output=True, text=True)
        lines = [l for l in r.stdout.splitlines() if l]
        failed_line = next((l for l in lines if l.startswith('FAILED_CHECKS')), '')
        negs['N1' if kind == 'vertex' else 'N2'] = dict(command='audit.py --negative=' + kind, exit_code=r.returncode,
                                                       expected_failed_check=expect, output=lines, ok=r.returncode != 0 and expect in failed_line)
    (HERE / 'negative-results.json').write_text(json.dumps(negs, indent=1) + '\n')
    res['negatives_ok'] = all(v['ok'] for v in negs.values())
    res['all_positive_gates_pass'] = all(res[k]['ok'] for k in ('P1', 'P2', 'P3', 'P4', 'P5'))
    res['inputs'] = dict(lod1=sha(LOD1), lod2=sha(LOD2), provenance=sha(PROV))
    (HERE / 'audit.json').write_text(json.dumps(res, indent=1) + '\n')
    for k in ('P1', 'P2', 'P3', 'P4', 'P5'):
        print(k, 'PASS' if res[k]['ok'] else 'FAIL')
    for k, v in negs.items():
        print(k, 'exit', v['exit_code'], 'OK' if v['ok'] else 'NOT-OK')
    sys.exit(0 if res['all_positive_gates_pass'] and res['negatives_ok'] else 1)


if __name__ == '__main__':
    main()
