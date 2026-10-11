"""Offline replay of actual root-run controls. No subprocess or producer mutation."""
from pathlib import Path
import hashlib,json,re,base64
P=Path(__file__).resolve().parent.parent
R=P.parents[3]
def h(b):return hashlib.sha256(b).hexdigest()
def j(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def check():
 transfer=j(P/'root-control-output-scp.json')
 assert len(transfer['transfers'])==4 and all(x['exitCode']==0 and not x['stderr'] for x in transfer['transfers'])
 pins=[]
 for path,pin in transfer['files'].items():
  b=(R/path).read_bytes();assert h(b)==pin,path;pins.append({'path':path,'bytes':len(b),'sha256':pin})
 start=j(P/'root-controls-start.json');process=j(P/'root-controls-process.json');entry=P/'root-controls-file-r1.ps1'
 assert h(entry.read_bytes())==start['scriptSha256']
 command=base64.b64decode(start['argv'][-1]).decode('utf-16-le')
 assert start['scriptSha256'] in command and start['scriptRemotePath'] in command
 assert process['startedAt']==start['startedAt'] and process['finishedAt']>process['startedAt'] and process['exitCode']==0
 for name,key in [('stdout','stdoutSha256'),('stderr','stderrSha256')]:assert h((P/('root-controls.'+name+'.bin')).read_bytes())==process[key]
 script=entry.read_text()
 sourcepins=re.findall(r"Get-FileHash -LiteralPath '([^']+)'\)\.Hash\.ToLowerInvariant\(\) -ne '([0-9a-f]{64})'",script)
 assert len(sourcepins)==28
 for path,pin in sourcepins:
  local=R/path.split('\\swiftright\\',1)[1].replace('\\','/');assert h(local.read_bytes())==pin,path
 parsed=j(P/'root-parse-actual-r1.json');assert len(parsed)==10
 for row in parsed:
  assert row['errors']==[];local=R/row['path'].split('\\swiftright\\',1)[1].replace('\\','/');assert h(local.read_bytes())==row['sha256']
 clean=j(P/'root-cleanup-actual-r1/controls.json');assert len(clean)==15
 normal={x['mode']:x for x in clean[:9]}
 for n in ['normal','already-exited','exit-race']:assert normal[n]['result']['confirmedOwnedExit']
 for n in ['identity-drift','timeout','retained-path','retained-start','zero-handle','unproven-exit']:assert not normal[n]['result']['confirmedOwnedExit']
 for n in ['identity-drift','retained-path','retained-start','zero-handle','unproven-exit']:assert not normal[n]['killed'] and not normal[n]['result']['killAttempted']
 assert normal['timeout']['result']['killAttempted']
 assert all(x['originalError']=='simulated capture failure' for x in clean[9:11])
 assert clean[11]['rejected'] is True
 for x in clean[12:]:assert x['released']==(x['acquired'] and x['exitConfirmed'])
 ns=j(P/'root-namespace-actual-r1/controls.json');assert len(ns)==7
 assert {x['name']:x['rejected'] for x in ns}=={'empty':False,'normal':False,'missing':True,'extra':True,'equal-count-wrong':True,'duplicate':True,'file':True}
 io=j(P/'root-stream-actual-r1/controls.json');assert len(io)==4
 for name in ['complete','unfinished','faulted','stdout','stderr']:assert (P/('root-stream-actual-r1/'+name+'.bin')).read_bytes()==b'raw stdout bytes\n'
 assert io[0]['bytes']==17 and io[0]['sha256']==h(b'raw stdout bytes\n')
 assert all(x['rejected'] and x['sealed'] is False for x in io[1:3]) and io[3]['hashedFiles']==5
 return {'status':'actual-controls-clear','actualASTScripts':10,'cleanupControls':15,'namespaceControls':7,'streamControls':4,'entrySourcePins':len(sourcepins),'outputPins':pins,'processExit':0,'stderr':'CLIXML first-use progress only; stdout preserves three VoidTaskResult messages','nativeRunsByReviewer':0,'producerEdits':0}
if __name__=='__main__':print(json.dumps(check(),indent=2))
