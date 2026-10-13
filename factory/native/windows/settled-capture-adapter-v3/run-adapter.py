"""Local explicit archive reader. Never launches, repairs, or infers receipt paths."""
import argparse,json
from pathlib import Path
from adapter import normalize,r
ap=argparse.ArgumentParser();ap.add_argument('--inputs',required=True);ap.add_argument('--archive-root',required=True);ap.add_argument('--output',required=True);args=ap.parse_args()
root=Path(args.archive_root).resolve()
def reader(ref):
 path=(root/ref['path']).resolve()
 if not path.is_relative_to(root):raise ValueError('archive reader escaped root')
 return path.read_bytes()
result=normalize(r.parse(Path(args.inputs).read_bytes()),reader)
with Path(args.output).open('x',encoding='utf-8') as output:json.dump(result,output,ensure_ascii=False,indent=2,allow_nan=False);output.write('\n')
print(json.dumps({'typedStatus':result['typedStatus'],'captures':len(result['captures']),'diagnosticChannels':len(result['diagnosticChannels']),'qualified':False,'issues':result['issues']}))
