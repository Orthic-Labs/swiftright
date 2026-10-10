"""Ephemeral unit metadata only; no capture artifacts or native replay claims."""
import json
from pathlib import Path
import tempfile
import unittest
from factory.core.artifacts import canonical_hash,file_hash,write_artifact
from factory.native.windows.additive_archive import validate

class AdditiveArchiveGuards(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        p=self.root
        (p/'Sources/FactoryProbe').mkdir(parents=True);(p/'evidence').mkdir()
        (p/'Sources/FactoryProbe/Witness.swift').write_text('// UNIT ONLY; no native execution\n')
        (p/'evidence/FactoryProbe.exe').write_bytes(b'UNIT ONLY, not executable')
        (p/'sr0-status-closed.md').write_text('**Overall: SR0 is CLOSED on tuple10.**\n')
        (p/'sr0-tuple10-staging.md').write_text('UNIT ONLY staging metadata')
        closure={'tuple':'10','decision':'CLOSED','statusHash':file_hash(p/'sr0-status-closed.md'),'closedAt':'2026-01-01T00:00:00Z'}
        write_artifact(p/'closure-receipt.json',closure)
        tree=[{'path':'Package.swift','sha256':'sha256:'+'3'*64}]
        runtime={'sourceCommit':'a'*40,'sourceTreeHash':canonical_hash(tree),'sourceBindings':tree,'unitNote':'unit byte binding fixture, never native evidence'}
        write_artifact(p/'runtime-source-tree.json',tree);write_artifact(p/'runtime-source-receipt.json',runtime)
        self.tuple=p/'tuple.json';write_artifact(self.tuple,{'runtimeCommit':'a'*40})
        self.plan={'unitNote':'unit metadata only','sourceHash':file_hash(p/'Sources/FactoryProbe/Witness.swift'),'case':{'id':'unit-only','hash':'sha256:'+'5'*64},'runtimeSourceCommit':'a'*40,'runtimeSourceTreeHash':canonical_hash(tree),'runtimeSourceReceiptHash':file_hash(p/'runtime-source-receipt.json'),'stageSourceCommit':'b'*40,'rendererSha256':'c'*64,'sourceBindings':[{'path':'Sources/FactoryProbe/Witness.swift','sha256':file_hash(p/'Sources/FactoryProbe/Witness.swift')}],
            'closureBinding':{**closure,'receiptHash':file_hash(p/'closure-receipt.json'),'tupleHash':file_hash(self.tuple),'tuple10StagingHash':file_hash(p/'sr0-tuple10-staging.md')}}
        write_artifact(p/'plan.json',self.plan)
        self.obs={k:self.plan[k] for k in ('sourceHash','runtimeSourceCommit','runtimeSourceTreeHash','stageSourceCommit','rendererSha256')}
        self.obs.update(exitCode=0,observedAt='2026-01-02T00:00:00Z',planSha256=file_hash(p/'plan.json').removeprefix('sha256:'),exeSha256=file_hash(p/'evidence/FactoryProbe.exe').removeprefix('sha256:'))
        write_artifact(p/'observation.json',self.obs)
        self.rows=[{**self.obs,'case':self.plan['case']}]
    def check(self):return validate(self.root,self.plan,self.rows,self.tuple)
    def test_complete_unit_bindings(self):
        copies=self.check();self.assertIn(Path('runtime-source-tree.json'),copies);self.assertIn(Path('Sources/FactoryProbe/Witness.swift'),copies)
    def test_missing_runtime_receipt(self):
        (self.root/'runtime-source-receipt.json').rename(self.root/'omitted-unit-receipt.json')
        with self.assertRaisesRegex(ValueError,'missing required'):self.check()
    def test_drifted_inner_receipt(self):
        path=self.root/'runtime-source-receipt.json';receipt=json.loads(path.read_text());receipt['sourceCommit']='d'*40;write_artifact(path,receipt)
        self.plan['runtimeSourceReceiptHash']=file_hash(path)
        with self.assertRaisesRegex(ValueError,'receipt/tree differs'):self.check()
    def test_nested_synthetic_receipt(self):
        path=self.root/'runtime-source-receipt.json';receipt=json.loads(path.read_text());receipt['context']={'synthetic':True};write_artifact(path,receipt)
        with self.assertRaisesRegex(ValueError,'nested synthetic'):self.check()
    def test_historical_row_relabel(self):
        self.rows[0]['runtimeSourceCommit']='8e47b89b3e9ae488e77ea8b5a2e4663053601c0d'
        with self.assertRaisesRegex(ValueError,'replay identity differs'):self.check()
    def test_missing_compile_archive(self):
        self.plan['compileBinding']={'planHash':'sha256:'+'0'*64}
        with self.assertRaisesRegex(ValueError,'missing required.*compile-plan'):self.check()
    def test_drifted_compile_tree(self):
        self.obs['runtimeSourceTreeHash']='sha256:'+'0'*64;write_artifact(self.root/'observation.json',self.obs)
        with self.assertRaisesRegex(ValueError,'compile identity differs'):self.check()
