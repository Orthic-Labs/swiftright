#!/usr/bin/env python3
"""Boundary and immutable-input tests for exact enum-case bridge validator."""
from __future__ import annotations
import copy,hashlib,json,sys,unittest
from tempfile import TemporaryDirectory
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(HERE))
import exact_access_bridge as bridge

class ExactAccessBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.link=json.loads((ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json').read_text())
        cls.derived=json.loads((HERE/'derived-access-bridge.json').read_text())
        cls.row=next(r for r in cls.link['rows'] if r['module']=='SwiftUICore' and r['line']==15328)
        cls.module_record=next(i for i in cls.link['interfaces'] if i['module']==cls.row['module'])
        cls.interface=Path(cls.module_record['path'])
        cls.raw_path=ROOT/cls.module_record['indexOutput']
        cls.raw=bridge.parse_index_declarations(cls.raw_path)
        cls.scopes=bridge.parse_lexical_scopes(cls.interface)[cls.row['line']]
        cls.live_hash=hashlib.sha256(cls.interface.read_bytes()).hexdigest()
        cls.entity=bridge.exact_raw_entity(cls.row,cls.raw,cls.row['module'])
    def assert_rejected(self,row=None,entities=None,scopes=None,module=None,raw_module=None,
                        live_hash=None,request_exact=True,reason=None):
        with self.assertRaises(ValueError) as error:
            bridge.validate_case_link(row or copy.deepcopy(self.row),
              entities if entities is not None else [copy.deepcopy(self.entity)],
              scopes if scopes is not None else copy.deepcopy(self.scopes),
              module=module or self.row['module'],raw_entity_module=raw_module or self.row['module'],
              live_interface_sha256=live_hash or self.live_hash,request_is_exact=request_exact)
        if reason: self.assertIn(reason,str(error.exception))
    def test_all_51_cases_have_full_scoped_unique_compiler_bridge(self):
        self.assertEqual({'sourceRows':51,'validatedRows':51,'heldRows':0,'uniqueCompilerUsrs':51},
                         self.derived['summary'])
        self.assertEqual(bridge.EXPECTED_LINK_SHA256,
                         self.derived['bindings']['sourceLinkSha256'].removeprefix('sha256:'))
        self.assertEqual('sha256:'+bridge.EXPECTED_SEED_SHA256,self.derived['seedAccessEvidenceSha256'])
        self.assertEqual('sha256:'+bridge.EXPECTED_RECEIPT_SHA256,self.derived['seedRunReceiptSha256'])
        self.assertEqual(51,len({r['usr'] for r in self.derived['rows']}))
        for row in self.derived['rows']:
            self.assertEqual(len(row['context']),len(row['lexicalScopes']))
            self.assertEqual(row['context'],[s['name'] for s in row['lexicalScopes']])
            self.assertEqual('enum',row['lexicalScopes'][-1]['kind'])
            self.assertTrue(all(s['resolvedAccess'] in ('public','open') for s in row['lexicalScopes']))
            for scope in row['lexicalScopes']:
                if scope['kind']=='extension':
                    self.assertEqual(scope['qualifiedTarget'],scope['resolvedQualifiedName'])
                    self.assertEqual(scope['qualifiedTarget'],scope['resolvedOwnerChain'][-1]['qualifiedName'])
                    self.assertTrue(all(owner['resolvedAccess'] in ('public','open')
                                        for owner in scope['resolvedOwnerChain']))
            self.assertTrue(all(s.get('scopeRole')=='resolved-extension-ancestor' or
                                s['startLine']<=row['line']<=s['endLine'] for s in row['lexicalScopes']))
            self.assertEqual('public',row['effectiveAccess'])
            self.assertEqual(1,row['rawEntityCount'])
    def test_derived_evidence_binds_live_interface_request_raw_and_toolchain_bytes(self):
        bindings=self.derived['bindings']
        def matches(path,expected):
            self.assertEqual(expected,'sha256:'+hashlib.sha256(Path(path).read_bytes()).hexdigest(),str(path))
        matches(HERE/'access-evidence.json',self.derived['seedAccessEvidenceSha256'])
        matches(HERE/'run-receipt.json',self.derived['seedRunReceiptSha256'])
        matches(HERE/'exact_access_bridge.py',self.derived['validatorSourceSha256'])
        self.assertEqual(bridge.EXPECTED_LINK_SHA256,
                         bindings['sourceLinkSha256'].removeprefix('sha256:'))
        matches(ROOT/bindings['sourceLinkPath'],bindings['sourceLinkSha256'])
        matches(bindings['sdkSettingsPath'],bindings['sdkSettingsSha256'])
        for record in (bindings['compiler'],bindings['sourcekitLsp'],bindings['sourcekitd']):
            path=record.get('executablePath',record.get('path'))
            matches(path,record['sha256'])
        for module,record in self.derived['modules'].items():
            with self.subTest(module=module):
                matches(record['interfacePath'],record['interfaceSha256'])
                matches(ROOT/record['requestPath'],record['requestSha256'])
                matches(ROOT/record['rawOutputPath'],record['rawOutputSha256'])
                self.assertEqual(module,record['requestIdentity']['moduleName'])
                self.assertEqual(bridge.TARGET,record['requestIdentity']['target'])
                self.assertTrue(bridge.validate_request_binding(
                    (ROOT/record['requestPath']).read_text(),interface=record['interfacePath'],
                    sdk=bindings['sdkPath'],target=bridge.TARGET,module=module))
    def test_single_candidate_returns_raw_usr_and_complete_scope_ranges(self):
        got=bridge.validate_case_link(copy.deepcopy(self.row),[copy.deepcopy(self.entity)],
          copy.deepcopy(self.scopes),module='SwiftUICore',raw_entity_module='SwiftUICore',
          live_interface_sha256=self.live_hash,request_is_exact=True)
        evidence=next(r for r in self.derived['rows'] if r['auditRowKey']==self.row['auditRowKey'])
        self.assertEqual(self.entity['usr'],got['usr'])
        self.assertEqual(evidence['lexicalScopes'],got['lexicalScopes'])
    def test_wrong_lexical_owner_fails(self):
        scopes=copy.deepcopy(self.scopes); scopes[-1]['name']='WrongOwner'
        self.assert_rejected(scopes=scopes,reason='lexical owner/context mismatch')
    def test_public_outer_does_not_override_private_nested_enum(self):
        scopes=copy.deepcopy(self.scopes); scopes[-1]['explicitAccess']='private'; scopes[-1]['resolvedAccess']='private'
        self.assertEqual('public',scopes[0]['resolvedAccess'])
        self.assert_rejected(scopes=scopes,reason='not explicitly public/open')
    def test_wrong_module_fails(self):
        self.assert_rejected(module='SwiftUI',reason='wrong module identity')
        self.assert_rejected(raw_module='SwiftUI',reason='wrong module identity')
    def test_missing_access_and_duplicate_records_fail(self):
        entity=copy.deepcopy(self.entity); entity.pop('effective_access',None)
        self.assert_rejected(entities=[entity],reason='compiler effective access is unknown')
        self.assert_rejected(entities=[copy.deepcopy(self.entity),copy.deepcopy(self.entity)],
                             reason='raw entity cardinality 2')
        implicit=copy.deepcopy(self.entity); implicit['is_implicit']=1
        self.assert_rejected(entities=[implicit],reason='raw declaration is implicit')
    def test_private_internal_package_unknown_access_fail(self):
        for access in ('private','internal','package','fileprivate','less_than_fileprivate','unknown'):
            with self.subTest(access=access):
                entity=copy.deepcopy(self.entity)
                entity['effective_access']='source.decl.effective_access.'+access
                self.assert_rejected(entities=[entity],reason='compiler effective access is '+access)
    def test_wrong_hash_scope_range_and_request_identity_fail(self):
        self.assert_rejected(live_hash='0'*64,reason='interface source hash mismatch')
        scopes=copy.deepcopy(self.scopes); scopes[-1]['endLine']=self.row['line']-1
        self.assert_rejected(scopes=scopes,reason='scope range')
        self.assert_rejected(request_exact=False,reason='request identity')
        req=(HERE/'request-index-fixture.yaml').read_text()
        self.assertFalse(bridge.validate_request_binding(req,interface=str(self.interface),sdk=str(bridge.SDK),
             target=bridge.TARGET,module='SwiftUICore'))
    def test_exact_core_request_is_module_specific(self):
        item=self.module_record
        req=(ROOT/item['indexRequest']).read_text()
        self.assertTrue(bridge.validate_request_binding(req,interface=item['path'],sdk=str(bridge.SDK),
             target=bridge.TARGET,module='SwiftUICore'))
        self.assertFalse(bridge.validate_request_binding(req,interface=item['path'],sdk=str(bridge.SDK),
             target=bridge.TARGET,module='SwiftUI'))
    def test_extension_resolution_rejects_wrong_module_and_nested_same_basename(self):
        fixtures=(
          ('wrong-module','public enum Font {}\nextension SwiftUI::Font {\n public enum Bucket {\n  case item\n }\n}\n'),
          ('nested-private','public enum Outer {\n private enum Font {}\n}\nextension Font {\n public enum Bucket {\n  case item\n }\n}\n'))
        for label,source in fixtures:
            with self.subTest(fault=label),TemporaryDirectory() as tmp:
                interface=Path(tmp)/'Fixture.swiftinterface'; interface.write_text(source)
                case_line=source.splitlines().index('  case item')+1
                scopes=bridge.parse_lexical_scopes(interface,'SwiftUICore')[case_line]
                row={'kind':'case','module':'SwiftUICore','sourceHash':'sha256:'+hashlib.sha256(interface.read_bytes()).hexdigest(),
                     'line':case_line,'name':'item','context':['Font','Bucket']}
                raw=[{'kind':'source.lang.swift.decl.enumelement','name':'item','usr':'test-usr','line':case_line,
                      'effective_access':'source.decl.effective_access.public',
                      'sourcekitContext':[{'kind':'source.lang.swift.decl.extension.struct','name':'Font'},
                                          {'kind':'source.lang.swift.decl.enum','name':'Bucket'}]}]
                with self.assertRaisesRegex(ValueError,'public/open'):
                    bridge.validate_case_link(row,raw,scopes,module='SwiftUICore',raw_entity_module='SwiftUICore',
                      live_interface_sha256=row['sourceHash'].removeprefix('sha256:'),request_is_exact=True)
    def test_parser_rejects_private_enum_nested_in_public_outer(self):
        source='public enum Outer {\n private enum Inner {\n  case item\n }\n}\n'
        with TemporaryDirectory() as tmp:
            interface=Path(tmp)/'Fixture.swiftinterface'; interface.write_text(source)
            case_line=source.splitlines().index('  case item')+1
            scopes=bridge.parse_lexical_scopes(interface,'SwiftUICore')[case_line]
            self.assertEqual(['Outer','Inner'],[s['name'] for s in scopes])
            self.assertEqual('public',scopes[0]['resolvedAccess'])
            self.assertEqual('private',scopes[1]['resolvedAccess'])
            row={'kind':'case','module':'SwiftUICore','sourceHash':'sha256:'+hashlib.sha256(interface.read_bytes()).hexdigest(),
                 'line':case_line,'name':'item','context':['Outer','Inner']}
            raw=[{'kind':'source.lang.swift.decl.enumelement','name':'item','usr':'test-usr','line':case_line,
                  'effective_access':'source.decl.effective_access.private',
                  'sourcekitContext':[{'kind':'source.lang.swift.decl.enum','name':'Outer'},
                                      {'kind':'source.lang.swift.decl.enum','name':'Inner'}]}]
            with self.assertRaisesRegex(ValueError,'public/open'):
                bridge.validate_case_link(row,raw,scopes,module='SwiftUICore',raw_entity_module='SwiftUICore',
                  live_interface_sha256=row['sourceHash'].removeprefix('sha256:'),request_is_exact=True)
    def test_extension_of_public_nested_type_retains_private_original_outer(self):
        source=('private struct Outer {\n public struct Inner {}\n}\n'
                'extension Outer.Inner {\n public enum Bucket {\n  case item\n }\n}\n')
        with TemporaryDirectory() as tmp:
            interface=Path(tmp)/'Fixture.swiftinterface'; interface.write_text(source)
            case_line=source.splitlines().index('  case item')+1
            scopes=bridge.parse_lexical_scopes(interface,'SwiftUICore')[case_line]
            self.assertEqual(['Outer','Inner','Bucket'],[s['name'] for s in scopes])
            self.assertEqual(['private','public','public'],[s['resolvedAccess'] for s in scopes])
            row={'kind':'case','module':'SwiftUICore','sourceHash':'sha256:'+hashlib.sha256(interface.read_bytes()).hexdigest(),
                 'line':case_line,'name':'item','context':['Outer','Inner','Bucket']}
            raw=[{'kind':'source.lang.swift.decl.enumelement','name':'item','usr':'test-usr','line':case_line,
                  'effective_access':'source.decl.effective_access.public',
                  'sourcekitContext':[{'kind':'source.lang.swift.decl.struct','name':'Outer'},
                    {'kind':'source.lang.swift.decl.extension.struct','name':'Inner'},
                    {'kind':'source.lang.swift.decl.enum','name':'Bucket'}]}]
            with self.assertRaisesRegex(ValueError,'public/open'):
                bridge.validate_case_link(row,raw,scopes,module='SwiftUICore',raw_entity_module='SwiftUICore',
                  live_interface_sha256=row['sourceHash'].removeprefix('sha256:'),request_is_exact=True)

if __name__=='__main__': unittest.main()
