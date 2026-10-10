"""Bind explicit CLOSED status, tuple10 staging pins & distinct additive runtime."""
from pathlib import Path
import argparse, json, re
from datetime import datetime
from factory.core.artifacts import file_hash, write_artifact
from .prepare_additive import STAGE10_COMMIT, DLL_HASH
from .closure_guard import validate

def bind(package: Path, status: Path, staging: Path, tuple_path: Path | None, *, closure_receipt: Path | None = None, manifest: Path | None = None) -> dict:
    package=package.resolve();root=Path(__file__).resolve().parent
    if not package.is_relative_to(root) or package==root:raise ValueError('owned package required')
    if closure_receipt is None:raise ValueError('CLOSED tuple10 closure receipt required')
    closure=validate(status,closure_receipt)
    pins=staging.read_text().lower()
    if STAGE10_COMMIT not in pins or DLL_HASH not in pins:raise ValueError('tuple10 staging pins absent')
    plan_path=package/'plan.json';plan=json.loads(plan_path.read_text())
    if plan.get('closureBinding'):raise ValueError('closure already bound')
    if (package/'native-observation.json').exists() or list(package.glob('native-[0-9]*')):raise ValueError('native archives already exist')
    if manifest is not None:
        final_manifest=json.loads(manifest.read_text())
        if final_manifest['sourceHash']!=plan['sourceHash']:raise ValueError('final witness differs from compiled source')
        if not final_manifest.get('executionEligible',False):raise ValueError('final case is not eligible')
        main=(package/'Sources/FactoryProbe/main.swift').read_text()
        if 'Graph('+final_manifest['witnessType']+'()' not in main:raise ValueError('final witness type differs from compiled host')
        plan.update(case=final_manifest['case'],manifestHash=file_hash(manifest),executionEligible=True)
    tuple_data=json.loads(tuple_path.read_text()) if tuple_path else None
    if tuple_data and tuple_data['runtimeCommit']!=plan['runtimeSourceCommit']:raise ValueError('tuple runtime differs from additive source')
    if tuple_data and (tuple_data['rendererHash']!='sha256:'+DLL_HASH or tuple_data.get('id','')=='sr1-observed-r09-20261010'):raise ValueError('fresh changed-runtime tuple required')
    compile_archives=[]
    if (package/'observation.json').exists():
        compile_plan=json.loads(plan_path.read_text());observation=json.loads((package/'observation.json').read_text(encoding='utf-8-sig'))
        if observation.get('synthetic'):raise ValueError('synthetic compile observation rejected')
        stamp=observation.get('observedAt','')
        if not stamp.endswith('Z') or datetime.fromisoformat(stamp[:-1]+'+00:00')<=datetime.fromisoformat(closure['closedAt'][:-1]+'+00:00'):raise ValueError('compile must follow exact closure timestamp')
        if observation.get('planSha256')!=file_hash(plan_path).removeprefix('sha256:') or observation.get('sourceHash')!=plan['sourceHash'] or observation.get('exitCode')!=0:
            raise ValueError('successful exact compiled source binding required')
        for binding in compile_plan['sourceBindings']:
            source=package/binding['path']
            if not source.resolve().is_relative_to(package) or file_hash(source)!=binding['sha256']:raise ValueError('compiled source drift')
        if (package/'compile-plan.json').exists() or (package/'compile-observation.json').exists():raise ValueError('compile archive already exists')
        compile_archives=[(plan_path,'compile-plan.json'),(package/'observation.json','compile-observation.json')]
        plan['compileBinding']={'planHash':file_hash(plan_path),'observationHash':file_hash(package/'observation.json'),'actualExecutableHash':'sha256:'+observation['exeSha256']}
    archives=[(status,'sr0-status-closed.md'),(staging,'sr0-tuple10-staging.md'),(closure_receipt,'closure-receipt.json')]
    if tuple_path:archives.append((tuple_path,'tuple.json'))
    if manifest:archives.append((manifest,'final-manifest.json'))
    archives+=compile_archives
    for _,name in archives:
        if (package/name).exists():raise ValueError('closure archive already exists')
    for source,name in archives:
        (package/name).write_bytes(source.read_bytes())
    plan['closureBinding']={'receiptHash':file_hash(closure_receipt),'closedAt':closure['closedAt'],'tuple':'10','decision':'CLOSED','statusHash':file_hash(status),'tuple10StagingHash':file_hash(staging),'tupleHash':file_hash(tuple_path) if tuple_path else None,'stageSourceCommit':STAGE10_COMMIT,'runtimeSourceCommit':plan['runtimeSourceCommit']}
    write_artifact(plan_path,plan);return plan

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('package',type=Path);p.add_argument('--status',type=Path,required=True);p.add_argument('--staging',type=Path,required=True);p.add_argument('--tuple',type=Path);p.add_argument('--manifest',type=Path);p.add_argument('--closure-receipt',type=Path,required=True)
    a=p.parse_args();print(json.dumps(bind(a.package,a.status,a.staging,a.tuple,manifest=a.manifest,closure_receipt=a.closure_receipt),sort_keys=True))
if __name__=='__main__':main()
