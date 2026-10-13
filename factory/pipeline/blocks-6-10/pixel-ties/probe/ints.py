import subprocess, re, sys
mode, path, maxpt, scalemode = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:]
rows = [(a, 4) for a in range(1, maxpt, 2)]
out = subprocess.run(["./probe", "--mode", mode, "--path", path, "--w", str(maxpt+20)] + sys.argv[5:], input="".join(f"{a} {w}\n" for a,w in rows), capture_output=True, text=True).stdout
res = []
for (a,w), line in zip(rows, out.splitlines()):
    m = re.match(r"(\S+) (\S+) L=(\d+) R=(\d+)", line); l=int(m[3]); res.append((a, 'U' if l > a*2.5 else 'd'))
# run-length
cur=None; start=None; runs=[]
for a,c in res:
    if c!=cur:
        if cur: runs.append((cur,start,prev))
        cur=c; start=a
    prev=a
runs.append((cur,start,prev))
print(" ".join(f"{c}[{s}-{e}]" for c,s,e in runs))
