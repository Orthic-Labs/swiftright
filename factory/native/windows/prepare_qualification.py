"""Fixed compile-only qualification host, independent final tuple/case identity."""
from pathlib import Path
import argparse
from factory.core.artifacts import file_hash, canonical_hash, write_artifact
from .prepare_additive import prepare_additive

SOURCE='import SwiftRightRuntime\nstruct FactoryQualificationWitness: View { var body: some View { EmptyView() } }\n'

def prepare(output: Path, runtime_receipt: Path):
    root=Path(__file__).resolve().parent;output=output.resolve()
    if not output.is_relative_to(root) or output==root or output.exists():raise ValueError('fresh owned qualification root required')
    seed=output/'fixed-source';seed.mkdir(parents=True)
    source=seed/'Witness.swift';source.write_text(SOURCE)
    manifest=seed/'manifest.json'
    write_artifact(manifest,{'kind':'factory-qualification-host-manifest','sourceFile':source.name,'sourceHash':file_hash(source),
        'witnessType':'FactoryQualificationWitness','case':{'id':'factory.windows.fixed-qualification-host','hash':canonical_hash({'purpose':'compile-only fixed host','sourceHash':file_hash(source)})},
        'compileExpectation':'success','executionEligible':False,'environmentInputs':{'colorScheme':'light'},'tupleIndependent':True})
    plan=prepare_additive(manifest,output/'package',runtime_receipt)
    plan.update(purpose='fixed qualification host measurement',tupleIndependent=True,nativeReplayAllowed=False)
    write_artifact(output/'package/plan.json',plan)
    return plan

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--runtime-receipt',type=Path,required=True);a=p.parse_args();prepare(a.output,a.runtime_receipt)
