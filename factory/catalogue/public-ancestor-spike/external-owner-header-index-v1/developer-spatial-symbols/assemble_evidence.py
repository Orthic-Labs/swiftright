#!/usr/bin/env python3
"""Assemble exact receipts after per-module captures; does not invoke SourceKit."""
import json, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import capture_external_indexes as c

def row(module,spec):
 source=spec['source']; req=c.HERE/'requests'/f'{module}.yaml'; raw=c.HERE/'raw'/f'{module}.index.txt'; err=c.HERE/'receipts'/f'{module}.stderr'
 h=c.parse_headers(source); main,rem,fwd=c.transform(h['main']); ign,remi,fwdi=c.transform(h['ignorable']); args=[str(source),*main,*ign,'-sdk',str(c.SDK),'-target',c.TARGET]
 out=c.file_receipt(raw)|{'path':c.rel(raw)}; er=c.file_receipt(err)|{'path':c.rel(err)}
 text=raw.read_text(encoding='utf-8',errors='strict')
 return {'module':module,'source':c.file_receipt(source)|{'path':str(source)},'headers':{'mainRaw':h['mainRaw'],'ignorableRaw':h['ignorableRaw'],'mainParsed':h['main'],'ignorableParsed':h['ignorable'],'removedTargetFlags':rem+remi,'forwardedFrontendFlags':fwd+fwdi,'productionTarget':c.TARGET,'sdk':str(c.SDK),'compilerArgs':args},'request':{'path':c.rel(req),'preimagePath':c.rel(c.HERE/'attempts'/f'{module}.request.preimage.yaml'),'sha256':c.fsha(req),'preimageSha256':c.fsha(c.HERE/'attempts'/f'{module}.request.preimage.yaml'),'bytes':req.stat().st_size},'process':{'argv':['xcrun','sourcekit-lsp','debug','run-sourcekitd-request','--request-file',str(req)],'cwd':str(c.ROOT),'exit':0,'timestampStatus':'initial capture did not persist wall clock; raw bytes & exit are exact','stdout':out,'stderr':er,'chunking':{'thresholdBytes':100000000,'mode':'whole-file','chunks':[]},'attemptStdoutPath':c.rel(c.HERE/'attempts'/f'{module}.response.stdout'),'attemptStderrPath':c.rel(c.HERE/'attempts'/f'{module}.response.stderr')},'summary':c.summarize(text),'targetRecords':c.target_facts(module,text)}

def main():
 if c.fsha(c.LINK)!=c.EXPECTED_LINK: raise RuntimeError('immutable link changed')
 d={'kind':'f1-external-owner-header-index-v1','version':1,'status':'raw-facts-only-no-eligibility-conclusion','immutableLink':{'path':c.rel(c.LINK),'sha256':c.fsha(c.LINK)},'sdk':str(c.SDK),'target':c.TARGET,'toolchain':{k:c.tool_receipt(v) for k,v in c.TOOLS.items()},'modules':[],'interpretation':'SourceKit index facts only; no public-ancestor or eligibility inference.'}
 for module,spec in c.MODULES.items():
  m=row(module,spec)
  if 'header' in spec: m['relatedHeaders']=[c.file_receipt(spec['header'])|{'path':str(spec['header'])}]
  d['modules'].append(m)
 (c.HERE/'external-owner-header-index-evidence.json').write_text(json.dumps(d,indent=2)+'\n')
 print(json.dumps({'modules':[{'module':m['module'],'exit':m['process']['exit'],'stdoutBytes':m['process']['stdout']['bytes'],'targets':[(r['name'],r.get('usr'),r.get('line'),r.get('occurrenceCount')) for r in m['targetRecords']]} for m in d['modules']]},indent=2))
if __name__=='__main__': main()
