"""Read complete top-level Clang JSON nodes without loading full translation units."""
import gzip,json,re
from pathlib import Path

def translation_nodes(raw):
    import io
    stream=gzip.open(io.BytesIO(raw),'rt',encoding='utf-8') if isinstance(raw,bytes) else gzip.open(Path(raw),'rt',encoding='utf-8')
    def pairs(items):
        result={}
        for key,value in items:
            if key in result or key=='_physicalFile':raise ValueError('AST duplicate/reserved field')
            result[key]=value
        return result
    with stream:
        buf=''
        while True:
            chunk=stream.read(1024*1024)
            if not chunk:raise ValueError('AST root header missing/truncated')
            buf+=chunk
            match=re.search(r'"inner"\s*:\s*\[',buf)
            if match:
                header=json.loads(buf[:match.start()]+'"inner": []}', object_pairs_hook=pairs)
                if set(header)!={'id','kind','loc','range','inner'} or header.get('kind')!='TranslationUnitDecl' or header.get('loc')!={} or header.get('range')!={'begin':{},'end':{}}:raise ValueError('AST translation root identity')
                buf=buf[match.end():];break
            if len(buf)>4*1024*1024: raise ValueError('AST root inner missing')
        decoder=json.JSONDecoder(object_pairs_hook=pairs);first=True
        while True:
            buf=buf.lstrip()
            if not buf:
                buf=stream.read(1024*1024)
                if not buf:raise ValueError('AST truncated root')
                buf=buf.lstrip()
            if not first and not buf.startswith(']'):
                if not buf.startswith(','):raise ValueError('AST missing root child comma')
                buf=buf[1:].lstrip();first=True
                if buf.startswith(']'):raise ValueError('AST trailing root child comma')
            if buf.startswith(']'):
                rest=buf[1:]+stream.read()
                if not re.fullmatch(r'\s*}\s*',rest): raise ValueError('AST trailing data')
                return
            try:
                node,end=decoder.raw_decode(buf)
            except json.JSONDecodeError:
                chunk=stream.read(1024*1024)
                if not chunk: raise ValueError('AST truncated or malformed')
                buf+=chunk;continue
            if not isinstance(node,dict) or 'kind' not in node:raise ValueError('AST root child malformed')
            first=False
            yield node
            buf=buf[end:]

# Location files are elided by Clang JSON's location printer. Only genuine
# physical location dictionaries update printer state; includedFrom never does.
def located_nodes(nodes):
    last_file=None
    def visit(value,parent=()):
        nonlocal last_file
        if isinstance(value,dict):
            is_node='id' in value and 'kind' in value and ('loc' in value or 'range' in value)
            if is_node:
                ancestry=parent
                parent=parent+((value.get('kind'),value.get('name'),value.get('id')),)
            for key,child in value.items():
                if key=='includedFrom':continue
                if isinstance(child,dict) and 'offset' in child:
                    if 'file' in child:last_file=child['file']
                    child['_physicalFile']=last_file
                yield from visit(child,parent)
            if is_node:yield value,ancestry
        elif isinstance(value,list):
            for child in value:yield from visit(child,parent)
    for node in nodes:yield from visit(node)
