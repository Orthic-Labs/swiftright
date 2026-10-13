import subprocess, re, sys, math
from fractions import Fraction
def model(x,s):
    pl=1.0/s
    return math.floor((x+pl*0.5)/pl)
def run(mode,path,scale,maxpx,vert=False,start=0):
    sc=Fraction(scale)
    rows=[(n,float((Fraction(n)+Fraction(1,2))/sc)) for n in range(start,start+maxpx)]
    W=int(float((start+maxpx)/sc))+40
    cmd=["./probe","--mode",mode,"--path",path,"--w",str(W),"--scale",scale]+(["--vert"] if vert else [])
    out=subprocess.run(cmd,input="0 4\n"+"".join(f"{a!r} 4\n" for n,a in rows),capture_output=True,text=True).stdout.splitlines()[1:]
    bad=0;U=0
    for (n,a),l in zip(rows,out):
        m=re.match(r"(\S+) (\S+) L=(-?\d+)",l); L=int(m[3]); U+= L>n
        if model(a,float(sc))!=L: bad+=1
    return bad,len(rows),U
cfgs=[("hosting","hstack","2.5",800),("hosting","hstack","3",400),("renderer","padding","2.5",800),("renderer","center","2.5",800),("renderer","overlay","3",400),
      ("renderer","hstack","1.75",400),("renderer","hstack","2.25",400),("renderer","hstack","3.5",400),("renderer","hstack","0.75",300),("renderer","hstack","7",400),("renderer","hstack","2.5",3000),
      ("renderer","hstack","2.5",800,True),("hosting","shape","1.25",400),("renderer","hstack","1.1",400),("renderer","hstack","2.75",500),("renderer","hstack","6",400)]
for c in cfgs:
    vert = len(c)>4
    b,t,u=run(c[0],c[1],c[2],c[3],vert)
    print(c[:4],"vert" if vert else "", f"mismatch {b}/{t} (rounded-up {u})")
