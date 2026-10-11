from pathlib import Path
import importlib.util,json
root=Path(__file__).parent; modpath=root/'factory/oracle/mac/seed-origin-v2/capture_origin.py'; spec=importlib.util.spec_from_file_location('origin',modpath); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
work=root/'work'; evidence=root/'evidence'; work.joinpath('Witness.swift').write_bytes(b'public struct SeedOriginControl {}\n'); work.joinpath('CaptureHost.swift').write_bytes(b'\n'); result,receipt=m.compiler_build(work,evidence,work/'capture-host'); print(json.dumps({'returncode':result.returncode,'status':receipt.get('status'),'receipt':str(evidence/'compiler-receipt.json')},sort_keys=True))
