"""Frozen evaluate body; sole delta validates exact SHA-pinned recorded path pair.
Reader facts supply source text/hash; filesystem resolution is never invoked.
"""
def evaluate(row,nodes,demangles,index_records):
 m=row['module'];src=source(m);fields=row['cursor']['fields'];line=row['line']
 require(fields['kind']=='source.lang.swift.decl.function.destructor' and fields['name']=='deinit' and fields['modulename']==m and fields['line']==line,'cursor-destructor-identity')
 require(cursor_source_identity(fields,src) and row['source']['sha256']=='sha256:'+sha(src),'cursor-source-identity')
 lines=src.read_text().splitlines(keepends=True);text=lines[line-1].rstrip('\r\n')
 require(row['sourceLine']==text and 'deinit' in text,'source-line')
 require(row['conditions']==source_conditions(lines,line),'source-conditions')
 offset=sum(len(x.encode()) for x in lines[:line-1])+len(text[:text.index('deinit')].encode())
 require(row['deinitByteOffset']==fields['offset']==offset,'source-offset')
 matches=[n for n in nodes if n['line']==line and n['source']==str(src)]
 require(len(matches)==1,'ast-node-cardinality');node=matches[0]
 require(node['kind']=='destructor_decl' and node['name']=='deinit' and node['access'] in {'public','open','internal','package','private','fileprivate'},'ast-destructor-access')
 require(header_projection(node['raw'])=={k:v for k,v in node.items() if k!='owners'},'ast-derived-node')
 require('<error' not in node['raw'] and 'interface_type=' in node['raw'],'typed-destructor')
 require(node['column']==fields['column']==len(text[:text.index('deinit')])+1 and node['endLine']==line and node['endColumn']==node['column'],'ast-source-position')
 owners=node['owners'];require([n['line'] for n in owners]==row['scopeLines'] and bool(owners),'ast-owner-range')
 require(all(n['source']==str(src) and n['line']<=line<=n['endLine'] for n in owners),'ast-owner-source-range')
 d=demangles.get(fields['usr']);require(d is not None and (d['extensionModule'] or d['nominalModule'])==m,'demangle-module')
 require(d['nominalModule']==('__C' if (m,line)==('SwiftUI',32548) else m) and (d['extensionModule'] is None or owners[0]['kind']=='extension_decl'),'demangle-nominal-module')
 require(d==demangle_rows('Demangling for $s'+fields['usr'][2:]+'\n'+d['raw'])[fields['usr']],'demangle-derived-tree')
 require([n['name'] for n in owners]==d['identifiers'],'demangle-owner-chain')
 raw=[e for e in index_records if e.get('usr')==fields['usr'] and e.get('line')==line and e.get('name')=='deinit']
 require(len(raw)==1,'raw-member-cardinality');entity=raw[0]
 require(entity['kind']=='source.lang.swift.decl.function.destructor' and entity['column']==fields['column'],'raw-member-kind-position')
 context=entity['sourcekitContext'];require(len(context)==len(owners),'raw-owner-cardinality')
 kinds={'class_decl':'class','struct_decl':'struct','enum_decl':'enum'};nominals={'Class':'class','Structure':'struct','Enum':'enum'}
 for index,(owner,raw_owner,nominal_kind) in enumerate(zip(owners,context,d['ownerKinds'])):
  require(owner['name']==raw_owner['name'] and owner['line']==raw_owner['line'],'raw-owner-identity')
  expected='source.lang.swift.decl.'+('extension.' if owner['kind']=='extension_decl' else '')+nominals[nominal_kind]
  require(raw_owner['kind']==expected and (owner['kind']=='extension_decl' or kinds.get(owner['kind'])==nominals[nominal_kind]),'raw-owner-kind')
 require(context[-1]['usr']==fields['usr'][:-2],'raw-owner-usr')

 require(all(header_projection(n['raw'])==n for n in owners),'ast-derived-owner')
 require(all(n['kind']=='extension_decl' or n['access'] in {'public','open','internal','package','private','fileprivate'} for n in owners),'typed-owner-access')
 return {'module':m,'line':line,'usr':fields['usr'],'usrIdentityScope':'frozen836 textual SourceKit index/cursor lineage; AST emits no declaration USR & canonical ABI namespace is not asserted','source':row['source'],'deinitByteOffset':offset,'conditions':row['conditions'],'target':TARGET,'targetVariant':None,'effectiveAccess':node['access'],'astNode':node,'demangle':d,'rawIndexEntity':entity,'cursorResponse':row['response'],'sourceKitRequest':row['request'],'interpretation':'compiler-reported-member-access; enclosing-owner eligibility remains separate'}
