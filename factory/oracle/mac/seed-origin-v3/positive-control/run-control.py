#!/usr/bin/env python3
from pathlib import Path
import importlib.util
root=Path(__file__).parent
module_path=root/"factory/oracle/mac/seed-origin-v3/capture_origin.py"
spec=importlib.util.spec_from_file_location("seed_origin_v3_collector", module_path)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
result, receipt=module.compiler_build(root/"work", root/"evidence", root/"work/capture-host")
print({"returncode": result.returncode, "status": receipt.get("status"), "compilerExit": (receipt.get("compiler") or {}).get("exitCode"), "binary": (receipt.get("compiler") or {}).get("outputBinary")})
