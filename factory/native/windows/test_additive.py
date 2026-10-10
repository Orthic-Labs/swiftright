import json
from pathlib import Path
import tempfile
import unittest
from factory.core.artifacts import file_hash
from factory.native.windows.prepare_additive import prepare_additive, STAGE10_COMMIT
from factory.native.windows.runtime_receipt import receipt
from factory.native.windows.bind_closure import bind

class AdditiveBindingGuards(unittest.TestCase):
    def test_separate_runtime_and_immutable_stage_sources(self):
        lane=Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory(dir=lane,prefix='unit-additive-') as directory:
            d=Path(directory);runtime=d/'runtime';(runtime/'Sources').mkdir(parents=True)
            (runtime/'Package.swift').write_text('// synthetic source fixture\n')
            (runtime/'Sources/API.swift').write_text('// synthetic API fixture\n')
            source=d/'Witness.swift';source.write_text('import SwiftRightRuntime\nstruct Witness: View { var body: some View { Text("unit") } }\n')
            manifest=d/'manifest.json';manifest.write_text(json.dumps({'sourceFile':source.name,'sourceHash':file_hash(source),'witnessType':'Witness','case':{'id':'synthetic-unit-only','hash':'sha256:'+'1'*64},'compileExpectation':'success','executionEligible':False}))
            r=receipt(runtime,r'D:\Claude\factory-swiftright-unit\runtime','a'*40,synthetic=True)
            rp=d/'receipt.json';rp.write_text(json.dumps(r));output=d/'host'
            plan=prepare_additive(manifest,output,rp)
            self.assertEqual(file_hash(output/'Sources/FactoryProbe/Witness.swift'),file_hash(source))
            self.assertEqual(plan['runtimeSourceCommit'],'a'*40)
            self.assertEqual(plan['stageSourceCommit'],STAGE10_COMMIT)
            self.assertIn(r'D:\\Claude\\factory-swiftright-unit\\runtime',(output/'Package.swift').read_text())
            self.assertNotIn('sr0-r09',(output/'Package.swift').read_text())
            self.assertIn(r'D:\\Claude\\sr0-r10\\renderer',(output/'Sources/FactoryProbe/main.swift').read_text())
            self.assertFalse(plan['executionEligible']);self.assertIsNone(plan['closureBinding'])
            status=d/'status.md';status.write_text('**Overall: SR0 is OPEN.**\n')
            with self.assertRaisesRegex(ValueError,'CLOSED'):
                bind(output,status,d/'unused-staging',d/'unused-tuple')
            old_plan=(output/'plan.json').read_bytes()
            observation={'observedAt':'2026-01-02T00:00:00Z','exitCode':0,'sourceHash':plan['sourceHash'],'planSha256':file_hash(output/'plan.json').removeprefix('sha256:'),'exeSha256':'2'*64}
            (output/'observation.json').write_text(json.dumps(observation))
            status.write_text('**Overall: SR0 is CLOSED on tuple10.**\n')
            staging=d/'staging.md';staging.write_text(STAGE10_COMMIT+'\n'+plan['rendererSha256'])
            closure=d/'closure.json';closure.write_text(json.dumps({'tuple':'10','decision':'CLOSED','statusHash':file_hash(status),'closedAt':'2026-01-01T00:00:00Z'}))
            bound=bind(output,status,staging,None,closure_receipt=closure)
            self.assertEqual((output/'compile-plan.json').read_bytes(),old_plan)
            self.assertEqual(bound['sourceHash'],plan['sourceHash'])
            self.assertIsNone(bound['closureBinding']['tupleHash'])
            self.assertEqual(bound['compileBinding']['actualExecutableHash'],'sha256:'+'2'*64)
            self.assertTrue(bound['synthetic'])
            r['sourceCommit']=STAGE10_COMMIT;rp.write_text(json.dumps(r))
            with self.assertRaisesRegex(ValueError,'distinct'):
                prepare_additive(manifest,d/'rejected',rp)
            self.assertFalse((d/'rejected').exists())

if __name__=='__main__':unittest.main()
