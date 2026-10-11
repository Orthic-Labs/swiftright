"""Archive hydration for frozen Swift16 proof; recorded semantic paths stay exact."""
import hashlib,importlib.util,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
FROZEN_HASH='sha256:78620db51cdc47da5c1cafcb3f546cea918b67c8a3c5dcc5131b83988e652a0e'
def digest(b):return 'sha256:'+hashlib.sha256(b).hexdigest()
p=HERE/'exact_swift16.py'
if digest(p.read_bytes())!=FROZEN_HASH:raise ValueError('frozen Swift16 helper bytes changed')
s=importlib.util.spec_from_file_location('archived_frozen_swift16',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class ArchivedExactSwift16:
 def __init__(self,read_bytes=None,force_archive=False):
  if force_archive and read_bytes is None:raise ValueError('forced archive resolver required')
  self.reader=read_bytes or (lambda path,force_archive=False:Path(path).read_bytes());self.force_archive=force_archive
  manifest=(HERE/'capture-inputs.json').read_bytes();m.require(digest(manifest)==m.INPUT_MANIFEST_HASH,'frozen Swift16 actual input manifest')
  descriptors=json.loads(manifest);self.paths={k:Path(d['path']) if Path(d['path']).is_absolute() else m.ROOT/d['path'] for k,d in descriptors.items()}
  self.pins={k:d['sha256'] for k,d in descriptors.items()};self.sizes={k:d['bytes'] for k,d in descriptors.items()}
  for name,(path,pin) in m.TOOLS.items():self.paths['tool:'+name]=path;self.pins['tool:'+name]=pin
  self.paths['headerLineage']=m.HEADER/'swift-foundation-index-evidence.json';self.pins['headerLineage']=m.HEADER_EVIDENCE_HASH
  self.inputs={k:self.reader(str(path),force_archive=force_archive) for k,path in self.paths.items()}
  self.check_bytes(self.inputs)
  self.guard=m.ExactSwift16.__new__(m.ExactSwift16);self.guard.paths={k:self.paths[k] for k in descriptors};self.guard.inputs={k:self.inputs[k] for k in descriptors};self.guard.pins={k:self.pins[k] for k in descriptors};self.guard.source_anchors=m.nominal_source(self.inputs['source'].decode())
 def check_bytes(self,b):
  m.require(set(b)==set(self.inputs) if hasattr(self,'inputs') else set(b)==set(self.paths),'archive Swift16 input closure')
  for key,raw in b.items():m.require(type(raw) is bytes and digest(raw)==self.pins[key] and (key not in self.sizes or len(raw)==self.sizes[key]),'archive Swift16 exact bytes '+key)
 def validate(self,inputs=None):
  b=dict(self.inputs)
  if inputs is not None:m.require(set(inputs)<=set(b),'archive Swift16 override closure');b.update(inputs)
  # Frozen production semantic checks run before immutable raw-byte admission.
  rows=self.guard.validate({k:b[k] for k in self.guard.inputs})
  self.check_bytes(b);return rows
