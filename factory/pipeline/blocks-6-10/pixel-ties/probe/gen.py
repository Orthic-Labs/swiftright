import subprocess, re, sys
from fractions import Fraction
mode, path, scale, maxpx = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
sc = Fraction(scale)
# ties: px = n+.5 -> pt = (n+.5)/scale ; use exact rational then to float
rows=[]
for n in range(0, maxpx):
    pt = (Fraction(n)+Fraction(1,2))/sc
    rows.append((n, float(pt)))
W = int(float(maxpx/float(sc)))+40
out = subprocess.run(["./probe","--mode",mode,"--path",path,"--w",str(W),"--scale",scale], input="0 4\n"+"".join(f"{a!r} 4\n" for n,a in rows), capture_output=True, text=True).stdout
res=[]
for (n,a),line in zip(rows,out.splitlines()[1:]):
    m=re.match(r"(\S+) (\S+) L=(\d+) R=(\d+)", line); l=int(m[3]); res.append((n,'U' if l>n else 'd', a*float(sc)==n+.5))
print("".join(c for n,c,e in res))
print("exact-products:", sum(e for n,c,e in res), "of", len(res))
