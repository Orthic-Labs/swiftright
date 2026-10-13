#!/usr/bin/env python3
"""Read-only cleanup inventory. Never removes, copies or runs native bytes."""
from pathlib import Path
import os,json,hashlib,subprocess,datetime
ROOT=Path('/Volumes/D/claude/swiftright');CACHE=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory');OUT=ROOT/'factory/pipeline/workspace-cleanup-audit-v1'
def sha(p):return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def beneath(p,r):
 try:Path(p).relative_to(r);return True
 except ValueError:return False
def files(p):
 for base,dirs,names in os.walk(p):
  dirs[:]=[d for d in dirs if d!='.git']
  for name in names:
   q=Path(base)/name
   if q.is_file() and not q.is_symlink():yield q
names=subprocess.check_output(['rg','--files','factory'],cwd=ROOT,text=True).splitlines()
archive_index={};archive_manifests=[];reader_configs=[];dependencies=[]
for name in names:
 p=ROOT/name
 if p.suffix!='.json':continue
 if ('archive-map' in p.name or 'archive-manifest' in p.name):
  try:j=json.loads(p.read_text())
  except Exception:continue
  archive_manifests.append({'path':str(p),'sha256':sha(p)})
  for row in j.get('files',[]):
   if isinstance(row,dict) and isinstance(row.get('path'),str) and isinstance(row.get('sha256'),str):
    target=p.parent/row['path']
    if target.is_file():archive_index.setdefault(row['sha256'],[]).append(target)
 if 'config' in p.name and 'reader' in p.name:
  try:j=json.loads(p.read_text())
  except Exception:continue
  reader_configs.append({'path':str(p),'sha256':sha(p)})
  for key,value in j.get('macPathMap',{}).items():dependencies.append({'config':str(p),'logical':key,'physical':value})
  for value in j.get('macRoots',[]):dependencies.append({'config':str(p),'root':value})
# Existing explicit origin maps also bind immutable archived targets by content.
for dep in dependencies:
 if 'physical' in dep:
  q=Path(dep['physical'])
  if q.is_file() and q.stat().st_size<10_000_000:archive_index.setdefault(sha(q),[]).append(q)
# Canonical protected runtime source is retained, used only as byte-match anchor.
for p in (ROOT/'probes/sr0-s/fresh-runtime').rglob('*.swift'):
 if '.build' not in p.parts:archive_index.setdefault(sha(p),[]).append(p)
for name in names:
 p=ROOT/name
 if name.startswith('factory/runtime-additions/') and p.is_file() and p.stat().st_size<10_000_000:archive_index.setdefault(sha(p),[]).append(p)
verified={}
def archive_matches(q):
 h=sha(q);matches=[]
 for p in archive_index.get(h,[]):
  if beneath(p,CACHE):continue
  if str(p) not in verified:verified[str(p)]=sha(p)
  if verified[str(p)]==h:matches.append(str(p))
 return {'path':str(q),'sha256':h,'bytes':q.stat().st_size,'archivedCopies':sorted(set(matches))}
ps=subprocess.check_output(['ps','-axo','pid=,ppid=,command='],text=True)
active=[s.strip() for s in ps.splitlines() if str(CACHE) in s and 'audit.py' not in s]
try:
 result=subprocess.run(['/usr/sbin/lsof','-nP','-Fpn'],capture_output=True,text=True,timeout=30)
 openfiles=[s[1:] for s in result.stdout.splitlines() if s.startswith('n'+str(CACHE))];lsof={'exitCode':result.returncode,'paths':openfiles}
except subprocess.TimeoutExpired:lsof={'status':'TIMEOUT','paths':[]}
# Generated compiler caches are proposed separately from Products, executable evidence & logs.
cache_names={'CompilationCache.noindex','ModuleCache.noindex','SDKExplicitPrecompiledModules','SDKStatCaches.noindex','PCH'}
runtime=CACHE/'sr1/runtime-additions';candidates=[]
for base,dirs,_ in os.walk(runtime):
 dirs[:]=[d for d in dirs if d!='.git']
 for d in list(dirs):
  if d not in cache_names:continue
  p=Path(base)/d;dirs.remove(d);items=list(files(p));blocked=[x for x in dependencies if beneath(x.get('physical',x.get('root','')),p)]
  opens=[x for x in lsof['paths'] if beneath(x,p)];proc=[x for x in active if str(p) in x or str(runtime) in x]
  candidates.append({'path':str(p),'allocatedBytes':sum(q.stat().st_blocks*512 for q in items),'fileCount':len(items),'status':'GENERATED_CACHE_CANDIDATE' if not blocked and not opens and not proc and lsof.get('exitCode') in (0,1) else 'HOLD_ACTIVE_OR_DEPENDENT','readerDependencies':blocked,'openFiles':opens,'processes':proc,'recovery':'Regenerate compiler cache from retained source/toolchain; byte-identical historical extraction is not claimed. Products/source/logs remain outside this exact deletion path.'})
# Whole directory cleanup requires byte-exact archives for every file, not prose receipt alone.
roots=[p for p in CACHE.iterdir() if p.is_dir() and p.name not in ('padding-origin-fresh-v1','sr1')]+[p for p in (CACHE/'sr1').iterdir() if p.is_dir() and p.name not in ('padding-origin-fresh-v1','runtime-additions')]
small=[]
for p in roots:
 items=list(files(p));allocated=sum(q.stat().st_blocks*512 for q in items)
 if allocated>25_000_000:
  small.append({'path':str(p),'allocatedBytesExcludingGit':allocated,'status':'HOLD_NOT_FULLY_ARCHIVED','reason':'Large build/control/source tree requires own complete byte archive & terminal lineage inventory; no whole-tree removal justified here.'});continue
 rows=[archive_matches(q) for q in items];missing=[r for r in rows if not r['archivedCopies']]
 deps=[x for x in dependencies if beneath(x.get('physical',x.get('root','')),p)];opens=[x for x in lsof['paths'] if beneath(x,p)];proc=[x for x in active if str(p) in x]
 gitdirs=[str(Path(b)/'.git') for b,dirs,_ in os.walk(p) if '.git' in dirs]
 symlinks=[str(Path(b)/name) for b,ds,fs in os.walk(p) for name in ds+fs if (Path(b)/name).is_symlink()]
 status='BYTE_ARCHIVED_CANDIDATE' if not gitdirs and not symlinks and rows and not missing and not deps and not opens and not proc and lsof.get('exitCode') in (0,1) else 'HOLD_NOT_ARCHIVED_OR_ACTIVE'
 small.append({'path':str(p),'allocatedBytesExcludingGit':allocated,'status':status,'files':rows,'unarchivedFileCount':len(missing),'gitRepositoriesHeld':gitdirs,'symlinksHeld':symlinks,'readerDependencies':deps,'openFiles':opens,'processes':proc})
# Bind specific runtime evidence preservation blockers & final canonical anchor.
anchors=[ROOT/'factory/runtime-additions/RESULT.md',ROOT/'factory/runtime-additions/font-storage/root-integration.json',ROOT/'factory/runtime-additions/font-storage/root-integration.stdout',ROOT/'factory/runtime-additions/scroll/README.md']
log=runtime/'scroll/fresh-runtime-db29/probes/sr0-s/fresh-runtime/out/swift-test-scroll-db29.txt'
if log.is_file():logrecord=archive_matches(log)
else:logrecord={'path':str(log),'status':'MISSING'}
report={'createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'source/read-only cleanup inventory; no deletion/native/compiler/remote/Git execution','activeProcessSnapshot':active,'openFileSnapshot':lsof,'generatedCacheCandidates':candidates,'generatedCacheCandidateBytes':sum(c['allocatedBytes'] for c in candidates if c['status']=='GENERATED_CACHE_CANDIDATE'),'nativeControlDirectoryInventory':small,'readerConfigs':reader_configs,'archiveManifestPins':archive_manifests,'canonicalAnchors':[{'path':str(p),'sha256':sha(p)} for p in anchors],'runtimeWholeTreeStatus':'HOLD: source, Products, historical logs & copied repositories have not been fully byte-archived; source patches/final175 receipt do not retroactively archive intermediate raw failures.','specificHistoricalLog':logrecord,'runtimeRoot':str(runtime),'separateOwnerExcluded':[str(CACHE/'padding-origin-fresh-v1'),str(CACHE/'sr1/padding-origin-fresh-v1')],'executionOrder':'Root rechecks process/open-file quiescence immediately before any exact-path cleanup. Eligible byte-archived directories & generated cache-only paths may be retired; all HOLD directories/source/Products/logs stay. Fresh Mac20 cache belongs separate cleanup-rehydration owner.'}
(OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps({'generatedCachePaths':len(candidates),'candidateGiB':report['generatedCacheCandidateBytes']/1024**3,'byteArchivedDirectories':[x['path'] for x in small if x['status']=='BYTE_ARCHIVED_CANDIDATE'],'historicalLogArchivedCopies':logrecord.get('archivedCopies',[]),'lsof':lsof.get('exitCode',lsof.get('status'))}))
