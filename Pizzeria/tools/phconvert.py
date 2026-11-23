#!/usr/bin/env python3
"""Download CC0 assets from Poly Haven and convert them for the game.

Models (glTF) become a compact binary mesh (`<id>.mesh`) plus a JSON material
manifest (`<id>.json`) and resized JPEG/PNG textures. Surface textures and HDRIs
are downloaded as-is (resized). Everything lands in Pizzeria/Pizzeria/Res, which
Xcode copies flat into the app bundle.

Mesh format (little endian):
  b"PZM2", u32 partCount
  per part: u16 nameLen, name utf8,
            u32 primCount
            per prim: u32 materialIndex, u32 vertexCount, u32 indexCount,
                      u8 flags (1=uv, 2=tangent), u8 indexBytes, u16 pad,
                      f32 pos[v*3], f32 nrm[v*3], [f32 uv[v*2]], [f32 tan[v*4]], indices
"""
import io
import json
import os
import ssl
import struct
import sys
import urllib.request

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(ROOT, '..', 'Pizzeria', 'Res'))
CACHE = os.environ.get('PH_CACHE', '/tmp/ph-cache')
CA = '/root/.ccr/ca-bundle.crt'
UA = {'User-Agent': 'Mozilla/5.0 (pizzeria-asset-build)'}


def fetch(url):
    os.makedirs(CACHE, exist_ok=True)
    key = os.path.join(CACHE, url.replace('https://', '').replace('/', '_').replace('?', '_'))
    if os.path.exists(key):
        return open(key, 'rb').read()
    ctx = ssl.create_default_context(cafile=CA) if os.path.exists(CA) else None
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), context=ctx, timeout=120) as r:
        data = r.read()
    open(key, 'wb').write(data)
    return data


def files(asset):
    return json.loads(fetch(f'https://api.polyhaven.com/files/{asset}'))


COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_accessor(js, bins, idx):
    a = js['accessors'][idx]
    bv = js['bufferViews'][a['bufferView']]
    buf = bins[bv.get('buffer', 0)]
    dt = np.dtype(COMP[a['componentType']])
    n = NCOMP[a['type']]
    count = a['count']
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', 0) or dt.itemsize * n
    raw = np.frombuffer(buf, dtype=np.uint8, count=stride * (count - 1) + dt.itemsize * n, offset=off)
    if stride == dt.itemsize * n:
        arr = np.frombuffer(raw.tobytes(), dtype=dt).reshape(count, n)
    else:
        arr = np.lib.stride_tricks.as_strided(raw, shape=(count, dt.itemsize * n), strides=(stride, 1))
        arr = np.frombuffer(np.ascontiguousarray(arr).tobytes(), dtype=dt).reshape(count, n)
    if a.get('normalized'):
        info = np.iinfo(dt)
        arr = np.maximum(arr.astype(np.float32) / info.max, -1.0)
    return arr


def quat_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0],
        [0, 0, 0, 1]], dtype=np.float64)


def node_matrix(n):
    if 'matrix' in n:
        return np.array(n['matrix'], dtype=np.float64).reshape(4, 4).T
    m = np.eye(4)
    if 'scale' in n:
        m = np.diag(list(n['scale']) + [1]) @ m
    if 'rotation' in n:
        m = quat_mat(n['rotation']) @ m
    if 'translation' in n:
        t = np.eye(4)
        t[:3, 3] = n['translation']
        m = t @ m
    return m


def compute_tangents(pos, nrm, uv, idx):
    tan = np.zeros((len(pos), 3))
    bit = np.zeros((len(pos), 3))
    tri = idx.reshape(-1, 3)
    p0, p1, p2 = pos[tri[:, 0]], pos[tri[:, 1]], pos[tri[:, 2]]
    w0, w1, w2 = uv[tri[:, 0]], uv[tri[:, 1]], uv[tri[:, 2]]
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = w1 - w0, w2 - w0
    r = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    r = np.where(np.abs(r) < 1e-12, 1e-12, r)
    sdir = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / r[:, None]
    tdir = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) / r[:, None]
    for k in range(3):
        np.add.at(tan, tri[:, k], sdir)
        np.add.at(bit, tri[:, k], tdir)
    t = tan - nrm * np.sum(nrm * tan, axis=1, keepdims=True)
    ln = np.linalg.norm(t, axis=1, keepdims=True)
    fallback = np.cross(nrm, np.array([0, 1, 0.0001]))
    t = np.where(ln > 1e-8, t / np.maximum(ln, 1e-8), fallback / np.maximum(np.linalg.norm(fallback, axis=1, keepdims=True), 1e-8))
    w = np.where(np.sum(np.cross(nrm, t) * bit, axis=1) < 0, -1.0, 1.0)
    return np.concatenate([t, w[:, None]], axis=1)


def save_image(data, name, maxdim, keep_alpha=False):
    im = Image.open(io.BytesIO(data))
    has_alpha = keep_alpha and im.mode in ('RGBA', 'LA', 'P')
    im = im.convert('RGBA' if has_alpha else 'RGB')
    if max(im.size) > maxdim:
        s = maxdim / max(im.size)
        im = im.resize((max(4, int(im.width * s)), max(4, int(im.height * s))), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    if has_alpha:
        fn = name + '.png'
        im.save(os.path.join(OUT, fn), optimize=True)
    else:
        fn = name + '.jpg'
        im.save(os.path.join(OUT, fn), quality=82, optimize=True)
    return fn


def convert_model(asset, maxtex=512, parts=None, only=None, rename=None, res='1k'):
    """parts=None → bake everything into one part 'root'.
    parts='nodes' → one part per mesh node, in the node's local space.
    only → list of node names to keep (with parts='nodes') or to bake."""
    fl = files(asset)['gltf']
    entry = fl.get(res) or fl.get('1k') or next(iter(fl.values()))
    g = entry['gltf']
    js = json.loads(fetch(g['url']))
    base = g['url'].rsplit('/', 1)[0]
    include = g.get('include', {})

    def uri_data(uri):
        if uri in include:
            return fetch(include[uri]['url'])
        return fetch(base + '/' + uri)

    bins = [uri_data(b['uri']) for b in js['buffers']]
    out_name = rename or asset

    # Materials.
    tex_cache = {}

    def texture(ti, suffix, alpha=False, maxdim=maxtex):
        if ti is None:
            return None
        src = js['textures'][ti['index']]['source']
        uri = js['images'][src]['uri']
        key = (uri, alpha, maxdim)
        if key not in tex_cache:
            stem = os.path.splitext(os.path.basename(uri))[0]
            stem = stem.replace('_1k', '').replace('_2k', '').replace('_4k', '')
            tex_cache[key] = save_image(uri_data(uri), stem, maxdim, keep_alpha=alpha)
        return tex_cache[key]

    def build_material(m):
        pbr = m.get('pbrMetallicRoughness', {})
        alpha = m.get('alphaMode', 'OPAQUE')
        return {
            'name': m.get('name', ''),
            'diffuse': texture(pbr.get('baseColorTexture'), 'diff', alpha=alpha != 'OPAQUE'),
            'normal': texture(m.get('normalTexture'), 'nor'),
            'arm': texture(pbr.get('metallicRoughnessTexture'), 'arm', maxdim=max(256, maxtex // 2)),
            'ao': texture(m.get('occlusionTexture'), 'ao', maxdim=max(256, maxtex // 2)),
            'color': pbr.get('baseColorFactor', [1, 1, 1, 1]),
            'metal': pbr.get('metallicFactor', 1.0),
            'rough': pbr.get('roughnessFactor', 1.0),
            'alpha': alpha,
            'cutoff': m.get('alphaCutoff', 0.5),
            'doubleSided': m.get('doubleSided', False),
            'emissive': m.get('emissiveFactor', [0, 0, 0]),
        }

    default_mat = {'name': 'default', 'diffuse': None, 'normal': None, 'arm': None, 'ao': None, 'color': [0.8, 0.8, 0.8, 1],
                   'metal': 0, 'rough': 0.8, 'alpha': 'OPAQUE', 'cutoff': 0.5, 'doubleSided': False, 'emissive': [0, 0, 0]}
    src_mats = js.get('materials', [])
    mats = [None] * max(1, len(src_mats))

    # Walk the scene graph.
    collected = {}   # part name → {material: [chunks]}
    scene = js['scenes'][js.get('scene', 0)]

    def visit(ni, parent):
        n = js['nodes'][ni]
        world = parent @ node_matrix(n)
        if 'mesh' in n and (only is None or n.get('name') in only):
            if parts == 'nodes':
                part = n.get('name', f'node{ni}')
                xf = np.eye(4)
                if 'rotation' in n or 'scale' in n:
                    xf = node_matrix({k: v for k, v in n.items() if k in ('rotation', 'scale')})
            else:
                part = 'root'
                xf = world
            nm = np.linalg.inv(xf[:3, :3]).T
            for p in js['meshes'][n['mesh']]['primitives']:
                if p.get('mode', 4) != 4:
                    continue
                at = p['attributes']
                pos = read_accessor(js, bins, at['POSITION']).astype(np.float64)
                pos = (np.c_[pos, np.ones(len(pos))] @ xf.T)[:, :3]
                if 'NORMAL' in at:
                    nrm = read_accessor(js, bins, at['NORMAL']).astype(np.float64) @ nm.T
                    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
                else:
                    nrm = np.tile([0, 1, 0.0], (len(pos), 1))
                uv = read_accessor(js, bins, at['TEXCOORD_0']).astype(np.float64) if 'TEXCOORD_0' in at else None
                if 'indices' in p:
                    idx = read_accessor(js, bins, p['indices']).reshape(-1).astype(np.int64)
                else:
                    idx = np.arange(len(pos))
                if np.linalg.det(xf[:3, :3]) < 0:
                    idx = idx.reshape(-1, 3)[:, ::-1].reshape(-1)
                mi = p.get('material', 0)
                collected.setdefault(part, {}).setdefault(mi, []).append((pos, nrm, uv, idx))
        for c in n.get('children', []):
            visit(c, world)

    for ni in scene['nodes']:
        visit(ni, np.eye(4))

    for by_mat in collected.values():
        for mi in by_mat:
            if mats[mi] is None:
                mats[mi] = build_material(src_mats[mi]) if mi < len(src_mats) else dict(default_mat)
    mats = [m if m is not None else dict(default_mat, name='unused') for m in mats]

    blob = io.BytesIO()
    blob.write(b'PZM2')
    blob.write(struct.pack('<I', len(collected)))
    stats = []
    for part, by_mat in collected.items():
        nb = part.encode()
        blob.write(struct.pack('<H', len(nb)))
        blob.write(nb)
        blob.write(struct.pack('<I', len(by_mat)))
        for mi, chunks in by_mat.items():
            pos = np.concatenate([c[0] for c in chunks])
            nrm = np.concatenate([c[1] for c in chunks])
            has_uv = all(c[2] is not None for c in chunks)
            uv = np.concatenate([c[2] for c in chunks]) if has_uv else None
            idx_list, offset = [], 0
            for c in chunks:
                idx_list.append(c[3] + offset)
                offset += len(c[0])
            idx = np.concatenate(idx_list)
            has_tan = has_uv and mats[mi]['normal'] is not None
            tan = compute_tangents(pos, nrm, uv, idx) if has_tan else None
            vc = len(pos)
            ib = 2 if vc < 65536 else 4
            flags = (1 if has_uv else 0) | (2 if has_tan else 0)
            blob.write(struct.pack('<IIIBBH', mi, vc, len(idx), flags, ib, 0))
            blob.write(pos.astype('<f4').tobytes())
            blob.write(nrm.astype('<f4').tobytes())
            if has_uv:
                blob.write(uv.astype('<f4').tobytes())
            if has_tan:
                blob.write(tan.astype('<f4').tobytes())
            blob.write(idx.astype('<u2' if ib == 2 else '<u4').tobytes())
            stats.append(len(idx) // 3)
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, out_name + '.mesh'), 'wb').write(blob.getvalue())
    json.dump({'materials': mats, 'parts': list(collected.keys())}, open(os.path.join(OUT, out_name + '.json'), 'w'), indent=1)
    print(f'{out_name}: parts={len(collected)} tris={sum(stats)} mesh={len(blob.getvalue()) // 1024}KB textures={len(tex_cache)}')


def convert_surface(asset, maxdim=1024, rename=None, maps=('Diffuse', 'nor_gl', 'arm')):
    fl = files(asset)
    name = rename or asset
    suffix = {'Diffuse': 'diff', 'nor_gl': 'nor', 'arm': 'arm', 'Rough': 'rough', 'AO': 'ao'}
    for m in maps:
        if m not in fl:
            if m == 'arm' and 'Rough' in fl:
                m = 'Rough'
            else:
                print('  missing', asset, m)
                continue
        res = fl[m].get('1k') or fl[m].get('2k')
        url = res['jpg']['url']
        save_image(fetch(url), f'{name}_{suffix[m]}', maxdim if m != 'arm' else maxdim // 2)
    print(f'surface {name}')


def convert_hdri(asset, rename=None, res='1k'):
    fl = files(asset)['hdri']
    url = fl[res]['exr']['url']
    data = fetch(url)
    os.makedirs(OUT, exist_ok=True)
    fn = (rename or asset) + '.exr'
    open(os.path.join(OUT, fn), 'wb').write(data)
    print(f'hdri {fn} {len(data) // 1024}KB')


FACADE_PARTS = [
    'wall_standard_standard_01', 'wall_pier_standard_01',
    'wall_door_centered_large_01', 'door_centered_large_01',
    'wall_window_centered_large_01', 'window_centered_large_01',
    'wall_window_centered_large_02', 'window_centered_large_02',
    'wall_window_centered_large_03', 'window_centered_large_03',
    'wall_window_centered_double_02', 'window_centered_double_02',
    'wall_window_centered_double_03', 'window_centered_double_03',
    'base_standard_01', 'base_end_01', 'base_end_02',
    'dado_standard_standard_01', 'dado_end_01', 'dado_end_02',
    'cornice_standard_standard_01', 'cornice_end_01', 'cornice_end_02',
    'crown_standard_standard_01', 'crown_end_01', 'crown_end_02',
]

MODELS = [
    # id, max texture size, kwargs
    ('plastic_monobloc_chair_01', 512, {}),
    ('painted_wooden_chair_01', 512, {}),
    ('outdoor_table_chair_set_01', 512, {'parts': 'nodes'}),
    ('steel_frame_shelves_01', 512, {}),
    ('wooden_display_shelves_01', 512, {}),
    ('standing_chalkboard_01', 512, {}),
    ('modern_ceiling_lamp_01', 512, {}),
    ('hanging_industrial_lamp', 512, {}),
    ('industrial_wall_lamp', 256, {}),
    ('wall_clock', 512, {}),
    ('hanging_picture_frame_02', 512, {}),
    ('potted_plant_02', 512, {}),
    ('potted_plant_04', 256, {}),
    ('planter_box_01', 512, {}),
    ('WetFloorSign_01', 256, {}),
    ('plastic_broom', 256, {}),
    ('cardboard_box_01', 512, {}),
    ('plastic_crate_01', 512, {}),
    ('wooden_cutting_board', 256, {}),
    ('portable_generator', 512, {}),
    ('exterior_aircon_unit', 512, {'only': ['exterior_aircon_unit']}),
    ('metal_trash_can', 512, {'only': ['metal_trash_can', 'metal_trash_can_handle_left', 'metal_trash_can_handle_right', 'metal_trash_can_lid']}),
    ('street_lamp_01', 512, {}),
    ('utility_box_01', 512, {}),
    ('security_camera_01', 256, {}),
    ('rollershutter_door', 512, {'only': ['rollershutter_door']}),
    ('rollershutter_window_01', 512, {'parts': 'nodes'}),
    ('covered_car', 512, {}),
    ('water_manhole_cover', 256, {}),
    ('trashbag', 256, {}),
    ('modular_urban_apartments_facade', 1024, {'parts': 'nodes', 'rename': 'facade', 'only': FACADE_PARTS}),
]

SURFACES = [
    ('floor_tiles_06', 1024), ('herringbone_parquet', 1024), ('terracotta_floor_tiles', 1024),
    ('long_white_tiles', 1024), ('painted_plaster_wall', 1024), ('red_brick_03', 1024),
    ('beige_wall_002', 1024), ('rectangular_facade_tiles', 1024), ('patterned_concrete_pavers', 1024),
    ('asphalt_02', 1024), ('granular_concrete', 512), ('wood_table_001', 1024), ('oak_veneer_01', 1024),
    ('marble_01', 1024), ('large_red_bricks', 1024), ('yellow_plaster', 1024), ('painted_metal_shutter', 512),
    ('dark_wood', 512),
]

HDRIS = [('canary_wharf', 'env_day'), ('shanghai_bund', 'env_night')]


if __name__ == '__main__':
    what = sys.argv[1:] or ['models', 'surfaces', 'hdris']
    if 'models' in what:
        for asset, maxtex, kw in MODELS:
            convert_model(asset, maxtex, **kw)
    for a in what:
        if a.startswith('model:'):
            name = a.split(':', 1)[1]
            for asset, maxtex, kw in MODELS:
                if asset == name:
                    convert_model(asset, maxtex, **kw)
    if 'surfaces' in what:
        for asset, d in SURFACES:
            convert_surface(asset, d)
    if 'hdris' in what:
        for asset, name in HDRIS:
            convert_hdri(asset, name)
