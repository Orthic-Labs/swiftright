"""Archive fixed recipe witness declarations for headless Windows capability checks."""
import argparse, json, shutil
from pathlib import Path
from factory.core.artifacts import file_hash, write_artifact

def prepare(output, receipt, manifests_dir=None):
    lane=Path(__file__).resolve().parent; repo=lane.parents[2]; output=Path(output).resolve()
    if not output.is_relative_to(lane) or output.exists(): raise ValueError('fresh owned sweep root required')
    runtime=json.loads(Path(receipt).read_text()); manifests=sorted((Path(manifests_dir) if manifests_dir else repo/'factory/pipeline/probes').glob('*.manifest.json'))
    if len(manifests)!=81: raise ValueError('fixed 81 declarations required')
    output.mkdir(); rows=[]
    for index, original in enumerate(manifests,1):
        correction=repo/'factory/pipeline/corrections'/original.name
        manifest=correction if correction.is_file() else original
        value=json.loads(manifest.read_text()); source=manifest.parent/value['sourceFile']
        if file_hash(source)!=value['sourceHash']: raise ValueError('witness bytes drift')
        directory=output/f'case-{index:03d}'; directory.mkdir()
        shutil.copyfile(source,directory/'Witness.swift'); shutil.copyfile(manifest,directory/'manifest.json')
        rows.append({'index':index,'block':value['block'],'case':value['case'],'sourceHash':file_hash(source),'manifestHash':file_hash(manifest),'directory':directory.name,'originalManifestHash':file_hash(original),'foundationCorrection':manifest!=original,'compileExpectation':value['compileExpectation']})
    shutil.copyfile(receipt,output/'runtime-source-receipt.json')
    tree=Path(receipt).parent/'runtime-source-tree.json'; shutil.copyfile(tree,output/tree.name)
    write_artifact(output/'sweep-plan.json',{'kind':'windows-fixed81-declaration-plan','runtimeCommit':runtime['sourceCommit'],'runtimePackagePath':runtime['runtimePackagePath'],'runtimeSourceTreeHash':runtime['sourceTreeHash'],'runtimeReceiptHash':file_hash(receipt),'rows':rows,'nativeCaseCaptureCount':0,'frozenTupleBound':False})
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--output',type=Path,required=True); parser.add_argument('--runtime-receipt',type=Path,required=True); parser.add_argument('--manifests-dir',type=Path); args=parser.parse_args(); prepare(args.output,args.runtime_receipt,args.manifests_dir)
