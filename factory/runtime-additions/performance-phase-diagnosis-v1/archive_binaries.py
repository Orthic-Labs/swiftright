"""Archive existing consumed executables; never execute remote binaries."""
import base64,gzip,hashlib,json,subprocess
from pathlib import Path,PureWindowsPath
HERE=Path(__file__).resolve().parent
receipt=json.loads((HERE/'captured-corrected/receipt.json').read_text(encoding='utf-8-sig'))
rows=[]
for h in receipt['hosts']:
 for kind,path,expected in [('runner',h['binary'],h['binaryHash']),('testLibrary',str(PureWindowsPath(h['binary']).parent/'SwiftRightRuntimeTests.dll'),h['dllHash'])]:
  literal="'"+path.replace("'","''")+"'"
  script='$ErrorActionPreference="Stop";$p='+literal+';$b=[IO.File]::ReadAllBytes($p);[ordered]@{path=$p;sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant();bytes=$b.Length;base64=[Convert]::ToBase64String($b)}|ConvertTo-Json -Compress'
  r=subprocess.run(['ssh','-o','BatchMode=yes','win','powershell','-NoProfile','-EncodedCommand',base64.b64encode(script.encode('utf-16le')).decode()],capture_output=True,timeout=120)
  assert r.returncode==0,r.stderr
  row=json.loads(r.stdout.decode('utf-8-sig'));raw=base64.b64decode(row.pop('base64'))
  assert hashlib.sha256(raw).hexdigest()==expected==row['sha256'] and len(raw)==row['bytes']
  archive='binary-archives/'+h['label']+'-'+kind+'.gz';p=HERE/archive;p.parent.mkdir(exist_ok=True)
  compressed=gzip.compress(raw,mtime=0)
  if p.exists():assert p.read_bytes()==compressed
  else:p.write_bytes(compressed)
  row.update(label=h['label'],kind=kind,archive=archive,archiveSha256=hashlib.sha256(compressed).hexdigest(),archiveBytes=len(compressed));rows.append(row)
(HERE/'binary-archive-manifest.json').write_text(json.dumps({'schema':'consumed-binary-archive-v1','operation':'Read existing retained bytes only; no native execution','files':rows},indent=2)+'\n')
print('Archived',len(rows),'consumed binaries;',sum(x['archiveBytes'] for x in rows),'compressed bytes')
