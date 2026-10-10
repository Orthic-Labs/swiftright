"""New factory host lineage: native owned HWND client metrics, immutable witness bytes."""
from pathlib import Path
import argparse, json, shutil
from factory.core.artifacts import file_hash, write_artifact
from .prepare_additive import prepare_additive

def prepare(manifest: Path, output: Path, receipt: Path):
    plan = prepare_additive(manifest, output, receipt)
    witness = json.loads(manifest.read_text())
    lane = Path(__file__).resolve().parent
    template = (lane / 'RendererHostViewport.swift.in').read_text()
    main = output / 'Sources/FactoryProbe/main.swift'
    main.write_text(template.replace('__WITNESS__', witness['witnessType']).replace('__COLORSCHEME__', witness.get('environmentInputs', {}).get('colorScheme', 'light')))
    shutil.copyfile(lane / 'FactoryViewport.swift', main.parent / 'FactoryViewport.swift')
    plan['sourceBindings'] = [{'path': str(p.relative_to(output)), 'sha256': file_hash(p)} for p in sorted(output.rglob('*.swift'))]
    plan['viewportPolicy'] = 'Exact own PID/UI-thread/title HWND; physical GetClientRect pixels / DPI scale; root proposal cache key changes before flush; DPI drift abort; foreground abort'
    plan['adapterLineage'] = 'factory-viewport-v1'
    write_artifact(output / 'plan.json', plan)
    return plan

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--runtime-receipt', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.manifest, args.output, args.runtime_receipt)
