"""Source-only SDK lexical declarations & complete conditional branch identities."""
from __future__ import annotations
import re
from functools import lru_cache

ACCESS = {'public','open','internal','package','fileprivate','private'}
NOMINAL = {'struct','enum','class','actor','protocol'}
FAMILIES = NOMINAL | {'extension','func','var','let','init','deinit','subscript','typealias','associatedtype','case','macro','operator','precedencegroup'}
IDENT = r'`[^`]+`|[A-Za-z_$][A-Za-z0-9_$]*'


def require(ok, why):
    if not ok: raise ValueError(why)


def code_lines(source):
    """Mask literals/comments preserving offsets; state survives multiline strings."""
    block, quote, hashes, escaped = 0, None, 0, False
    out=[]
    for original in source.splitlines():
        chars=list(original); i=0
        while i<len(original):
            if block:
                if original.startswith('/*',i): block+=1; chars[i:i+2]='  '; i+=2
                elif original.startswith('*/',i): block-=1; chars[i:i+2]='  '; i+=2
                else:chars[i]=' ';i+=1
                continue
            if quote:
                close=quote+'#'*hashes
                if not escaped and original.startswith(close,i):
                    chars[i:i+len(close)]=' '*len(close);i+=len(close);quote=None;hashes=0;continue
                if escaped:escaped=False
                elif original[i]=='\\' and not hashes:escaped=True
                chars[i]=' ';i+=1;continue
            if original.startswith('//',i):chars[i:]=' '*(len(chars)-i);break
            if original.startswith('/*',i):block=1;chars[i:i+2]='  ';i+=2;continue
            raw=re.match(r'(#+)?("""|")',original[i:])
            if raw:
                hashes=len(raw[1] or '');quote=raw[2];chars[i:i+raw.end()]=' '*raw.end();i+=raw.end();continue
            i+=1
        out.append(''.join(chars))
    require(not block and quote is None,'unterminated SDK comment/string')
    return out


def fields(code):
    masked=list(code); cursor=0
    while cursor<len(code):
        attribute=re.match(r'@[A-Za-z_][A-Za-z0-9_.]*',code[cursor:])
        if not attribute:cursor+=1;continue
        end=cursor+attribute.end()
        if end<len(code) and code[end]=='(':
            level=0
            while end<len(code):
                level+=(code[end]=='(')-(code[end]==')');end+=1
                if level==0:break
        masked[cursor:end]=' '*(end-cursor);cursor=end
    code=''.join(masked)
    hits=list(re.finditer(r'\b('+'|'.join(sorted(FAMILIES,key=len,reverse=True))+r')\b',code))
    for hit in hits:
        kind=hit[1]; tail=code[hit.end():].lstrip()
        if kind=='class' and re.match(r'(?:func|var|subscript)\b',tail):continue
        # Declaration must begin with attributes/modifiers, never expression/return.
        prefix=code[:hit.start()]
        if re.search(r'[={};]|\b(?:return|throw|print)\b',prefix):return None
        access=[m[1] for m in re.finditer(r'\b(public|open|internal|package|fileprivate|private)\b(?!\s*\(set\))',prefix)]
        require(len(access)<=1,'multiple declaration read access modifiers')
        if kind in {'init','deinit','subscript'}:name=kind
        else:
            name_match=re.match(r'('+IDENT+r')',tail)
            if not name_match and kind in {'func','operator'}:name_match=re.match(r'([^\s(]+)',tail)
            if not name_match:return None
            name=name_match[1].strip('`')
            if kind=='extension':
                target=re.match(r'([A-Za-z_$][A-Za-z0-9_$.:]*)',tail);name=target[1].replace('::','.') if target else name
        result={'kind':kind,'name':name,'explicitAccess':access[0] if access else None,'keywordOffset':hit.start()}
        if kind=='extension':
            result['targetSpelling']=target[1]
            result['targetNamespaceQualifiers']=re.findall(r'([A-Za-z_$][A-Za-z0-9_$]*)::',target[1])
            result['name']=re.sub(r'\.([A-Za-z_$][A-Za-z0-9_$]*)::','.',target[1]).replace('::','.')
        return result
    return None


@lru_cache(maxsize=4)
def model(source,module):
    lines=source.splitlines(); code=code_lines(source)
    scopes=[]; all_scopes=[]; declarations=[]; by_line={}; frames={}; conditional=[]; depth=0; body_stack=[]
    attributes=[]
    for number,(original,structural) in enumerate(zip(lines,code),1):
        stripped=structural.strip(); literal=original.strip()
        if stripped.startswith('#if '):
            frame={'ifLine':number,'parentIfLines':[f['ifLine'] for f in conditional],'branches':[{'kind':'if','line':number,'expression':literal[4:]}],'endifLine':None}
            frames[number]=frame;conditional.append(frame)
        elif stripped.startswith('#elseif ') or stripped=='#else':
            require(conditional and conditional[-1]['branches'][-1]['kind']!='else','orphan/late conditional branch')
            conditional[-1]['branches'].append({'kind':'elseif' if stripped.startswith('#elseif ') else 'else','line':number,'expression':literal[8:] if stripped.startswith('#elseif ') else None})
        elif stripped=='#endif':
            require(conditional,'orphan endif');conditional.pop()['endifLine']=number
        branch=[{'ifLine':f['ifLine'],'branchLine':f['branches'][-1]['line'],'kind':f['branches'][-1]['kind']} for f in conditional]
        ancestors=[s['line'] for s in scopes]
        by_line[number]={'text':original,'scopeLines':ancestors,'conditions':branch,'depth':depth,'insideFunction':any(x['role']=='function' for x in body_stack)}
        if literal.startswith('@') and fields(structural) is None:attributes.append({'line':number,'text':literal})
        declaration=fields(structural)
        if declaration:
            own_attributes=attributes if attributes and all(by_line[a['line']]['scopeLines']==ancestors and by_line[a['line']]['conditions']==branch for a in attributes) else []
            record={**declaration,'line':number,'text':literal,'module':module,'scopeLines':ancestors,'conditions':branch,'attributes':list(own_attributes),'insideFunction':by_line[number]['insideFunction']}
            declarations.append(record)
            if record['kind'] in {'case','var','let'} and not re.match(r'\s*(?:if|guard|while|for)\b',structural):
                tail=structural[record['keywordOffset']+len(record['kind']):].strip();level=0;angles=0;start=0;parts=[]
                for position,char in enumerate(tail):
                    level+=(char in '([{')-(char in ')]}')
                    if char=='<':angles+=1
                    elif char=='>' and angles and (position==0 or tail[position-1]!='-'):angles-=1
                    if char==',' and level==angles==0:parts.append(tail[start:position]);start=position+1
                parts.append(tail[start:])
                for extra in parts[1:]:
                    matched=re.match(r'\s*('+IDENT+r')',extra)
                    require(matched is not None,'unparsed compound declaration binding')
                    declarations.append({**record,'name':matched[1].strip('`')})
            attributes=[]
        elif literal and not literal.startswith('@') and not literal.startswith('//'):attributes=[]
        opened=False
        for token in re.findall(r'[{}]',structural):
            if token=='{':
                depth+=1;role='other'
                if declaration and not opened:
                    opened=True
                    if declaration['kind'] in NOMINAL|{'extension'}:
                        scope={**record,'bodyDepth':depth,'endLine':None}
                        scope['path']=[s['name'] for s in scopes if s['kind'] in NOMINAL]+[scope['name']]
                        scopes.append(scope);all_scopes.append(scope);role='type'
                    elif declaration['kind'] in {'func','init','deinit','subscript','var','let'}:role='function'
                body_stack.append({'depth':depth,'role':role})
            else:
                depth-=1;require(depth>=0,'negative SDK lexical brace depth')
                while body_stack and body_stack[-1]['depth']>depth:body_stack.pop()
                while scopes and scopes[-1]['bodyDepth']>depth:scopes.pop()['endLine']=number
    require(not conditional and not scopes and depth==0,'unbalanced SDK lexical/conditional source')
    return {'lines':by_line,'declarations':declarations,'scopes':all_scopes,'frames':frames}
