import subprocess, re, sys, math, random
mode, path, scale = sys.argv[1], sys.argv[2], float(sys.argv[3])
seed = int(sys.argv[4]) if len(sys.argv)>4 else 1
random.seed(seed)
rows=[]
pl=1.0/scale
for i in range(1200):
    kind=i%4
    if kind==0: a=random.uniform(0,250); w=random.uniform(1,40)
    elif kind==1: a=round(random.uniform(0,250),2); w=round(random.uniform(1,40),2)
    elif kind==2: # near tie
        n=random.randint(0,600); a=((n+0.5)/scale)*(1+random.choice([0,0,1e-15,-1e-15,1e-13,-1e-13])); w=random.choice([3,7.3,10,12.5,0.4,1.2])
    else: # tie via sums of tenths
        a=round(random.randint(0,2500)*0.1,1); w=round(random.randint(1,300)*0.1,1)
    rows.append((a,w))
inp="0 4\n"+"".join(f"{a!r} {w!r}\n" for a,w in rows)
out=subprocess.run(["./probe","--mode",mode,"--path",path,"--w","400","--scale",str(scale)],input=inp,capture_output=True,text=True).stdout.splitlines()[1:]
bad=0; tot=0; bad_old=0; bk={0:0,1:0,2:0,3:0}
for i,((a,w),line) in enumerate(zip(rows,out)):
    m=re.match(r"(\S+) (\S+) L=(-?\d+) R=(-?\d+).*GL=(\S+) GR=(\S+)",line)
    if abs(float(m[1])-a)>1e-5*max(1,abs(a)): print("MISALIGN",a,line); break
    L,R=int(m[3]),int(m[4])
    gl,gr=float(m[5]),float(m[6]); pL=math.floor((gl+pl*0.5)/pl); pR=math.floor((gr+pl*0.5)/pl)
    oL=round(a*scale+1e-12-1e-12) ; oR=round((a+w)*scale)
    tot+=2
    if L!=pL: bad+=1; 
    if R!=pR: bad+=1
    if L!=pL or R!=pR: bk[i%4]+=1
print(mode,path,scale,"mismatch",bad,"of",tot,"by kind(random,2dp,neartie,decimal-tie)",bk)
