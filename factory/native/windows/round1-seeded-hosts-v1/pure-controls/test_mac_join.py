# Prepared pure production-function faults; synthetic metadata never native evidence.
import copy
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('seed_join', Path(__file__).parents[1] / 'verify_mac_join.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
case = {'id': 'unit-case', 'hash': 'unit-case-hash'}
rows = [{'path': f'unit/run-{i}', 'run': i, 'case': case, 'sourceHash': 'unit-source'} for i in range(1, 21)]
assert module.verify(rows, case, 'unit-source')
for fault in ('missing', 'duplicate-path', 'wrong-source', 'wrong-case', 'duplicate-run', 'boolean-run'):
    broken = copy.deepcopy(rows)
    if fault == 'missing': broken.pop()
    if fault == 'duplicate-path': broken[1]['path'] = broken[0]['path']
    if fault == 'wrong-source': broken[1]['sourceHash'] = 'other'
    if fault == 'wrong-case': broken[1]['case']['hash'] = 'other'
    if fault == 'duplicate-run': broken[1]['run'] = 1
    if fault == 'boolean-run': broken[0]['run'] = True
    try: module.verify(broken, case, 'unit-source')
    except ValueError: pass
    else: raise AssertionError(fault)
print('Six synthetic source-join faults rejected')
