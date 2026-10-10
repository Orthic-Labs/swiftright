import copy,importlib.util,json,unittest
from pathlib import Path
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('proof',HERE/'prove_access.py');g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
class ProofTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.seed=json.loads(g.SEED.read_text());cls.rows=cls.seed['rows'];cls.nodes={m:g.parse_ast((g.RAW/(m+'-arm64.stdout')).read_text(),m) for m in ['SwiftUI','SwiftUICore']};cls.indices=g.raw_indices();cls.d=g.demangle_rows((g.RAW/'demangle.stdout').read_text())
 def test_actual_positive(self):
  proof=g.verify_all();self.assertEqual(len(proof['rows']),42);self.assertEqual(proof['summary'],{'internal':20,'package':11,'public':6,'open':5});self.assertEqual(proof['promotionsMade'],0)
 def test_production_row_semantic_faults(self):
  row=self.rows[0];m=row['module'];self.assertEqual(g.evaluate(row,self.nodes[m],self.d,self.indices[m])['effectiveAccess'],'internal')
  faults=[('cursor-source-identity',lambda r:r['source'].update(sha256='sha256:'+'0'*64)),('cursor-destructor-identity',lambda r:r['cursor']['fields'].update(kind='source.lang.swift.decl.function.method.instance')),('cursor-destructor-identity',lambda r:r['cursor']['fields'].update(modulename='Other')),('source-line',lambda r:r.update(sourceLine='deinit')),('source-offset',lambda r:r.update(deinitByteOffset=r['deinitByteOffset']+1)),('source-conditions',lambda r:r.update(conditions=[])),('demangle-module',lambda r:r['cursor']['fields'].update(usr='s:wrong'))]
  for reason,mutate in faults:
   with self.subTest(reason=reason):
    candidate=copy.deepcopy(row);mutate(candidate)
    with self.assertRaisesRegex(ValueError,reason):g.evaluate(candidate,self.nodes[m],self.d,self.indices[m])
 def test_actual_ast_identity_and_owner_faults(self):
  row=self.rows[0];m=row['module'];nodes=self.nodes[m];index=next(i for i,n in enumerate(nodes) if n['line']==row['line'])
  faults=[('ast-destructor-access',lambda n:n.update(access='unknown')),('ast-destructor-access',lambda n:n.update(kind='func_decl')),('ast-destructor-access',lambda n:n.update(name='init')),('ast-owner-range',lambda n:n['owners'][0].update(line=1)),('ast-owner-source-range',lambda n:n['owners'][0].update(endLine=1)),('demangle-owner-chain',lambda n:n['owners'][0].update(name='WrongOwner')),('ast-derived-owner',lambda n:n['owners'][0].update(access=None)),('typed-destructor',lambda n:n.update(raw=n['raw']+' <error>')),('ast-derived-node',lambda n:n.update(access='public')),('ast-derived-owner',lambda n:n['owners'][0].update(access='public')),('ast-derived-node',lambda n:n.update(column=n['column']+1)),('ast-derived-node',lambda n:n.update(endColumn=n['endColumn']+1))]
  for reason,mutate in faults:
   with self.subTest(reason=reason):
    candidate=copy.deepcopy(nodes);mutate(candidate[index])
    with self.assertRaisesRegex(ValueError,reason):g.evaluate(row,candidate,self.d,self.indices[m])
  with self.assertRaisesRegex(ValueError,'ast-node-cardinality'):g.evaluate(row,nodes+[copy.deepcopy(nodes[index])],self.d,self.indices[m])
  candidate=copy.deepcopy(nodes);candidate[index]['source']='wrong'
  with self.assertRaisesRegex(ValueError,'ast-node-cardinality'):g.evaluate(row,candidate,self.d,self.indices[m])
 def test_coherent_raw_source_position_faults(self):
  row=self.rows[0];m=row['module'];nodes=self.nodes[m];index=next(i for i,n in enumerate(nodes) if n['line']==row['line']);actual=nodes[index]
  for before,after in [(f":{row['line']}:{actual['column']} -",f":{row['line']}:{actual['column']+1} -"),(f"line:{row['line']}:{actual['endColumn']}]",f"line:{row['line']}:{actual['endColumn']+1}]")]:
   candidate=copy.deepcopy(nodes);header=g.header_projection(actual['raw'].replace(before,after));header['owners']=candidate[index]['owners'];candidate[index]=header
   with self.subTest(before=before),self.assertRaisesRegex(ValueError,'ast-source-position'):g.evaluate(row,candidate,self.d,self.indices[m])
 def test_actual_demangle_owner_and_module_faults(self):
  row=self.rows[0];usr=row['cursor']['fields']['usr'];m=row['module']
  for field,val,reason in [('identifiers',['WrongOwner'],'demangle-derived-tree'),('nominalModule','Other','demangle-module')]:
   candidate=copy.deepcopy(self.d);candidate[usr][field]=val
   with self.assertRaisesRegex(ValueError,reason):g.evaluate(row,self.nodes[m],candidate,self.indices[m])
  text=(g.RAW/'demangle.stdout').read_text()
  with self.assertRaisesRegex(ValueError,'demangle-destructor-kind'):g.demangle_rows(text.replace('kind=Destructor','kind=Constructor',1))
  with self.assertRaisesRegex(ValueError,'duplicate-demangle'):g.demangle_rows(text+text)
 def test_strict_tree_and_raw_owner_production_faults(self):
  row=self.rows[0];m=row['module'];usr=row['cursor']['fields']['usr'];raw=self.d[usr]['raw']
  mutations=[('demangle-destructor-class',raw.replace('kind=Class','kind=Function',1)),('demangle-nominal-kind',raw.replace('      kind=Identifier','      kind=Module, text="Extra"\n      kind=Identifier',1)),('demangle-global',raw.replace('kind=Global','kind=Global\n  kind=Variable',1)),('demangle-derived-tree',raw.replace('text="SwiftUI"','text="Other"',1).replace('SwiftUI.','Other.',1))]
  for reason,body in mutations:
   candidate=copy.deepcopy(self.d);candidate[usr]['raw']=body
   with self.subTest(reason=reason),self.assertRaisesRegex(ValueError,reason):g.evaluate(row,self.nodes[m],candidate,self.indices[m])
  actual=next(i for i,e in enumerate(self.indices[m]) if e.get('usr')==usr and e.get('line')==row['line'])
  for reason,mutate in [('raw-owner-kind',lambda e:e['sourcekitContext'][0].update(kind='source.lang.swift.decl.struct')),('raw-owner-identity',lambda e:e['sourcekitContext'][0].update(name='Wrong')),('raw-owner-identity',lambda e:e['sourcekitContext'][0].update(line=1)),('raw-owner-usr',lambda e:e['sourcekitContext'][-1].update(usr='s:wrong'))]:
   records=copy.deepcopy(self.indices[m]);mutate(records[actual])
   with self.subTest(reason=reason),self.assertRaisesRegex(ValueError,reason):g.evaluate(row,self.nodes[m],self.d,records)
  with self.assertRaisesRegex(ValueError,'raw-member-cardinality'):g.evaluate(row,self.nodes[m],self.d,self.indices[m]+[self.indices[m][actual]])
 def test_production_capture_argv_source_tool_exit_faults(self):
  m='SwiftUI';r=json.loads((g.RAW/(m+'-arm64.receipt.json')).read_text());g.verify_receipt(m,r)
  faults=[('target-header-argv',lambda x:x['argv'].__setitem__(x['argv'].index(g.TARGET),'arm64e-apple-macos27.0')),('target-header-argv',lambda x:x['argv'].remove('-enable-library-evolution')),('capture-cwd',lambda x:x.update(cwd='/wrong')),('successful-semantic-ast',lambda x:x.update(exitCode=1)),('successful-semantic-ast',lambda x:x.update(timedOut=True)),('live-compiler',lambda x:x['tool'].update(sha256='sha256:'+'0'*64)),('live-source',lambda x:x['inputs'][0].update(sha256='sha256:'+'0'*64)),('raw-ast-stdout',lambda x:x['stdout'].update(sha256='sha256:'+'0'*64))]
  for reason,mutate in faults:
   with self.subTest(reason=reason):
    candidate=copy.deepcopy(r);mutate(candidate)
    with self.assertRaisesRegex(ValueError,reason):g.verify_receipt(m,candidate)
 def test_repository_fallback_same_artifact(self):
  expected=g.verify_all();original=Path.is_file
  with patch.object(Path,'is_file',lambda path:False if path.parent==g.RAW else original(path)):
   self.assertEqual(g.verify_all(),expected)
 def test_repository_archive_production_faults(self):
  original=Path.read_bytes;file=g.HERE/'raw-arm64-v2/SwiftUI-arm64.stdout'
  with patch.object(Path,'read_bytes',lambda path:original(path)+b'changed' if path==file else original(path)):
   with self.assertRaisesRegex(ValueError,'repository-archive-bytes'):g.verify_archive()
  original_manifest=g.archive_manifest();changed=copy.deepcopy(original_manifest);changed['rows'][0]['archivePath']='../escape'
  with patch.object(g,'archive_manifest',return_value=changed):
   with self.assertRaisesRegex(ValueError,'repository-archive-shape'):g.verify_archive()
  changed=copy.deepcopy(original_manifest);changed['rows'][0]['sha256']='0'*64
  with patch.object(g,'archive_manifest',return_value=changed):
   with self.assertRaisesRegex(ValueError,'repository-archive-bytes'):g.verify_archive()
  changed=copy.deepcopy(original_manifest);changed['rows']=changed['rows'][:-1]
  with patch.object(g,'archive_manifest',return_value=changed):
   with self.assertRaisesRegex(ValueError,'repository-archive-coverage'):g.verify_archive()
 def test_actual_raw_and_manifest_pin_faults(self):
  original=g.sha
  for f,reason in [(g.HERE/'raw-pins.json','raw-pin-manifest'),(g.RAW/'SwiftUI-arm64.stdout','raw-tool-request-pin'),(g.TOOL,'raw-tool-request-pin'),(g.SEED,'seed-pin')]:
   with self.subTest(path=f),patch.object(g,'sha',side_effect=lambda p: '0'*64 if Path(p)==f else original(p)):
    with self.assertRaisesRegex(ValueError,reason):g.verify_all()
if __name__=='__main__':unittest.main()
