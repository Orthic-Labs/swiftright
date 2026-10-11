#!/usr/bin/env python3
"""Strict offline verifier for fresh corrected-seed Mac candidate packet."""
from __future__ import annotations
import argparse, hashlib, json, sys
from pathlib import Path

SEED = 14577611000270672472
BLOCKS = ('stack-overlay','padding-frame','scroll-view','custom-layout','preference-key')
PREFIX = 'swiftui.'
SUFFIX = '.recipe.gate-seeded.ca4e13f820f5d258'

def raw_sha(p: Path) -> str:
    return 'sha256:' + hashlib.sha256(p.read_bytes()).hexdigest()

def canonical(v):
    return json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()

def canonical_sha(v):
    return 'sha256:' + hashlib.sha256(canonical(v)).hexdigest()

def fail(msg): raise ValueError(msg)

def check_pin(pin, root):
    p=root/pin['path']; p.is_file() or fail(f'missing input {pin["path"]}')
    pin['sha256']==raw_sha(p) or fail(f'input bytes changed {pin["path"]}')
    pin['bytes']==p.stat().st_size or fail(f'input size changed {pin["path"]}')

def validate(root: Path) -> dict:
    root=root.resolve(); pins=json.loads((root/'input-pins.json').read_text())
    pins['seed']==SEED or fail('wrong seed')
    rows={r['block']:r for r in pins['rows']}
    set(rows)==set(BLOCKS) or fail('case set is not exact five')
    for r in rows.values():
        for item in (r['manifest'],r['source'],r['case'],r['recipe']): check_pin(item,root)
        m=json.loads((root/r['manifest']['path']).read_text()); src=root/r['source']['path']; case=json.loads((root/r['case']['path']).read_text()); recipe=json.loads((root/r['recipe']['path']).read_text())
        case['seed']==SEED or fail(f'{r["block"]}: case seed mismatch')
        raw_sha(src)==m['sourceHash']==r['source']['declared'] or fail(f'{r["block"]}: source hash mismatch')
        canonical_sha(case)==m['case']['hash']==r['case']['declared'] or fail(f'{r["block"]}: case hash mismatch')
        canonical_sha(recipe)==m['recipe']['hash']==r['recipe']['declared'] or fail(f'{r["block"]}: recipe hash mismatch')
        m['case']['id']==r['caseID'] and m['case']['id']==r['manifestCaseID'] or fail(f'{r["block"]}: case identity mismatch')
    ex=json.loads((root/'execution-receipt.json').read_text())
    ex['seed']==SEED and ex['permissionRequests'] is False or fail('execution permission/seed guard failed')
    ax=ex['freshAX']; ax.get('externalAX')=='AVAILABLE' and ax.get('preflight',{}).get('axTrusted') is True and ax.get('preflight',{}).get('permissionRequests') is False or fail('fresh AX preflight not trusted/no-prompt')
    rec=ex['signedRecorder']; rec.get('axTrusted') is True and rec.get('permissionRequests') is False or fail('signed recorder preflight failed')
    for b in ex['executables']:
        p=root/b['path']; p.is_file() or fail(f'missing executable {b["path"]}'); raw_sha(p)==b['sha256'] or fail(f'executable changed {b["path"]}'); p.stat().st_size==b['bytes'] or fail(f'executable size changed {b["path"]}')
    summaries=[]
    for block in BLOCKS:
        dname=PREFIX+block+SUFFIX; d=root/'evidence'/dname; sp=d/'summary.json'; sp.is_file() or fail(f'missing summary {block}')
        s=json.loads(sp.read_text()); s['candidateOnly'] is True and s['acceptance']=='not-promoted' or fail(f'{block}: promotion guard')
        s['status']=='CANDIDATE_CAPTURED' and len(s['runs'])==20 or fail(f'{block}: requires exactly 20 candidate runs')
        s['sourceHash']==rows[block]['source']['declared'] or fail(f'{block}: evidence source mismatch')
        bh=raw_sha(root/f'binaries/{block}/capture-host'); s.get('binaryHash')==bh or fail(f'{block}: binary lineage mismatch')
        ids=[]
        for row in s['runs']:
            n=row['run']; ids.append(n); 1<=n<=20 or fail(f'{block}: bad run id')
            rd=d/f'run-{n:03d}'; (rd/'capture.json').is_file() or fail(f'{block}: missing normalized run {n}')
            for mode in ('plain','instrumented'):
                x=row.get(mode,{}); (rd/f'{mode}.raw.json').is_file() and (rd/f'{mode}.png').is_file() or fail(f'{block}: missing {mode} raw/png {n}')
                x.get('rawHash')==raw_sha(rd/f'{mode}.raw.json') and x.get('pngHash')==raw_sha(rd/f'{mode}.png') or fail(f'{block}: {mode} hash mismatch {n}')
            if (rd/'compositor.raw.json').exists(): row.get('compositorRawHash')==raw_sha(rd/'compositor.raw.json') or fail(f'{block}: compositor hash mismatch {n}')
            if (rd/'external-ax.raw.json').exists(): row.get('externalAXRawHash')==raw_sha(rd/'external-ax.raw.json') or fail(f'{block}: AX hash mismatch {n}')
        sorted(ids)==list(range(1,21)) and len(set(ids))==20 or fail(f'{block}: duplicate/missing run IDs')
        summaries.append({'block':block,'status':s['status'],'runs':20,'channels':s['channels']})
    return {'status':'PASS','seed':SEED,'cases':summaries,'controls':['source/raw hash','case/recipe canonical hash','exact five-case set','exact 20 unique runs','binary lineage','no-prompt AX/recorder','candidate-only promotion hold']}

def main(argv=None):
    ap=argparse.ArgumentParser(); ap.add_argument('root',nargs='?',default=Path(__file__).parent); a=ap.parse_args(argv)
    try: print(json.dumps(validate(Path(a.root)),sort_keys=True,indent=2)); return 0
    except (OSError,ValueError,KeyError,TypeError,json.JSONDecodeError) as e: print(f'FAIL: {e}',file=sys.stderr); return 1
if __name__=='__main__': raise SystemExit(main())
