import json,copy,hashlib
from verify_source import snapshot,verify
s=snapshot();verify(s);rows=[]
def coherent(x):
 p=json.loads(x['package/plan.json']);old=hashlib.sha256(x['package/plan.json']).hexdigest()
 for r in p['sourceBindings']:r['sha256']='sha256:'+hashlib.sha256(x['package/'+r['path']]).hexdigest()
 x['package/plan.json']=(json.dumps(p,indent=2,sort_keys=True)+'\n').encode();new=hashlib.sha256(x['package/plan.json']).hexdigest()
 for f in ['build-hosts-v2.ps1','preflight.ps1']:x[f]=x[f].replace(old.encode(),new.encode())
def reject(name,mutate,reason):
 verify(s);x=dict(s);mutate(x);coherent(x)
 try:verify(x)
 except ValueError as e:
  if str(e)!=reason:raise AssertionError((name,str(e),reason))
 else:raise AssertionError('accepted '+name)
 rows.append({'name':name,'acceptedBaseline':True,'coherentSourcePlanRehashed':True,'rejected':True,'reason':reason})
def raw(f,a,b):return lambda x:x.__setitem__(f,x[f].replace(a.encode(),b.encode()))
def planfield(k,v):
 def mutate(x):p=json.loads(x['package/plan.json']);p[k]=v;x['package/plan.json']=(json.dumps(p,indent=2,sort_keys=True)+'\n').encode()
 return mutate
reject('default_changed',raw('package/Sources/FactoryProbe/CaptureLease.swift','return 10_000_000_000','return 40_000_000_000'),'bounded explicit40/default10')
reject('unbounded_lease',raw('package/Sources/FactoryProbe/CaptureLease.swift','return 40_000_000_000','return 400_000_000_000'),'bounded explicit40/default10')
reject('wrong_option',raw('package/Sources/FactoryProbe/CaptureLease.swift','seconds=40','seconds=41'),'bounded explicit40/default10')
reject('host_layout_changed',raw('package/Sources/FactoryProbe/main.swift','w: 320','w: 321'),'exact lifetime-only host delta')
reject('witness_changed',raw('package/Sources/FactoryProbe/Witness.swift','import SwiftRightRuntime','import SwiftRightRuntime\n// drift'),'unchanged witness/layout/package bytes')
reject('wrong_lease_plan',planfield('hostArguments',['--factory-capture-lease-seconds=41']),'exact prospective lease selection')
reject('wrong_runtime',planfield('runtimeSourceCommit','0'*40),'unchanged source/template/runtime/renderer authority')
reject('wrong_compiler',planfield('compilerHash','0'*64),'unchanged source/template/runtime/renderer authority')
reject('invented_measured_identity',raw('metadata/issue-before-launch.ps1','measuredHostIdentity=$null','measuredHostIdentity=\'invented\''),'prospective issuance before launch/no fabricated measurements')
print(json.dumps({'status':'passed','controls':rows,'nativeActions':0,'compilerActions':0},indent=2))
