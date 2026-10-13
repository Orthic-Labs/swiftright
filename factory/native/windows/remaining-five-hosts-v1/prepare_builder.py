"""Copy approved bounded compiler kernel/controls into new source-only lane."""
from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parents[4];OUT=Path(__file__).resolve().parent
OLD=ROOT/'factory/native/windows/round1-seeded-build-v2'
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for rel in ('cleanup-decision.ps1','control-admission.ps1','run-controls.ps1',
            'pure-controls/test-cleanup.ps1','pure-controls/test-host-inputs.ps1',
            'pure-controls/parse-controls.ps1','pure-controls/reserved-assignment-lint.ps1',
            'pure-controls/test-integer-admission.ps1'):
 src=(OLD/rel).read_text();src=src.replace('..\\round1-seeded-hosts-v1\\shared\\host-inputs.ps1','shared\\host-inputs.ps1').replace('..\\..\\round1-seeded-hosts-v1\\shared\\host-inputs.ps1','..\\shared\\host-inputs.ps1')
 p=OUT/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(src)
shared=OUT/'shared';shared.mkdir(exist_ok=True)
for src,name in [(ROOT/'factory/native/windows/verify-runtime-source.ps1','verify-runtime-source.ps1'),
                 (ROOT/'factory/native/windows/round1-seeded-hosts-v1/shared/host-inputs.ps1','host-inputs.ps1')]:
 (shared/name).write_bytes(src.read_bytes())
s=(OLD/'build-hosts-v2.ps1').read_text()
a=s.index('$expected=@(');b=s.index("if($expected",a)
rows=json.loads((OUT/'readiness.json').read_bytes())['rows']
s=s[:a]+"$expected=@("+','.join("'"+r['remotePackage']+"'" for r in rows)+")\n"+s[b:]
a=s.index('$approvedPlans=@{');b=s.index('$label=',a)
s=s[:a]+"$approvedPlans=@{\n"+'\n'.join(" '"+r['label']+"'='"+r['planHash'][7:]+"'" for r in rows)+"\n}\n"+s[b:]
s=s.replace("'..\\verify-runtime-source.ps1'","'shared\\verify-runtime-source.ps1'").replace("'..\\round1-seeded-hosts-v1\\shared\\host-inputs.ps1'","'shared\\host-inputs.ps1'")
s=s.replace("$out=Join-Path $Package 'build-v2-r1'", """$out=Join-Path $Package 'build-v2-r1'
$request=$plan.compileRequest
if($request.kind -cne 'swiftpm-windows-gui-release/1' -or $request.packagePath -cne $Package -or $request.scratchPath -cne (Join-Path $out 'scratch') -or $request.compilerPath -cne $plan.compilerPath -or $request.target -cne 'windows-x86_64' -or $request.configuration -cne 'release'){throw 'Exact prospective compile request mismatch'}""")
s=s.replace("compilerHash=$plan.compilerHash;rendererSha256", "compilerHash=$plan.compilerHash;compilerPath=$plan.compilerPath;target='windows-x86_64';configuration='release';rendererSha256")
s=s.replace("kind='factory-compile-only-owned-handle-v2'", "kind='factory-remaining-five-compile-only-owned-handle-v1'")
# No change to retained-handle cleanup/streams/deadline; all dependency helpers pinned.
s=s.replace('0348814bba0e8ea89de323603bcd096f10b68528a0ac762c1df9078e624fa39e',h(OUT/'control-admission.ps1'))
s=s.replace('018d89b825634a0dc238c1201d4fd97a23acbcdaf57b82333c6097e9efd92001',h(OUT/'cleanup-decision.ps1'))
s=s.replace('93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db',h(shared/'host-inputs.ps1'))
for patch in json.loads((OUT/'builder-additions.json').read_bytes()):
 if patch['before'] not in s:raise ValueError('Approved builder anchor drift')
 s=s.replace(patch['before'],patch['after'],1)
(OUT/'build-hosts-v2.ps1').write_text(s)
print('bounded builder + pure PS controls prepared, unrun')
