import subprocess, re, sys, math
mode, path = sys.argv[1], sys.argv[2]
K=8
def nx(x,n):
    for _ in range(abs(n)): x = math.nextafter(x, math.inf if n>0 else -math.inf)
    return x
for p in [float(x) for x in sys.argv[3:]]:
    vals = [nx(p,k) for k in range(-K,K+1)]
    inp = "".join(f"{a!r} 20\n" for a in vals)
    out = subprocess.run(["./probe", "--mode", mode, "--path", path], input=inp, capture_output=True, text=True).stdout
    s = ""
    for line in out.splitlines():
        m = re.match(r"(\S+) (\S+) L=(\d+) R=(\d+)", line)
        s += str(int(m[3]) - int(p*2.5 - 0.5))
    print(f"{p:6g} px={p*2.5:7.1f} {s[:K]}|{s[K]}|{s[K+1:]}")
