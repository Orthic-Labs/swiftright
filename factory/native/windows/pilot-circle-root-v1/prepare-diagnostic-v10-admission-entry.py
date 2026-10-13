#!/usr/bin/env python3
"""Emit bounded self-contained Windows admission entry for Circle diagnostic r10b.

Source-only: embeds named measured packet files, verifies bytes on Windows, then
invokes original installer with explicit plan/receipt/binary/stage arguments.
"""
from __future__ import annotations
import argparse, base64, hashlib, json, os, stat
from pathlib import Path

MAX_EMBED=2*1024*1024
REPO=Path(__file__).resolve().parents[4]
CACHE=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/git-root')
SRC=REPO/'factory/native/windows/pilot-circle-root-v1'
GRAPH=SRC/'capture-diagnostic-count1-r10b-sources/source-graph-v10.json'
MANIFEST=SRC/'capture-diagnostic-count1-r10b-manifest.json'
BUILD=SRC/'capture-diagnostic-count1-r10b-sources/package/overlay/root-v10/build-circle-diagnostic-root-v10.ps1'
HELPER=SRC/'capture-diagnostic-count1-r10b-sources/package/overlay/root-v10/Sr0OwnedJobProcess-v15.cs'
ZIP=CACHE/'circle-diagnostic-count1-r10b.zip'
INSTALLER=CACHE/'install-circle-diagnostic-count1-r10b.ps1'
PACKET_ROOT=r'D:\Claude\swiftright\.factory-work\root-tools\circle-admission-r10b-packet'
STAGE_ROOT=r'D:\Claude\swiftright\factory\native\windows\.work\circle-close-r11-r10'
EXE=r'D:\Claude\swiftright\.factory-work\hosts\circle\package\build-bound-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe'
RENDERER=r'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll'

def regular(p: Path, limit: int) -> bytes:
    try: st=p.lstat()
    except OSError as e: raise SystemExit(f'HOLD: missing input {p}: {e}')
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode): raise SystemExit(f'HOLD: unsafe input {p}')
    if st.st_size>limit: raise SystemExit(f'HOLD: input exceeds bound {p}')
    b=p.read_bytes()
    if len(b)!=st.st_size: raise SystemExit(f'HOLD: input changed {p}')
    return b

def sha(b: bytes) -> str: return hashlib.sha256(b).hexdigest()
def psq(s: str) -> str: return "'"+s.replace("'", "''")+"'"

def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--packet-root',default=PACKET_ROOT)
    ap.add_argument('--stage-root',default=STAGE_ROOT)
    ap.add_argument('--external-exe',default=EXE)
    ap.add_argument('--external-renderer',default=RENDERER)
    ap.add_argument('--zip',type=Path,default=ZIP)
    ap.add_argument('--installer',type=Path,default=INSTALLER)
    ap.add_argument('--manifest',type=Path,default=MANIFEST)
    ap.add_argument('--source-graph',type=Path,default=GRAPH)
    ap.add_argument('--build-script',type=Path,default=BUILD)
    ap.add_argument('--helper',type=Path,default=HELPER)
    a=ap.parse_args()
    files=[
      ('circle-diagnostic-count1-r10b.zip',a.zip,MAX_EMBED),
      ('capture-diagnostic-count1-r10b-manifest.json',a.manifest,MAX_EMBED),
      ('source-graph-v10.json',a.source_graph,MAX_EMBED),
      ('install-circle-diagnostic-count1-r10b.ps1',a.installer,MAX_EMBED),
      ('build-circle-diagnostic-root-v10.ps1',a.build_script,MAX_EMBED),
      ('Sr0OwnedJobProcess-v15.cs',a.helper,MAX_EMBED),
    ]
    payload=[]; total=0
    for name,path,lim in files:
        b=regular(path.resolve(),lim); total+=len(b)
        if total>MAX_EMBED: raise SystemExit('HOLD: embedded admission packet exceeds 2 MiB')
        payload.append({'name':name,'bytes':len(b),'sha256':sha(b),'base64':base64.b64encode(b).decode('ascii')})
    graph=json.loads(regular(a.source_graph.resolve(),MAX_EMBED).decode('utf-8'))
    manifest=json.loads(regular(a.manifest.resolve(),MAX_EMBED).decode('utf-8'))
    if graph.get('kind')!='factory-circle-incremental-diagnostic-source-graph-v10': raise SystemExit('HOLD: graph kind')
    if manifest.get('kind')!='factory-circle-incremental-diagnostic-stage-v10' or manifest.get('status')!='SOURCE_ONLY': raise SystemExit('HOLD: manifest kind/status')
    if graph.get('exeRef',{}).get('path')!=a.external_exe or graph.get('rendererRef',{}).get('path')!=a.external_renderer: raise SystemExit('HOLD: external binary path differs from measured graph')
    if manifest.get('stageRoot')!=a.stage_root: raise SystemExit('HOLD: stage root differs from measured manifest')
    by={x['name']:x for x in payload}
    # Keep script payload as data-only records; emitted PS does all Windows writes/hash checks.
    records='@(' + ','.join("[pscustomobject]@{Name="+psq(x['name'])+";Sha256="+psq(x['sha256'])+";Bytes="+str(x['bytes'])+";Base64="+psq(x['base64'])+"}" for x in payload) + ')'
    out=f'''# Circle diagnostic r10b source admission entry; source-only until original installer returns.
[CmdletBinding()]
param(
 [string]$PacketRoot={psq(a.packet_root)},
 [string]$StageRoot={psq(a.stage_root)},
 [string]$ExternalExePath={psq(a.external_exe)},
 [string]$ExternalRendererPath={psq(a.external_renderer)}
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$ExpectedStageRoot={psq(a.stage_root)};$ExpectedExe={psq(a.external_exe)};$ExpectedRenderer={psq(a.external_renderer)}
if($StageRoot -cne $ExpectedStageRoot){{throw 'stage root must equal measured manifest root'}}
if($ExternalExePath -cne $ExpectedExe -or $ExternalRendererPath -cne $ExpectedRenderer){{throw 'external binary paths must equal measured graph paths'}}
$entries={records}
if($entries.Count -ne 6 -or (($entries|Measure-Object -Property Bytes -Sum).Sum -gt 2097152)){{throw 'embedded admission file bounds'}}
function Hash-Bounded([string]$Path,[long]$Limit=2097152){{
 $i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($i.PSIsContainer -or (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $i.Length -gt $Limit){{throw "bounded regular file required: $Path"}}
 $s=[IO.File]::OpenRead($i.FullName);$h=[Security.Cryptography.SHA256]::Create();$buf=New-Object byte[] 65536;$n=[long]0
 try{{while(($r=$s.Read($buf,0,$buf.Length))-gt 0){{$n+=$r;if($n -gt $Limit){{throw 'hash bound exceeded'}};[void]$h.TransformBlock($buf,0,$r,$null,0)}};[void]$h.TransformFinalBlock($buf,0,0);$v=([BitConverter]::ToString($h.Hash)).Replace('-','').ToLowerInvariant()}}finally{{$s.Dispose();$h.Dispose()}}
 if($n -ne $i.Length){{throw "file changed during hash: $Path"}};return $v
}}
if(Test-Path -LiteralPath $PacketRoot){{
 $existing=Get-ChildItem -LiteralPath $PacketRoot -Force -ErrorAction Stop
 if(@($existing).Count -ne 0){{throw 'fresh packet root required'}}
}} else {{New-Item -ItemType Directory -Path $PacketRoot -Force:$false|Out-Null}}
foreach($e in $entries){{
 $path=Join-Path $PacketRoot $e.Name
 if(Test-Path -LiteralPath $path){{throw "fresh embedded path collision: $path"}}
 $tmp=$path+'.tmp';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String($e.Base64))
 if((Get-Item -LiteralPath $tmp).Length -ne [int64]$e.Bytes -or (Hash-Bounded $tmp) -cne $e.Sha256){{throw "embedded hash mismatch: $($e.Name)"}}
 [IO.File]::Move($tmp,$path)
}}
$zip=Join-Path $PacketRoot 'circle-diagnostic-count1-r10b.zip';$manifest=Join-Path $PacketRoot 'capture-diagnostic-count1-r10b-manifest.json';$graph=Join-Path $PacketRoot 'source-graph-v10.json';$installer=Join-Path $PacketRoot 'install-circle-diagnostic-count1-r10b.ps1';$build=Join-Path $PacketRoot 'build-circle-diagnostic-root-v10.ps1';$helper=Join-Path $PacketRoot 'Sr0OwnedJobProcess-v15.cs'
& $installer -PackageZip $zip -PackageZipSha256 (Hash-Bounded $zip 67108864) -StageManifest $manifest -StageManifestSha256 (Hash-Bounded $manifest) -SourceGraph $graph -SourceGraphSha256 (Hash-Bounded $graph) -BuildScriptPath $build -BuildScriptSha256 (Hash-Bounded $build) -HelperPath $helper -HelperSha256 (Hash-Bounded $helper) -ExternalExePath $ExternalExePath -ExternalRendererPath $ExternalRendererPath -StageRoot $StageRoot
'''
    outp=a.output.resolve()
    if outp.exists() or outp.is_symlink(): raise SystemExit(f'HOLD: output exists {outp}')
    outp.parent.mkdir(parents=True,exist_ok=True); outp.write_text(out,encoding='utf-8',newline='\n')
    print(json.dumps({'status':'SOURCE_ONLY_ENTRY_READY','output':str(outp),'sha256':sha(out.encode()),'embeddedBytes':total,'embeddedFiles':[{'name':x['name'],'bytes':x['bytes'],'sha256':x['sha256']} for x in payload],'packetRoot':a.packet_root,'stageRoot':a.stage_root,'externalExe':a.external_exe,'externalRenderer':a.external_renderer},indent=2))
    return 0
if __name__=='__main__': raise SystemExit(main())
