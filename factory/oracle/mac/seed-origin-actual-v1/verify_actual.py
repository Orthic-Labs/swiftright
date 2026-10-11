#!/usr/bin/env python3
"""Offline verifier for fresh v6 five-case candidate capture lineage."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

def sha(path: Path) -> str: return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
def fail(message: str) -> None: raise ValueError(message)

def validate(root: Path) -> dict:
    root = root.resolve(); lineage = json.loads((root/'lineage.json').read_text())
    lineage['candidateOnly'] is True and lineage['caseCount'] == 5 and lineage['runsPerCase'] == 20 and lineage['totalRuns'] == 100 or fail('candidate denominator')
    cases = lineage['cases']; len(cases) == 5 or fail('case count')
    seen = set()
    for case in cases:
        cid = case['caseId']; cid not in seen or fail('duplicate case'); seen.add(cid)
        receipt_path = root/case['compilerReceiptPath']; receipt_path.is_file() or fail('receipt missing')
        receipt = json.loads(receipt_path.read_text()); receipt['status'] == 'SUCCESS' and receipt['sourceDrift'] is False or fail(f'receipt {cid}')
        c = receipt['compiler']; c['exitCode'] == 0 and c['timedOut'] is False and c['pgid'] == c['pid'] or fail(f'compiler process {cid}')
        c['realToolBefore'] == c['realToolAfter'] and c['realToolDrift'] is False or fail(f'tool drift {cid}')
        case['compilerReceiptSha256'] == sha(receipt_path) or fail(f'receipt hash {cid}')
        binary = root/case['binaryPath']; binary.is_file() and sha(binary) == case['binarySha256'] and case['binarySha256'] == c['outputBinary']['sha256'] or fail(f'binary join {cid}')
        len(case['sourceBindings']) == 2 or fail(f'source bindings {cid}')
        for binding in case['sourceBindings']:
            archive = root/binding['archivePath']; archive.is_file() or fail(f'source archive {cid}')
            binding['archiveSha256'] == sha(archive) == binding['sourceBefore']['sha256'] == binding['sourceAfter']['sha256'] or fail(f'source join {cid}/{binding["name"]}')
            binding['unchanged'] is True or fail(f'source drift {cid}/{binding["name"]}')
        len(case['runs']) == 20 or fail(f'run denominator {cid}')
        for run in case['runs']:
            n = run['run']; run_dir = root/cid/f'run-{n:03d}'; run_dir.is_dir() or fail(f'run directory {cid}/{n}')
            for mode in ('plain','instrumented'):
                raw = run_dir/f'{mode}.raw.json'; raw.is_file() and run[f'{mode}RawHash'] == sha(raw) or fail(f'{mode} raw {cid}/{n}')
            ax = run_dir/'external-ax.raw.json'; ax.is_file() and run['externalAXRawHash'] == sha(ax) or fail(f'AX raw {cid}/{n}')
            capture = run_dir/'capture.json'; capture.is_file() and run['captureHash'] == sha(capture) or fail(f'capture join {cid}/{n}')
    ax = lineage['auxiliaryAX']; ax_receipt = root/ax['receiptPath']; ax_receipt.is_file() and sha(ax_receipt) == ax['receiptSha256'] or fail('AX receipt')
    ar = json.loads(ax_receipt.read_text()); ac = ar['compiler']; ac['exitCode'] == 0 and ac['pgid'] == ac['pid'] and ar['sourceDrift'] is False or fail('AX compiler')
    ax_source = root/ax['sourceArchivePath']; ax_binary = root/ax['binaryArchivePath']; ax_source.is_file() and sha(ax_source) == ax['sourceSha256'] == ac['sourceBefore']['AXClient.swift']['sha256'] or fail('AX source join'); ax_binary.is_file() and sha(ax_binary) == ax['binarySha256'] == ac['outputBinary']['sha256'] or fail('AX binary join')
    lineage['status'] == 'CAPTURED_CANDIDATE_NOT_PROMOTED' or fail('promotion status')
    return {'status':'PASS','cases':5,'runs':100,'compilerReceipts':5,'auxiliaryReceipt':'PASS','sourceDrift':False,'toolDrift':False,'candidateOnly':True}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('root', type=Path); args = parser.parse_args()
    try: print(json.dumps(validate(args.root), sort_keys=True, indent=2))
    except Exception as error: print(f'FAIL: {error}'); raise SystemExit(1)
