from pathlib import Path
import importlib.util,json,hashlib,gzip
H=Path(__file__).resolve().parent
sp=importlib.util.spec_from_file_location('transport',H/'transport.py');m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
s=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$r='ROOT';$files=@();$bin='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin';foreach($n in 'swift-frontend.exe','swift-test.exe','swift-driver.exe'){$p=Join-Path $bin $n;if(Test-Path -LiteralPath $p){$f=Get-Item -LiteralPath $p;$files+=[ordered]@{category='compiler';name=$n;path=$f.FullName;bytes=[int64]$f.Length;sha256=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant();creationTimeUtc=$f.CreationTimeUtc.ToString('o');lastWriteTimeUtc=$f.LastWriteTimeUtc.ToString('o')}}};foreach($n in 'original','retained','terminal'){$p=Join-Path $r ($n+'\scratch\out\Products\Release-windows-x86_64');foreach($f in @(Get-ChildItem -LiteralPath $p -File|Where-Object {$_.Extension -in '.dll','.exe'})){$files+=[ordered]@{category=$n;name=$f.Name;path=$f.FullName;bytes=[int64]$f.Length;sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant();creationTimeUtc=$f.CreationTimeUtc.ToString('o');lastWriteTimeUtc=$f.LastWriteTimeUtc.ToString('o')}}};[ordered]@{schema='taskid-native-artifact-bindings-v1';utc=[DateTime]::UtcNow.ToString('o');files=$files;compilerExecutions=0;testExecutions=0}|ConvertTo-Json -Depth 8'''.replace('ROOT',m.REMOTE_RUN)
m.call('native-artifact-binding',m.ps(s))
bind=json.loads((H/'native-artifact-binding.stdout.bin').read_text(encoding='utf-8-sig'))
sha=lambda b:hashlib.sha256(b).hexdigest()
rows=[]
for i,b in enumerate(bind['files']):
 dest=H/'results/native-artifacts'/b['category']/b['name'];dest.parent.mkdir(parents=True,exist_ok=True)
 m.call('scp-native-artifact-'+str(i),['scp','-o','BatchMode=yes','-o','ConnectTimeout=10','win:'+b['path'].replace('\\','/'),str(dest)])
 assert dest.stat().st_size==b['bytes'] and sha(dest.read_bytes())==b['sha256']
 chunks=[]
 if dest.stat().st_size>50_000_000:
  with dest.open('rb') as f:
   index=0;offset=0
   while raw:=f.read(32*1024*1024):
    part=dest.parent/(dest.name+'.part%03d.gz'%index);part.write_bytes(gzip.compress(raw,mtime=0));chunks.append(dict(path=part.relative_to(H).as_posix(),bytes=part.stat().st_size,sha256=sha(part.read_bytes()),rawBytes=len(raw),rawSha256=sha(raw),offset=offset));offset+=len(raw);index+=1
 rows.append(dict(**b,localPath=dest.relative_to(H).as_posix(),chunks=chunks))
(H/'native-artifact-archive.json').write_text(json.dumps(dict(schema='taskid-native-artifact-archive-v1',files=rows),indent=2)+'\n')
