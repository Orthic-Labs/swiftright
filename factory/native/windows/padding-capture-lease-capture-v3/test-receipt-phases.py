from pathlib import Path
import re,json
D=Path(__file__).resolve().parent
s=(D/'capture-repeat.ps1').read_text()
def check(t):
 phases=re.findall(r"Write-FactoryDiagnosticJson \(Join-Path \$dir '([^']*ordering[^']*)'\) \$ordering",t)
 assert phases==['capture-ordering-worker-ready.json','capture-ordering-pixels-start.json','capture-ordering-pixels-complete.json','capture-ordering-close-pending.json','capture-ordering.json']
 assert t.count("'declared-worker-inventory.json') $inventory")==1
 assert t.count("'owned-worker-inventory.json') $inventory")==2
 assert t.index("'declared-worker-inventory.json') $inventory")<t.index('$p=[Diagnostics.Process]::Start')
 assert "if(-not $workerAttempted){try{Write-FactoryDiagnosticJson (Join-Path $dir 'owned-worker-inventory.json') $inventory" in t
check(s)
faults=[s.replace('capture-ordering-pixels-start.json','capture-ordering.json'),s.replace('declared-worker-inventory.json','owned-worker-inventory.json'),s.replace('if(-not $workerAttempted){try{Write-FactoryDiagnosticJson','if($workerAttempted){try{Write-FactoryDiagnosticJson')]
for mutated in faults:
 assert mutated!=s
 try:check(mutated)
 except AssertionError:continue
 raise AssertionError('Coherent raw source fault accepted')
print(json.dumps({'baseline':'accepted','changedSourceFaultsRejected':3,'windowsWriterControls':'prepared/unrun'}))
