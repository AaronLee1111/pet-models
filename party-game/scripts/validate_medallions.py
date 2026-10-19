"""Offline regression checks for the exported kit and serialized Roblox mesh scale."""
import json, struct, xml.etree.ElementTree as ET
from pathlib import Path
root = Path(__file__).resolve().parents[1]
export = root / 'art/export/medallions_v1'
manifest = json.loads((export / 'manifest.json').read_text())
assets = {a['name']: a for a in manifest['assets']}
assert len(assets) == 15
for name, a in assets.items():
    data = (export / (name + '.glb')).read_bytes()
    assert data[:4] == b'glTF'
    length, kind = struct.unpack_from('<II', data, 12)
    gltf = json.loads(data[20:20 + length])
    triangles = sum(gltf['accessors'][p['indices']]['count'] // 3 for m in gltf['meshes'] for p in m['primitives'])
    assert triangles == a['triangles'], name
    assert triangles <= (500 if '_Base_' in name else 80 if '_Inlay_' in name else 200)
    assert a['non_manifold_edges'] == 0 and a['material_count'] == 1
    assert a['pivot_studs'] == [0, 0, 0]
    assert all((export / (name + ext)).stat().st_size > 100 for ext in ['.fbx', '.glb'])
tree = ET.parse(root / 'src/server/Board/MedallionAssets.rbxmx')
for item in tree.findall('.//Item[@class="MeshPart"]'):
    props = item.find('Properties')
    name = props.find('string[@name="Name"]').text
    size = [float(props.find(f'Vector3[@name="Size"]/{axis}').text) for axis in 'XYZ']
    native = [float(props.find(f'Vector3[@name="InitialSize"]/{axis}').text) for axis in 'XYZ']
    assert all(abs(s / n - 1 / .28) < .001 for s, n in zip(size, native)), name
    assert props.find('bool[@name="CanCollide"]').text == 'false'
    assert max(size[0], size[2]) <= 12
maximum = 380 + 80 + max(a['triangles'] for n, a in assets.items() if '_Symbol_' in n)
assert maximum <= 780 and maximum * 40 <= 31200
print(f'PASS: 15 GLB/FBX pairs, topology receipts, budgets, pivots, collision and source mesh scale; conservative maximum {maximum} triangles/space, {maximum * 40}/40 spaces')
