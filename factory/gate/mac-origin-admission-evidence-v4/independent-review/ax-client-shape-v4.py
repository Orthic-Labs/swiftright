from pathlib import Path
import sys,tempfile,json,copy,importlib.util
ROOT=Path(__file__).resolve().parents[4];sys.path.insert(0,str(ROOT))
from factory.gate.test_mac_origin_admission import OriginFixture,sha
spec=importlib.util.spec_from_file_location('guard',Path(__file__).parent/'source-snapshot-v4/mac_origin_admission.py');g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
rows=[]
for bad in [None,[], 'AVAILABLE']:
 with tempfile.TemporaryDirectory() as directory:
  f=OriginFixture(Path(directory));source=f._write('ax/AXClient.swift',b'struct AXClient {}\n');binary=f._write('ax/client',b'AX fixture\n');ax=copy.deepcopy(f.receipt);c=ax['compiler']
  c['sourceBefore']={'AXClient.swift':f._ref('ax/AXClient.swift')};c['sourceAfter']=copy.deepcopy(c['sourceBefore']);ax['sourceBefore']=c['sourceBefore'];ax['sourceAfter']=c['sourceAfter'];c['cwd']=str(source.parent);c['argv']=[str(f.root/'bin/swiftc'),'-O','-o',str(binary),str(source)];c['outputBinary']=f._ref('ax/client')
  axref=f._ref('ax-receipt.json',f._json(ax));origin=f.capture['meta']['conditions']['macOrigin'];origin['auxiliaryAX']={'receipt':axref,'source':f._ref('ax/AXClient.swift'),'binary':f._ref('ax/client')}
  f.summary['freshAXClient']={'externalAX':'AVAILABLE','sourceHash':origin['auxiliaryAX']['source']['sha256'],'binaryHash':origin['auxiliaryAX']['binary']['sha256'],'compilerReceiptHash':axref['sha256'],'compilerStatus':'SUCCESS','compilerExitCode':0};f.refresh_summary();assert not g.mac_origin_admission_issues(f.capture,f.reader)
  f.summary['freshAXClient']=bad;f.refresh_summary()
  try:issues=g.mac_origin_admission_issues(f.capture,f.reader);rows.append({'value':bad,'issues':issues})
  except Exception as e:rows.append({'value':bad,'exception':type(e).__name__+': '+str(e)})
print(json.dumps({'kind':'isolated-AX-client-nested-shape-v4','synthetic':True,'cleanAuxiliaryAXBaselinePassed':True,'rows':rows,'nativeCompilerRuns':0},indent=2))
