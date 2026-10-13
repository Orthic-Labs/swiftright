"""Source-only admission for execute-r5; no Windows/native/lock effects."""
from pathlib import Path
import hashlib,re
HERE=Path(__file__).parent
BASE=HERE.parent/'execute-r3'
FILES=('coordinator-r5.ps1','interactive-task-r5.ps1','dispatch-r5.ps1','capture-repeat-r5.ps1')
OLD=('coordinator-r3.ps1','interactive-task-r3.ps1','dispatch-r3.ps1','capture-repeat-r3.ps1')
GUARD="""$guardPath=Join-Path $overlayRoot 'integration-prefixed-ids-r1.ps1'\nif((Get-FileHash -LiteralPath $guardPath).Hash.ToLowerInvariant() -cne 'd4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904'){throw 'Prefixed integration guard drift'}\n. $guardPath"""

def norm(s, new):
    s=s.replace('coordinator-r5.ps1','coordinator-r3.ps1').replace('interactive-task-r5.ps1','interactive-task-r3.ps1').replace('dispatch-r5.ps1','dispatch-r3.ps1').replace('capture-repeat-r5.ps1','capture-repeat-r3.ps1')
    target=". (Join-Path $baseRoot 'support\\integration.ps1')" if new == 'capture-repeat-r5.ps1' else ". (Join-Path $here 'support\\integration.ps1')"
    return s.replace(GUARD,target)
def imports(s):
    out={}
    for lib,body in re.findall(r'\[DllImport\("([^"]+)"\)\]\s*public static extern ([^;]+);',s):
        out.setdefault(lib,[]).append(body)
    return out
for new,old in zip(FILES,OLD):
    n=(HERE/new).read_text(); o=(BASE/old).read_text()
    assert norm(n,new)==o, f'behavior drift: {new}'
    assert 'user42.dll' not in n, f'bad user DLL: {new}'
    assert imports(n)==imports(o), f'DllImport ABI drift: {new}'
    for library in ('user32.dll','kernel32.dll','gdi32.dll'):
        assert imports(n).get(library,[]) == imports(o).get(library,[]), f'{library} import ABI drift: {new}'
    if new != 'interactive-task-r5.ps1': assert 'integration-prefixed-ids-r1.ps1' in n and 'd4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904' in n
assert imports((HERE/'capture-repeat-r5.ps1').read_text()).get('user32.dll') == imports((BASE/'capture-repeat-r3.ps1').read_text()).get('user32.dll')
assert not any('user42.dll' in p.read_text() for p in HERE.glob('*.ps1'))
# Exact five-file overlay contract, including prefixed guard.
expected={'coordinator-r5.ps1','interactive-task-r5.ps1','dispatch-r5.ps1','capture-repeat-r5.ps1','integration-prefixed-ids-r1.ps1'}
assert {p.name for p in HERE.glob('*.ps1')} == expected
print('execute-r5 source admission PASS; behavior+DllImport ABI exact vs execute-r3; overlay five files exact; effects=0')
