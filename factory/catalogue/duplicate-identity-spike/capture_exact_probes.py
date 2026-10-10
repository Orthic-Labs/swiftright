#!/usr/bin/env python3
"""Capture bounded compiler branch & full USR demangle proof on internal Mac disk."""
import json
import subprocess
import tempfile
from pathlib import Path
from exact_identity_candidate import HERE, SDK, frozen, file_digest, digest_bytes

def main():
 trust=frozen(); compiler=trust['toolchain']['compiler']['driverPath']; demangle=str(Path(compiler).with_name('swift-demangle'))
 expected=b'#if compiler(>=5.3) && $TildeSendable\nprint("selected=active")\n#else\nprint("selected=inactive")\n#endif\n'
 assert (HERE/'tilde-sendable-probe.swift').read_bytes()==expected
 usr_input=''.join('$s'+trust['rows'][line]['pair'][0]['entity']['usr'][2:]+'\n' for line in sorted(trust['rows'])).encode()
 assert usr_input==(HERE/'usr-input.txt').read_bytes()
 receipts={}
 internal=Path('/Users/adrdsouza/.codex/tmp'); internal.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='duplicate-identity-',dir=internal) as folder:
  binary=str(Path(folder)/'condition-probe')
  operations=[('compile',[compiler,'-sdk',SDK,'-target',trust['toolchain']['target'],str(HERE/'tilde-sendable-probe.swift'),'-o',binary],None),('branch',[binary],None),('demangle',[demangle,'--expand'],usr_input)]
  for name,argv,stdin in operations:
   result=subprocess.run(argv,input=stdin,capture_output=True)
   assert result.returncode==0,(name,result.stderr)
   (HERE/('exact-'+name+'.stdout')).write_bytes(result.stdout)
   (HERE/('exact-'+name+'.stderr')).write_bytes(result.stderr)
   receipts[name]={'argv': [x.replace(binary,'<internal-temporary-probe>') for x in argv], 'exitCode':result.returncode,'stdoutSha256':digest_bytes(result.stdout),'stderrSha256':digest_bytes(result.stderr)}
 assert (HERE/'exact-branch.stdout').read_bytes()==b'selected=active\n'
 assert (HERE/'exact-demangle.stdout').read_bytes()==(HERE/'usr-demangle.txt').read_bytes()
 receipts['inputs']={'probe':file_digest(HERE/'tilde-sendable-probe.swift'),'usrInput':digest_bytes(usr_input),'compiler':trust['toolchain']['compiler']['sha256'],'demangle':file_digest(Path(demangle))}
 (HERE/'exact-probe-receipts.json').write_text(json.dumps(receipts,sort_keys=True,indent=2)+'\n')
 print('fresh compiler branch & full demangle probes passed')
if __name__=='__main__': main()
