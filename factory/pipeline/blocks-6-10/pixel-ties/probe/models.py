import math
from fractions import Fraction
def load():
    ds=[]
    for s in ['3','2.5','1.25','5','1.5']:
        obs=open(f'g_{s}.txt').read().strip(); sc=Fraction(s)
        pts=[(float((Fraction(n)+Fraction(1,2))/sc), n, obs[n]) for n in range(len(obs))]
        ds.append((s,float(sc),pts))
    ints=[(float(p), (5*p-1)//2, 'd' if (p==1 or 9<=p<=25 or 129<=p<=409) else 'U') for p in range(1,800,2)]
    ds.append(('ints2.5',2.5,ints))
    return ds
def fma(a,b,c):
    return float(Fraction(a)*Fraction(b)+Fraction(c))
models = {
 'floor(fl(x*s)+.5)': lambda x,s: math.floor(x*s+0.5),
 'floor(fma(x,s,.5))': lambda x,s: math.floor(fma(x,s,0.5)),
 'rint(x*s)': lambda x,s: round(x*s),
 'floor(x*s+.49999999999999994)': lambda x,s: math.floor(x*s+0.49999999999999994),
 'ceil(fma(x,s,-.5))': lambda x,s: math.ceil(fma(x,s,-0.5)),
 'floor(fl(x/(1/s))+.5)': lambda x,s: math.floor(x/(1/s)+0.5),
 'floor(fma(x,1/(1/s),.5))': lambda x,s: math.floor(fma(x,1/(1/s),0.5)),
 'floor(x*s+.5) w/ (x/pl)': lambda x,s: math.floor(fma(x,1.0/(1.0/s),0.5)),
}
if __name__=='__main__':
    ds=load()
    for name,m in models.items():
        row=[]
        for s,sc,pts in ds:
            bad=sum(1 for x,n,c in pts if ((m(x,sc)>n)==(c=='U'))==False)
            row.append(f"{s}:{bad}/{len(pts)}")
        print(f"{name:34s}", " ".join(row))
