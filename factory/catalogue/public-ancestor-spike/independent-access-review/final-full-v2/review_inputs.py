"""Independent source restrictions & branch identities for final bounded review."""
import re

def attributes(text):
 result=[];cursor=0
 while cursor<len(text):
  hit=re.search(r'@\w+(?:\.\w+)*',text[cursor:])
  if not hit:break
  start=cursor+hit.start();end=cursor+hit.end()
  if end<len(text) and text[end]=='(':
   depth=0;quoted=False;escaped=False
   while end<len(text):
    char=text[end]
    if quoted:
     if escaped:escaped=False
     elif char=='\\':escaped=True
     elif char=='"':quoted=False
    elif char=='"':quoted=True
    elif char=='(':depth+=1
    elif char==')':
     depth-=1
     if depth==0:end+=1;break
    end+=1
  result.append(text[start:end]);cursor=end
 return result

def category(text):
 if re.fullmatch(r'@_documentation\(visibility: (private|internal)\)',text):return 'documentation-hidden'
 if re.fullmatch(r'@_?available\((?:macOS|\*), unavailable(?:,.*)?\)',text):return 'macOS-unavailable'
 if text.startswith('@_spi('):return 'spi'
 return None

def branches(lines):
 stack=[];result={}
 for number,text in enumerate(lines,1):
  text=text.strip()
  if text.startswith('#if '):stack.append(number)
  elif text.startswith('#elseif ') or text=='#else':stack[-1]=number
  elif text=='#endif':stack.pop()
  result[number]=stack[:]
 assert not stack
 return result

def own_attributes(lines,model,line,floor=0):
 texts=[(line,lines[line-1])];cursor=line-1
 while cursor>floor and lines[cursor-1].strip().startswith('@') and model[cursor]['scopes']==model[line]['scopes'] and model[cursor]['conditions']==model[line]['conditions']:
  residual=lines[cursor-1]
  for text in attributes(residual):residual=residual.replace(text,'',1)
  if residual.strip():break
  texts.insert(0,(cursor,lines[cursor-1]));cursor-=1
 return [{'line':number,'text':text} for number,value in texts for text in attributes(value)]
