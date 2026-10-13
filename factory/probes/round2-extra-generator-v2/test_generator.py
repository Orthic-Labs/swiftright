#!/usr/bin/env python3
"""Offline positive & mutation controls for held Round2 F4 generator."""
from __future__ import annotations
import copy, json, tempfile
from pathlib import Path
from generate import GenerationError, generate, load_packet, validate_candidate_source_joins, validate_output_manifest, BLOCKS

ROOT=Path(__file__).resolve().parents[2]

def reject(label, fn):
    try: fn()
    except (GenerationError, KeyError, AssertionError): return
    raise AssertionError('accepted fault: '+label)

def main():
    packet=load_packet()
    assert packet['candidate']['activeRegistryMutation'] is False
    assert packet['validation']['compilerRuns']==0 and packet['validation']['nativeRuns']==0
    with tempfile.TemporaryDirectory(prefix='round2-extra-f4-', dir=ROOT/'.factory-work') as d:
        result=generate(packet,Path(d))
        assert result['outputs']==19 and result['executionEligible'] is False
        files=list(Path(d).glob('*'))
        assert len(files)==38 and all(p.suffix in {'.swift','.json'} for p in files)
        manifests=[json.loads(p.read_text()) for p in Path(d).glob('*.manifest.json')]
        assert len(manifests)==19
        for m in manifests:
            validate_output_manifest(m,packet)
            if m['scenario'].startswith('negative:'):
                assert m['witness']['id'].endswith('.negative.invalid-argument') and m['witnessType']=='Negative_round2'
            else:
                assert m['witness']['id'].endswith('.witness') and m['witnessType'].startswith('Witness_round2_')
    bad=copy.deepcopy(packet); bad['candidate']['blocks'][0]['symbols'][0]['selector']='usr:s:wrong'; reject('USR/source join',lambda:validate_candidate_source_joins(bad))
    bad=copy.deepcopy(packet); bad['join']['rows'][0]['selectedSourceSymbols'][0]['selector']='usr:s:wrong'; reject('join selector',lambda:validate_candidate_source_joins(bad))
    bad=copy.deepcopy(packet); bad['join']['rows'][0]['selectedSourceSymbols']=[]; reject('empty source-use join',lambda:validate_candidate_source_joins(bad))
    bad=copy.deepcopy(packet); bad['join']['rows'][1]['selectedSourceSymbols'].append(copy.deepcopy(bad['join']['rows'][1]['selectedSourceSymbols'][0])); reject('extra source-use join',lambda:validate_candidate_source_joins(bad))
    bad=copy.deepcopy(packet); bad['join']['rows'][0]['block']='swiftui.unknown'; reject('join block',lambda:validate_candidate_source_joins(bad))
    def generated_fault(label, packet_fault):
        with tempfile.TemporaryDirectory(prefix='round2-extra-f4-fault-', dir=ROOT/'.factory-work') as d:
            reject(label,lambda:generate(packet_fault,Path(d)))
    bad=copy.deepcopy(packet); bad['validation']['recipes'][0]['descriptors'][0]['id']='swiftui.unknown.case'; generated_fault('case binding',bad)
    bad=copy.deepcopy(packet); bad['config']['unsupportedObservability']['swiftui.text-field-ime'].pop('ime'); generated_fault('IME unsupported observability',bad)
    bad=copy.deepcopy(packet); bad['candidate']['blocks'][0]['registryPromotion']=True; generated_fault('registry promotion',bad)
    with tempfile.TemporaryDirectory(prefix='round2-extra-f4-output-fault-', dir=ROOT/'.factory-work') as d:
        generate(packet,Path(d)); mpath=next(Path(d).glob('*.manifest.json')); m=json.loads(mpath.read_text())
        badm=copy.deepcopy(m); badm['witness']['id']=badm['block']+'.negative.invalid-argument'; reject('positive/negative witness identity',lambda:validate_output_manifest(badm,packet))
        badm=copy.deepcopy(m); badm['witnessType']='Negative_round2'; reject('declaration name binding',lambda:validate_output_manifest(badm,packet))
        negative=json.loads(next(p for p in Path(d).glob('*.manifest.json') if json.loads(p.read_text())['scenario'].startswith('negative:')).read_text())
        badm=copy.deepcopy(negative); badm['witness']['sourceHash']='sha256:'+'0'*64; reject('negative source hash',lambda:validate_output_manifest(badm,packet))
        badm=copy.deepcopy(negative); badm['witnessType']='Witness_round2_wrong'; reject('negative declaration name',lambda:validate_output_manifest(badm,packet))
    print(json.dumps({'ok':True,'acceptedBaselineOutputs':19,'rejectedControls':12,'compilerRuns':0,'nativeRuns':0},sort_keys=True))

if __name__=='__main__': main()
