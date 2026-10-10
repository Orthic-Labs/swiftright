"""Archive actual primary witness bytes for independent non-windowed typechecks."""
from pathlib import Path
import argparse,json,shutil
from factory.core.artifacts import file_hash,write_artifact
ORDER=('swiftui.shapes.fill-stroke','swiftui.image','swiftui.stack-overlay','swiftui.text.bundled-font','swiftui.custom-layout','swiftui.disabled','swiftui.padding-frame','swiftui.preference-key','swiftui.scroll-view','swiftui.toggle')
def prepare(output, receipt):
    lane=Path(__file__).resolve().parent;repo=lane.parents[2];output=Path(output).resolve()
    if not output.is_relative_to(lane) or output.exists():raise ValueError('fresh owned typecheck root required')
    primaries=json.loads((repo/'factory/pipeline/inputs/primary-cases.json').read_text());runtime=json.loads(Path(receipt).read_text())
    output.mkdir();rows=[]
    for index,block in enumerate(ORDER,1):
        primary=next(p for p in primaries if p['block']==block);manifest=Path(primary['manifestPath'])
        correction=repo/'factory/pipeline/corrections'/manifest.name
        if block in ('swiftui.custom-layout','swiftui.preference-key'):manifest=correction
        value=json.loads(manifest.read_text());source=manifest.parent/value['sourceFile']
        if file_hash(source)!=value['sourceHash']:raise ValueError('actual witness source drift')
        sub=output/f'primary-{index:02d}';sub.mkdir();shutil.copyfile(source,sub/'Witness.swift');shutil.copyfile(manifest,sub/'manifest.json')
        rows.append({'index':index,'block':block,'case':value['case'],'sourceHash':file_hash(source),'manifestHash':file_hash(manifest),'directory':sub.name})
    shutil.copyfile(receipt,output/'runtime-source-receipt.json')
    write_artifact(output/'typecheck-plan.json',{'kind':'actual-witness-compile-only-plan','runtimeCommit':runtime['sourceCommit'],'runtimeSourceTreeHash':runtime['sourceTreeHash'],'runtimeReceiptHash':file_hash(receipt),'primaries':rows,'nativeCaseCaptureCount':0,'frozenTupleBound':False})
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--runtime-receipt',type=Path,required=True);a=p.parse_args();prepare(a.output,a.runtime_receipt)
