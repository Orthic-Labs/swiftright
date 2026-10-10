"""Validate complete additive provenance before publishing any normalized archive."""
from datetime import datetime, timezone
import json
from pathlib import Path
from factory.core.artifacts import canonical_hash, file_hash
from .closure_guard import validate as validate_closure

def synthetic(value):
    if isinstance(value,dict):return value.get('synthetic') is True or value.get('producer')=='test-fixture' or any(synthetic(v) for v in value.values())
    return isinstance(value,list) and any(synthetic(v) for v in value)

def validate(package, plan, rows, tuple_path):
    package=Path(package).resolve();copies={}
    def required(name):
        path=package/name
        if not path.is_file():raise ValueError('missing required additive archive: '+name)
        copies[Path(name)]=path
        return path
    def loaded(name):
        value=json.loads(required(name).read_text(encoding='utf-8-sig'))
        if synthetic(value):raise ValueError('nested synthetic additive receipt rejected: '+name)
        return value
    if synthetic(plan) or synthetic(rows):raise ValueError('synthetic additive provenance rejected')
    binding=plan['closureBinding'];required('sr0-status-closed.md')
    closure=validate_closure(package/'sr0-status-closed.md',required('closure-receipt.json'))
    for key in ('tuple','decision','closedAt','statusHash'):
        if closure[key]!=binding.get(key):raise ValueError('additive closure binding differs')
    for name,key in (('closure-receipt.json','receiptHash'),('sr0-tuple10-staging.md','tuple10StagingHash')):
        if file_hash(required(name))!=binding.get(key):raise ValueError('additive archive raw hash differs: '+name)
    tuple_value=json.loads(Path(tuple_path).read_text())
    if synthetic(tuple_value) or file_hash(tuple_path)!=binding.get('tupleHash') or tuple_value.get('runtimeCommit')!=plan.get('runtimeSourceCommit'):
        raise ValueError('additive tuple/runtime binding differs')
    runtime=loaded('runtime-source-receipt.json');tree=loaded('runtime-source-tree.json')
    if (file_hash(package/'runtime-source-receipt.json')!=plan.get('runtimeSourceReceiptHash') or runtime.get('sourceCommit')!=plan.get('runtimeSourceCommit')
        or runtime.get('sourceTreeHash')!=plan.get('runtimeSourceTreeHash') or runtime.get('sourceBindings')!=tree or canonical_hash(tree)!=plan.get('runtimeSourceTreeHash')):
        raise ValueError('additive runtime source receipt/tree differs')
    observation=loaded('observation.json');compile_plan=plan;compile_plan_path=package/'plan.json'
    if plan.get('compileBinding'):
        compiled_binding=plan['compileBinding'];compile_plan=loaded('compile-plan.json');archived_observation=loaded('compile-observation.json');compile_plan_path=package/'compile-plan.json'
        if (file_hash(compile_plan_path)!=compiled_binding.get('planHash') or file_hash(package/'compile-observation.json')!=compiled_binding.get('observationHash')
            or (package/'observation.json').read_bytes()!=(package/'compile-observation.json').read_bytes() or observation!=archived_observation
            or 'sha256:'+observation.get('exeSha256','')!=compiled_binding.get('actualExecutableHash')):
            raise ValueError('additive archived compile binding differs')
    for key in ('sourceHash','runtimeSourceCommit','runtimeSourceTreeHash','stageSourceCommit','rendererSha256'):
        if compile_plan.get(key)!=plan.get(key):raise ValueError('additive compiled plan differs: '+key)
    if (observation.get('exitCode')!=0 or observation.get('planSha256')!=file_hash(compile_plan_path).removeprefix('sha256:')
        or observation.get('sourceHash')!=plan.get('sourceHash')):raise ValueError('additive successful compile plan/source binding differs')
    for key in ('runtimeSourceCommit','runtimeSourceTreeHash','stageSourceCommit','rendererSha256'):
        if observation.get(key)!=plan.get(key):raise ValueError('additive compile identity differs: '+key)
    stamp=observation.get('observedAt','')
    if not stamp.endswith('Z') or not datetime.fromisoformat(closure['closedAt'][:-1]+'+00:00') < datetime.fromisoformat(stamp[:-1]+'+00:00') <= datetime.now(timezone.utc):
        raise ValueError('additive compile must follow closure')
    exe=required('evidence/FactoryProbe.exe')
    if file_hash(exe)!='sha256:'+observation.get('exeSha256',''):raise ValueError('additive executable archive differs')
    sources=compile_plan.get('sourceBindings')
    if not isinstance(sources,list) or not sources:raise ValueError('additive compiled source bindings required')
    for item in sources:
        relative=Path(item['path'].replace('\\','/'));source=(package/relative).resolve()
        if ':' in str(relative) or not source.is_relative_to(package) or file_hash(source)!=item['sha256']:raise ValueError('additive compiled source drift')
        copies[relative]=source
    for row in rows:
        for key in ('runtimeSourceCommit','runtimeSourceTreeHash','stageSourceCommit','rendererSha256'):
            if row.get(key)!=plan.get(key):raise ValueError('historical/additive replay identity differs: '+key)
        if row.get('exeSha256')!=observation.get('exeSha256') or row.get('sourceHash')!=plan.get('sourceHash') or row.get('case')!=plan.get('case'):
            raise ValueError('additive replay compile/source/case differs')
    if (package/'final-manifest.json').exists():
        final=loaded('final-manifest.json')
        if file_hash(package/'final-manifest.json')!=plan.get('manifestHash') or final.get('sourceHash')!=plan.get('sourceHash') or final.get('case')!=plan.get('case'):
            raise ValueError('additive final manifest differs')
    return copies
