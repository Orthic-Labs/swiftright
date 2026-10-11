"""Mutate complete actual Clang streams, preserving all other top-level nodes."""
import gzip,io,json
from ast_reader import translation_nodes

def rewrite_ast(raw,select,mutate):
 output=io.BytesIO();count=0
 with gzip.GzipFile(fileobj=output,mode='wb',mtime=0) as compressed:
  compressed.write(b'{"id":"bounded-control-tu","kind":"TranslationUnitDecl","loc":{},"range":{"begin":{},"end":{}},"inner":[');first=True
  for node in translation_nodes(raw):
   replacement=[node]
   if select(node):count+=1;replacement=mutate(node)
   for item in replacement:
    if not first:compressed.write(b',')
    compressed.write(json.dumps(item,separators=(',',':')).encode());first=False
  compressed.write(b']}')
 if count!=1:raise ValueError('raw AST control selector cardinality '+str(count))
 return output.getvalue()
