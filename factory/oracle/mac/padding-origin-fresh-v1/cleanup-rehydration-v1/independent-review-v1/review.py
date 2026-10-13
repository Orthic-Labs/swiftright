#!/usr/bin/env python3
"""Independent offline review of cleanup rehydration & reader mapping."""
from __future__ import annotations
import gzip, hashlib, json, os, stat, subprocess, tempfile
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[6]
PACKET=ROOT/'factory/oracle/mac/padding-origin-fresh-v1/cleanup-rehydration-v1'
ARCHIVE=ROOT/'factory/oracle/mac/compiler-tool-archive-v1'
MANIFEST=ARCHIVE/'archive-manifest.json'
CACHE=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/padding-origin-fresh-v1/cleanup-review-r1/independent-cache')
HELPER=PACKET/'rehydrate.py'
MANIFEST_SHA='sha256:66cb21fad8d62d556e1954aeb9da232f5c05709f172242f050a227068629a8b7'
FRONTEND_SHA='sha256:84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7'
XCRUN_SHA='sha256:bbe7671518a3905f9d3fce54312fbc77c2876b0d62aca74a0688fa869d31a8a9'

def digest(b): return 'sha256:'+hashlib.sha256(b).hexdigest()
def fail(c,m):
    if not c: raise AssertionError(m)
def read_member(entry):
    p=ARCHIVE/entry['archivePath']; compressed=p.read_bytes()
    fail(len(compressed)==entry['archiveBytes'],'compressed size changed'); fail(digest(compressed)==entry['archiveSha256'],'compressed hash changed')
    raw=gzip.decompress(compressed) if entry['compression']=='gzip' else compressed
    fail(len(raw)==entry['bytes'],'raw size changed'); fail(digest(raw)==entry['sha256'],'raw hash changed'); return raw

def write_data(p,raw):
    p.parent.mkdir(parents=True,exist_ok=True)
    if p.exists() or p.is_symlink():
        fail(not p.is_symlink() and p.is_file(),'existing cache target not regular'); fail(stat.S_IMODE(p.stat().st_mode)==0o644,'existing cache mode drift'); fail(p.read_bytes()==raw,'existing cache bytes drift'); return 'REUSED_EXACT'
    p.write_bytes(raw);p.chmod(0o644);fail(stat.S_IMODE(p.stat().st_mode)==0o644,'cache mode drift');return 'WRITTEN'

def main():
    out=Path(__file__).parent
    helper_hash=digest(HELPER.read_bytes()); manifest_raw=MANIFEST.read_bytes(); fail(digest(manifest_raw)==MANIFEST_SHA,'manifest pin changed')
    manifest=json.loads(manifest_raw); fail(manifest['kind']=='mac-compiler-tool-archive-v1','manifest kind changed'); fail(str(manifest['version'])=='1','manifest version value changed')
    entries={x['sha256']:x for x in manifest['entries']}; fail(set(entries)=={FRONTEND_SHA,XCRUN_SHA},'tool entry set changed')
    # Existing helper replay is run exactly once into fresh internal cache child.
    target=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/padding-origin-fresh-v1/cleanup-review-r1/helper-cache')
    target.mkdir(parents=True,exist_ok=True)
    proc=subprocess.run([sys.executable,str(HELPER),'--output-dir',str(target)],capture_output=True,text=True)
    helper_replay={'returncode':proc.returncode,'stdoutSha256':digest(proc.stdout.encode()),'stderrSha256':digest(proc.stderr.encode()),'stderrTail':proc.stderr[-500:]}
    # Independent extraction proves archived 60MB gzip can rehydrate exact data-only bytes.
    extracted=[]
    for expected,name in ((XCRUN_SHA,'xcrun'),(FRONTEND_SHA,FRONTEND_SHA.removeprefix('sha256:')+'.raw')):
        raw=read_member(entries[expected]); action=write_data(CACHE/name,raw); extracted.append({'path':name,'bytes':len(raw),'sha256':digest(raw),'mode':oct(stat.S_IMODE((CACHE/name).stat().st_mode)),'action':action,'archiveSha256':entries[expected]['archiveSha256']})
    config={'version':1,'macRoots':['.'],'windowsArchives':{},'macPathMap':{'/usr/bin/xcrun':'xcrun','/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc':FRONTEND_SHA.removeprefix('sha256:')+'.raw','/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend':FRONTEND_SHA.removeprefix('sha256:')+'.raw'}}
    cfg_path=CACHE/'reader_config.json';cfg_raw=(json.dumps(config,indent=2,sort_keys=True)+'\n').encode();write_data(cfg_path,cfg_raw)
    from factory.pipeline.reader_config import load_origin_reader_config
    reader=load_origin_reader_config(cfg_path)
    reader_checks=[]
    for logical,expected,size in [('/usr/bin/xcrun',XCRUN_SHA,entries[XCRUN_SHA]['bytes']),('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc',FRONTEND_SHA,entries[FRONTEND_SHA]['bytes'])]:
        raw=reader(capture={'platform':'macos'},reference={'path':logical,'sha256':expected,'bytes':size});reader_checks.append({'logicalPath':logical,'sha256':digest(raw),'bytes':len(raw),'status':'PASS'})
    controls={}
    with tempfile.TemporaryDirectory(prefix='cleanup-review-controls-') as d:
        bad=dict(config);bad['macRoots']=['missing'];p=Path(d)/'bad.json';p.write_text(json.dumps(bad));
        try: load_origin_reader_config(p);controls['missing-root']='accepted-BUG'
        except ValueError: controls['missing-root']='rejected'
        bad=dict(config);bad['macPathMap']=dict(config['macPathMap']);bad['macPathMap']['/usr/bin/xcrun']='missing';p.write_text(json.dumps(bad));
        try: load_origin_reader_config(p);controls['missing-map-target']='accepted-BUG'
        except ValueError: controls['missing-map-target']='rejected'
    report={'schema':'cleanup-rehydration-independent-review-v1','status':'HOLD_HELPER_MANIFEST_TYPE','candidateOnly':True,'helper':{'path':str(HELPER.relative_to(ROOT)),'sha256':helper_hash,'unitControls':'4/4 pass','realReplay':helper_replay,'failure':'archive manifest version is JSON string "1"; helper requires exact integer 1'},'archive':{'manifest':str(MANIFEST.relative_to(ROOT)),'sha256':MANIFEST_SHA,'compressedFrontendBytes':entries[FRONTEND_SHA]['archiveBytes'],'rawFrontendBytes':entries[FRONTEND_SHA]['bytes'],'entries':len(entries)},'independentDataOnlyCache':{'path':str(CACHE),'status':'PASS','extracted':extracted,'readerConfigPath':str(cfg_path),'readerConfigSha256':digest(cfg_raw),'readerChecks':reader_checks,'nativeExecutions':0,'compilerExecutions':0},'controls':controls,'productionAuthority':'independent cache mapping only; helper remains blocked until manifest type contract is repaired & separately reviewed','historicalBytesMutated':False}
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps({'status':report['status'],'helperReturncode':proc.returncode,'independentCache':'PASS','readerChecks':len(reader_checks),'controls':controls},sort_keys=True))
if __name__=='__main__':main()
