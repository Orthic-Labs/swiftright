#!/usr/bin/env python3
"""Pure Count1 donor admission controls; no writes, native, compiler, or lock action."""
from __future__ import annotations
import argparse, copy, importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('stage', HERE/'stage_fresh_capture_v1.py')
if spec is None or spec.loader is None: raise RuntimeError('stager unavailable')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
KEYS=set(mod.RECTANGLE_SOURCE_KEYS)
def admit(d,p,c):
    if set(KEYS)-set(d): raise ValueError('missing donor source field')
    if d.get('kind')!='factory-rectangle-source-inputs-v1' or d.get('count')!=1: raise ValueError('donor count/kind')
    if p.get('kind')!='factory-rectangle-native-capture-plan-v1': raise ValueError('donor plan kind')
    if p.get('dispatch',{}).get('first',{}).get('count')!=1 or p.get('dispatch',{}).get('repeat',{}).get('count')!=20: raise ValueError('donor dispatch')
    if len(c.get('sourceBindings',[]))<5: raise ValueError('donor bindings')
    if p.get('case',{}).get('id')!=d.get('caseID') or p.get('tuple',{}).get('id')!=d.get('tupleID'): raise ValueError('donor identity')
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--donor-source-inputs',type=Path,required=True);ap.add_argument('--donor-capture-plan',type=Path,required=True);ap.add_argument('--donor-config-template',type=Path,required=True);a=ap.parse_args()
    d=mod.json_file(a.donor_source_inputs);p=mod.json_file(a.donor_capture_plan);c=mod.json_file(a.donor_config_template);admit(d,p,c)
    faults=[]
    def reject(name,mut):
        x,y,z=copy.deepcopy(d),copy.deepcopy(p),copy.deepcopy(c);mut(x,y,z)
        try: admit(x,y,z)
        except ValueError: faults.append(name);return
        raise AssertionError('fault accepted: '+name)
    reject('wrong-count',lambda x,y,z:x.__setitem__('count',20))
    reject('wrong-kind',lambda x,y,z:x.__setitem__('kind','stale'))
    reject('repeat-count',lambda x,y,z:y['dispatch']['repeat'].__setitem__('count',19))
    reject('case-id',lambda x,y,z:y['case'].__setitem__('id','stale'))
    reject('tuple-id',lambda x,y,z:y['tuple'].__setitem__('id','stale'))
    reject('missing-binding',lambda x,y,z:z.__setitem__('sourceBindings',[]))
    if len(faults)!=6: raise AssertionError(faults)
    print('SOURCE_CONTROLS_PASS donor-baseline+6_faults nativeActions=0')
if __name__=='__main__':main()
