"""Bounded reader-backed replay; no SDK/tool/cache filesystem inspection."""
from __future__ import annotations
import hashlib, importlib.util, json, shlex, types
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
ROOT = HERE.parents[4]
BASE = PROOF.parent
ORIGINAL_HASH = '391cbf4c02748ed4b995936f606dcee2ab95e007767e8dd498b4b3d5f745e997'
EVALUATE_HASH = '0d5a8f1237c1c547890723c4272b7b06dc249d0b46f383e2d23c12743c9fe80d'
EVIDENCE_HASH = 'd4b55f38b99b0dc9cd4636786f8482f2c00c476a46b8c509129927ba709f3a96'
PARSER_HASH = '83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5'
RESOLVER_HASH = '28c7ddd5974534efc13cb93d6030ce64fadb752e6c98212205f02c4b9787a8d4'

def require(ok, reason):
    if not ok: raise ValueError(reason)

def digest(raw): return hashlib.sha256(raw).hexdigest()

def load(path, name, expected=None):
    raw = path.read_bytes()
    if expected: require(digest(raw) == expected, name + '-source-pin')
    # Only repository Python source is loaded; captured tools are never executed.
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

@dataclass(frozen=True)
class SourceFact:
    semantic_path: str
    raw: bytes
    def __str__(self): return self.semantic_path
    def read_text(self): return self.raw.decode('utf-8')

class Replay:
    def __init__(self, read_bytes=None, force_archive=False):
        require(type(force_archive) is bool, 'force-archive-bool')
        self.force_archive = force_archive
        self.original = load(PROOF/'prove_access.py', 'frozen_destructor_proof', ORIGINAL_HASH)
        o = self.original
        archive = self.local(PROOF/'archive-manifest-v2.json', o.ARCHIVE_HASH)
        self.archive_manifest = json.loads(archive)
        self.raw_rows = {r['originalPath']:r for r in self.archive_manifest['rows']}
        self.verify_archive()
        self.resolvers = None
        if read_bytes is None:
            resolver = load(BASE/'archive-resolver-v1/archive_resolver.py', 'destructor_resolver', RESOLVER_HASH)
            self.resolvers = [resolver.ArchiveResolver(), resolver.ArchiveResolver(manifest_path=resolver.V2_MANIFEST_PATH, expected_manifest_sha256=resolver.V2_MANIFEST_SHA256)]
            read_bytes = self.resolve
        require(callable(read_bytes), 'reader-callable')
        self.reader = read_bytes
        self.bindings = {}
        self.sources = {}
        self.cursor_paths = {}

    def local(self, path, expected=None):
        require(path.is_relative_to(ROOT), 'repository-only-local-read')
        raw=path.read_bytes()
        if expected: require(digest(raw)==expected, 'repository-byte-pin')
        return raw

    def verify_archive(self):
        # Preserve original verify_archive's complete repository archive contract,
        # including members not consumed by AST/source hydration.
        manifest=self.archive_manifest; names=[]
        require(type(manifest['rows']) is list, 'raw-archive-rows')
        for row in manifest['rows']:
            relative=Path(row['archivePath'])
            require(len(relative.parts)==2 and relative.parts[0]=='raw-arm64-v2' and relative.name not in names, 'repository-archive-shape')
            names.append(relative.name)
            path=PROOF/relative
            require(path.is_file(), 'repository-archive-file')
            raw=self.local(path,row['sha256'])
            require(type(row['bytes']) is int and len(raw)==row['bytes'], 'repository-archive-bytes')
        require(len(names)==13 and len(self.raw_rows)==13 and {p.name for p in (PROOF/'raw-arm64-v2').iterdir()}==set(names), 'repository-archive-coverage')
        require(type(manifest['totalBytes']) is int and manifest['totalBytes']==sum(row['bytes'] for row in manifest['rows']), 'repository-archive-size')

    def resolve(self, semantic_path, *, force_archive=False):
        for resolver in self.resolvers:
            if semantic_path in resolver._records:
                return resolver.read_bytes(semantic_path, force_archive=force_archive)
        raise ValueError('semantic-path-not-archived: '+semantic_path)

    def read(self, path, expected=None, size=None):
        key=str(path)
        if key in self.raw_rows:
            row=self.raw_rows[key]; rel=Path(row['archivePath'])
            require(len(rel.parts)==2 and rel.parts[0]=='raw-arm64-v2', 'raw-archive-path')
            raw=self.local(PROOF/rel, row['sha256'])
            require(type(row['bytes']) is int and len(raw)==row['bytes'], 'raw-archive-size')
        elif key.startswith(str(ROOT)+'/'):
            raw=self.local(Path(key))
        else:
            raw=self.reader(key, force_archive=self.force_archive)
        require(type(raw) is bytes, 'reader-bytes')
        if expected: require(digest(raw)==expected.removeprefix('sha256:'), 'reader-hash')
        if size is not None: require(type(size) is int and len(raw)==size, 'reader-size')
        self.bindings[key]={'path':key,'sha256':'sha256:'+digest(raw),'bytes':len(raw)}
        return raw

    def source(self, module):
        return self.sources[module]

    def cursor_source_identity(self, fields, src):
        key=(fields['usr'],fields['modulename'],fields['line'])
        return self.cursor_paths.get(key)==(fields['filepath'],str(src))

    def sha(self, path):
        key=str(path)
        require(key in self.bindings, 'unverified-semantic-file')
        return self.bindings[key]['sha256'][7:]

    def expected_argv(self, module):
        o=self.original
        header=shlex.split(self.source(module).read_text().splitlines()[2].split(': ',1)[1]); flags=[];i=0
        while i<len(header):
            if header[i] in {'-target','-target-variant','-target-arch-variant'}:
                if header[i]=='-target': flags+=['-target',o.TARGET]
                i+=2
            else: flags.append(header[i]);i+=1
        return [str(o.TOOL),'-dump-ast','-parse-as-library','-sdk',str(o.SDK)]+flags+[str(self.source(module))]

    def verify_receipt(self, module, receipt):
        o=self.original; src=self.source(module)
        require(receipt['argv']==self.expected_argv(module), 'target-header-argv')
        require(receipt['cwd']==str(o.RAW), 'capture-cwd')
        require(type(receipt['exitCode']) is int and receipt['exitCode']==0 and receipt['timedOut'] is False, 'successful-semantic-ast')
        require(receipt['tool']['path']==str(o.TOOL) and receipt['tool']['sha256']=='sha256:'+self.sha(o.TOOL), 'archive-compiler')
        require(receipt['inputs']==[{'path':str(src),'sha256':'sha256:'+self.sha(src),'bytes':len(src.raw)}], 'archive-source')
        for channel in ['stdout','stderr']:
            path=o.RAW/(module+'-arm64.'+channel); raw=self.read(path)
            require(receipt[channel]=={'path':str(path),'sha256':'sha256:'+digest(raw),'bytes':len(raw)}, 'raw-ast-'+channel)

    def verify_all(self):
        o=self.original
        seed=json.loads(self.read(o.SEED,o.SEED_HASH)); require(len(seed['rows'])==42,'bounded-42')
        for row in seed['rows']:
            fields=row['cursor']['fields'];key=(fields['usr'],fields['modulename'],fields['line'])
            require(key not in self.cursor_paths,'cursor-path-pair-unique')
            self.cursor_paths[key]=(fields['filepath'],row['source']['path'])
        pins=json.loads(self.read(PROOF/'raw-pins.json',o.RAW_PINS_HASH))
        for p in pins: self.read(p['path'],p['sha256'])
        for module in ['SwiftUI','SwiftUICore']:
            descriptors=[r['source'] for r in seed['rows'] if r['module']==module]
            require(descriptors and all(d==descriptors[0] for d in descriptors),'source-descriptor-set')
            desc=descriptors[0]; require(desc['path']==str(o.source(module)),'source-semantic-path')
            self.sources[module]=SourceFact(desc['path'],self.read(desc['path'],desc['sha256'],desc['bytes']))
        for row in seed['rows']:
            for key in ['response','request']:
                desc=row[key];self.read(ROOT/desc['path'],desc['sha256'])
        demangles=o.demangle_rows(self.read(o.RAW/'demangle.stdout').decode())
        require(set(demangles)=={r['cursor']['fields']['usr'] for r in seed['rows']},'exact-demangle-set')
        records={}
        for module in ['SwiftUI','SwiftUICore']:
            receipt=json.loads(self.read(o.RAW/(module+'-arm64.receipt.json')))
            self.verify_receipt(module,receipt)
            records[module]=o.parse_ast(self.read(o.RAW/(module+'-arm64.stdout')).decode(),module)
        link=json.loads(self.read(ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json','836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec'))
        parser=load(ROOT/'factory/catalogue/module-provenance-spike/exact_validator.py','frozen_destructor_index',PARSER_HASH)
        indices={}
        for interface in link['interfaces']:
            raw=self.read(ROOT/interface['indexOutput'],interface['indexOutputSha256'])
            self.read(ROOT/interface['indexRequest'],interface['indexRequestSha256'])
            require(interface['requestIdentity']['target']==o.TARGET and interface['requestIdentity']['moduleName']==interface['module'] and interface['requestIdentity']['sourcefile']==str(self.source(interface['module'])),'index-request-identity')
            indices[interface['module']]=parser.entities(raw.decode())
        adapted=load(HERE/'evaluate_reader.py','reader_evaluate',EVALUATE_HASH)
        env=dict(o.evaluate.__globals__);env.update(source=self.source,sha=self.sha,cursor_source_identity=self.cursor_source_identity)
        evaluate=types.FunctionType(adapted.evaluate.__code__,env)
        rows=[evaluate(row,records[row['module']],demangles,indices[row['module']]) for row in seed['rows']]
        out={'kind':'bounded-destructor-compiler-effective-access-proof','status':'independent-review-pending','sourceKitSeedHash':'sha256:'+o.SEED_HASH,'target':o.TARGET,'rows':rows,'summary':dict(Counter(r['effectiveAccess'] for r in rows)),'promotionsMade':0,'rule':'Explicit compiler effective access settles physical SDK declaration access only; frozen textual SourceKit USRs are lineage, not proof of canonical ABI IDs; owner access/API-addressability decisions remain separate.'}
        expected=json.loads(self.read(PROOF/'effective-access-evidence.json',EVIDENCE_HASH))
        require(out==expected,'all-42-facts-exact-frozen-evidence')
        return out

def verify_all(read_bytes=None, force_archive=False):
    return Replay(read_bytes,force_archive).verify_all()

def ast_bytes(module, read_bytes=None, force_archive=False):
    require(module in ('SwiftUI','SwiftUICore'),'ast-module')
    replay=Replay(read_bytes,force_archive)
    pins=json.loads(replay.read(PROOF/'raw-pins.json',replay.original.RAW_PINS_HASH))
    path=str(replay.original.RAW/(module+'-arm64.stdout'))
    expected=next(x['sha256'] for x in pins if x['path']==path)
    return replay.read(path,expected)
