#!/usr/bin/env python3
import hashlib,json,sys,unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
class EnumCaseCompilerAccessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence=json.loads((HERE/'access-evidence.json').read_text())
        cls.receipt=json.loads((HERE/'run-receipt.json').read_text())
        cls.rows=cls.evidence['rows']
    def test_all_held_rows_have_one_exact_raw_compiler_access_witness(self):
        self.assertEqual(51,self.evidence['summary']['rows'])
        self.assertEqual(51,self.evidence['summary']['uniqueExactRawPublicEntities'])
        self.assertEqual(51,self.evidence['summary']['distinctCompilerUsrs'])
        self.assertEqual(51,len({r['auditRowKey'] for r in self.rows}))
        for row in self.rows:
            self.assertEqual(1,row['rawEntityCount'],row['auditRowKey'])
            self.assertEqual('source.lang.swift.decl.enumelement',row['entities'][0]['kind'])
            self.assertEqual('source.decl.effective_access.public',row['entities'][0]['effectiveAccess'])
            self.assertIn(row['lexicalOwnerEnum']['explicitAccess'],('public','open'))
            self.assertEqual(row['sourceHash'],self.receipt['sourceHashes'][row['module']])
    def test_sourcekit_private_internal_and_public_fault_controls(self):
        by_line={x['line']:x for x in self.evidence['fixtureAccessControls']}
        expected={2:'public',6:'internal',10:'fileprivate',15:'public',19:'internal',23:'less_than_fileprivate',27:'internal'}
        self.assertEqual(expected,{n:by_line[n]['effectiveAccess'] for n in expected})
    def test_actual_client_import_and_negative_compiler_controls(self):
        results={x['name']:x for x in self.receipt['commands']}
        self.assertEqual(0,results['actual-sdk-enum-cases-importable']['exitCode'])
        self.assertEqual(0,results['fixture-positive-public-cases']['exitCode'])
        for name in ('fixture-internal-case-rejected','fixture-private-nested-case-rejected',
                     'fixture-internal-default-nested-case-rejected','fixture-fileprivate-case-rejected'):
            self.assertEqual(1,results[name]['exitCode'],name)
    def test_link_evidence_identity_is_fixed(self):
        link=ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json'
        actual='sha256:'+hashlib.sha256(link.read_bytes()).hexdigest()
        self.assertEqual(self.evidence['sourceLinkEvidenceSha256'],actual)
        self.assertEqual(self.receipt['sourceLinkEvidenceSha256'],actual)
if __name__=='__main__': unittest.main()
