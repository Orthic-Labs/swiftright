"""Lexical owner scopes only; external declaration universe is outside this proof."""
from lexical_model_v2 import code_lines,fields,NOMINAL,require
import re

def scopes(source,module):
    records=[];stack=[];depth=0;condition=[];attributes=[];bodies=[]
    for line,(original,structural) in enumerate(zip(source.splitlines(),code_lines(source)),1):
        text=structural.strip();literal=original.strip()
        if text.startswith('#if '):condition.append({'ifLine':line,'branchLine':line,'kind':'if'})
        elif text.startswith('#elseif ') or text=='#else':
            require(condition,'external conditional branch balance');condition[-1]={'ifLine':condition[-1]['ifLine'],'branchLine':line,'kind':'elseif' if text.startswith('#elseif ') else 'else'}
        elif text=='#endif':require(condition,'external conditional end balance');condition.pop()
        declaration=fields(structural);scope_lines=[s['line'] for s in stack]
        if literal.startswith('@') and declaration is None:attributes.append({'line':line,'text':literal,'scopeLines':scope_lines,'conditions':[dict(c) for c in condition]})
        record=None
        if declaration:
            own=[{'line':a['line'],'text':a['text']} for a in attributes if a['scopeLines']==scope_lines and a['conditions']==condition]
            record={**declaration,'module':module,'line':line,'text':literal,'scopeLines':scope_lines,'attributes':own,'conditions':[dict(c) for c in condition],'insideFunction':any(b['function'] for b in bodies)}
            attributes=[]
        elif literal and not literal.startswith('@') and not literal.startswith('//'):attributes=[]
        opened=False
        for token in re.findall(r'[{}]',structural):
            if token=='{':
                depth+=1;function=False
                if record and not opened:
                    opened=True
                    if record['kind'] in NOMINAL|{'extension'}:
                        owner={**record,'bodyDepth':depth,'endLine':None,'path':[s['name'] for s in stack if s['kind'] in NOMINAL]+[record['name']]};stack.append(owner);records.append(owner)
                    else:function=record['kind'] in {'func','init','deinit','subscript','var','let'}
                bodies.append({'depth':depth,'function':function})
            else:
                require(depth>0,'external lexical brace balance')
                if stack and stack[-1]['bodyDepth']==depth:stack.pop()['endLine']=line
                if bodies and bodies[-1]['depth']==depth:bodies.pop()
                depth-=1
    require(depth==0 and not stack and not condition,'external complete lexical owner balance')
    return records
