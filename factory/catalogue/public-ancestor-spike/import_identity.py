"""Exact raw imported nominal reference joins; process binding belongs to caller."""
import json,re

def require(ok,why):
    if not ok:raise ValueError(why)

def records(raw):
    result=[];stack=[]
    for line in raw.splitlines():
        opened=re.fullmatch(r'(\s*)\{',line)
        if opened:stack.append({'indent':len(opened[1]),'fields':{}});continue
        closed=re.fullmatch(r'(\s*)\},?',line)
        if closed:
            require(stack and stack[-1]['indent']==len(closed[1]),'raw import dictionary nesting')
            record=stack.pop()['fields']
            if 'kind' in record and all(k in record for k in ('name','usr','line','column')):result.append(record)
            continue
        field=re.fullmatch(r'(\s*)key\.(kind|name|usr|line|column|is_implicit|effective_access|filepath): (.*?),?',line)
        if field and stack and stack[-1]['indent']+2==len(field[1]):
            value=field[3].removesuffix(',')
            if value.startswith('"'):value=json.loads(value)
            elif re.fullmatch(r'\d+',value):value=int(value)
            require(field[2] not in stack[-1]['fields'],'duplicate raw import field')
            stack[-1]['fields'][field[2]]=value
    require(not stack,'unterminated raw import dictionary')
    return result

def reference(raw,source,line,column,name,kind):
    require(type(line)==type(column)==int and line>0 and column>0,'import nominal physical position type')
    text=source.splitlines()[line-1]
    require(re.match(r'`?'+re.escape(name)+r'`?(?![\w$])',text[column-1:]) is not None,'import actual nominal token/column')
    matches=[r for r in records(raw) if r['line']==line and r['column']==column]
    require(len(matches)==1,'import nominal raw physical cardinality')
    entity=matches[0]
    require(entity['kind']=='source.lang.swift.ref.'+kind and entity['name']==name and not entity.get('is_implicit'),'import exact nominal reference kind/name')
    require(entity['usr'].startswith(('s:','c:')),'import nominal actual USR family')
    return entity
