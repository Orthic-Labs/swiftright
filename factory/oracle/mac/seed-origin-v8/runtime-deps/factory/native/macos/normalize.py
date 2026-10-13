"""Normalize measured F5 channels into v0.1 candidate capture; no inferred text/font."""
from decimal import Decimal
from pathlib import Path
import json
from factory.core.artifacts import canonical_hash, file_hash, provenance, validate_artifact, write_artifact

def measured(value):
    if isinstance(value, float):
        if value.is_integer(): return int(value)
        return {'$decimal': format(Decimal(str(value)), 'f').rstrip('0').rstrip('.')}
    if isinstance(value, list): return [measured(item) for item in value]
    if isinstance(value, dict): return {key: measured(item) for key, item in value.items()}
    return value

def normalize_run(directory: Path, manifest: dict, case: dict, run: int, channels: dict, binary_hash: str) -> dict:
    raw_file = directory / 'instrumented.raw.json'
    raw = json.loads(raw_file.read_text())
    clock = {'clockId': 'macos.dispatch.uptime', 'startNs': raw['monoStartNs'], 'endNs': raw['monoEndNs'], 'scope': 'same-process render interval only'}
    write_artifact(directory / 'clock.json', clock)
    layout = []
    placements = raw.get('rootLayout', {}).get('placements', [])
    if placements:
        frame = placements[-1]
        layout = [{'probeTag': manifest['channels']['geometry'][0]['probeTag'], 'viewIdentity': manifest['witness']['id'], 'frame': measured(frame)}]
    images = []
    for name in ('plain', 'instrumented', 'compositor'):
        raw_path, png = directory / f'{name}.raw.json', directory / f'{name}.png'
        if raw_path.exists() and png.exists():
            data = json.loads(raw_path.read_text())
            if data.get('status') == 'OBSERVED':
                image = data['image']
                images.append({'id': f'macos.{name}', 'hash': file_hash(png), 'widthPx': image['width'], 'heightPx': image['height'], 'captureScale': measured(image['scale'])})
    ax = []
    ax_file = directory / 'external-ax.raw.json'
    if ax_file.exists():
        from factory.native.macos.capture import witness_ax_nodes
        for index, node in enumerate(witness_ax_nodes(json.loads(ax_file.read_text()))):
            frame = node.get('frame', {})
            if not all(key in frame for key in ('x', 'y', 'w', 'h')): continue
            record = {'identity': f'{manifest["witness"]["id"]}/ax/{index}', 'role': node['role'], 'actions': node.get('actions', []), 'source': 'external', 'bounds': measured({'x': frame['x'], 'y': frame['y'], 'width': frame['w'], 'height': frame['h']})}
            if node.get('label') or node.get('title'): record['label'] = node.get('label') or node['title']
            if 'value' in node: record['value'] = node['value']
            ax.append(record)
    capture = {'kind': 'capture', 'version': '0.1', 'id': f'{case["id"]}.macos.run-{run:03d}', 'provenance': provenance(raw_file, [{'id': 'macos.capture.binary', 'hash': binary_hash}], producer='factory/native/macos'), 'case': manifest['case'], 'platform': 'macos', 'tuple': case['tuple'], 'meta': {'run': run, 'host': {'id': 'factory.host.macos.measured', 'hash': case['tuple']['hostHashes']['macos']}, 'conditions': {'candidateOnly': True, 'observationalOnly': True, 'channelStatus': channels, 'clockScope': clock['scope'], 'caseInputs': case['inputs']}, 'clock': {'clockId': clock['clockId'], 'correlationHash': canonical_hash(clock)}}, 'layout': layout, 'ax': ax, 'events': [{'id': 'offscreen.begin', 'kind': 'capture-render-begin', 'timeNs': clock['startNs'], 'clockId': clock['clockId']}, {'id': 'offscreen.end', 'kind': 'capture-render-end', 'timeNs': clock['endNs'], 'clockId': clock['clockId']}], 'anim': [], 'images': images, 'text': []}
    validate_artifact(capture)
    write_artifact(directory / 'capture.json', capture)
    return capture
