from pathlib import Path
import json,hashlib,re
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/native/windows/native-host-validity-fix-v1';O=P/'independent-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(P/'root-stage-manifest.json')=='f1f03d5dfea9938d6cd360713481b9d3f80fcee48fbfb13b2f4e3ef905dec679'
m=json.loads((P/'root-stage-manifest.json').read_text())
for row in m['files']:
 p=R/row['path'];assert sha(p)==row.get('hash',row.get('sha256')).removeprefix('sha256:');assert p.stat().st_size==row['bytes']
new=(P/'capture-repeat.ps1').read_text();parent=(P/'parent-capture-repeat.ps1').read_text()
assert parent==(R/'factory/native/windows/padding-settled-capture-v4/capture-repeat.ps1').read_text()
guard="  if(-not $validHost){throw 'Owned host output failed original validity predicate'}\n"
assert new.count(guard)==1 and new.replace(guard,'')==parent
assert sha(P/'capture-repeat.ps1')=='4a62d93c69e7499b753d30c36f18c68b77d83808d3ab9d4179678bdceae87772'
assignment=next(line for line in new.splitlines() if line.startswith('  $validHost='))
assert new.index(assignment)<new.index(guard)<new.index('  $records +=')<new.index(' } catch {$primaryError=$_} finally {')
controls=(P/'test-host-output.ps1').read_text()
for token in ['AssignmentStatementAst','IfStatementAst','$assignments.Count -ne 1','[scriptblock]::Create($assignments[0].Extent.Text', 'try{. $production}', '$p=[pscustomobject]@{ExitCode=0}', '$p=[pscustomobject]@{ExitCode=1}']:assert token in controls
rows=[]
for f in json.loads((P/'fixtures.json').read_text()):
 copy=R/f['path']; original=R/f['originalPath'];assert copy.read_bytes()==original.read_bytes() and sha(copy)==f['sha256'] and copy.stat().st_size==f['bytes']
 text=copy.read_text(); valid=all(x in text for x in ('FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto','FACTORY_RENDERER_READY','FACTORY_COMMIT')) and not re.search('FACTORY_(RENDER|STARTUP)_ERROR',text)
 assert valid==(f['expected']=='accept');rows.append({'fixture':f['name'],'rawSha256':f['sha256'],'offlinePredicateAccept':valid,'syntheticExitCode':0})
report={'verdict':'CLEAR_MINIMAL_SOURCE_AND_CONTROL_DESIGN','findings':[],'stageRowsVerified':len(m['files']),'exactDelta':'One fail-closed throw immediately after unchanged validHost predicate, before accepted record; every other runner byte equals frozen v4. Existing catch/finally preserves original error, raw sealing, owned cleanup &lock protocol. No timeout or native behavior edits.','fixtures':rows,'controls':'AST extracts exactly one actual production assignment plus immediate throw guard, executes combined production script against actual baseline/run03/run16 bytes at permissive synthetic exit0; nonzero-exit fixture independently rejects. Windows PS execution not performed by reviewer.','historicalScope':'Actual runs03/16 exit codes not inferred; permissive exit0 is deliberate control assumption. Historical raw errors remain unchanged.','reviewExecution':'Offline Python source/hash/predicate replay only; zero native/compiler/remote actions','sourcePins':{str(p.relative_to(R)):sha(p) for p in [P/'root-stage-manifest.json',P/'capture-repeat.ps1',P/'parent-capture-repeat.ps1',P/'test-host-output.ps1',P/'fixtures.json']}}
(O/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(sha(O/'report.json'))
