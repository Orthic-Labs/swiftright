"""Candidate recipe construction; no runtime/ABI/capture or measured tuple claims."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parent

def digest(b): return 'sha256:'+hashlib.sha256(b).hexdigest()
SPECS={
 'swiftui.popover': ('popover', '''struct Witness_round2_popover: View {
    @State private var shown = false
    var body: some View {
        Button("Open popover") { shown = true }
            .popover(isPresented: $shown) { Text("Popover content") }
    }
}
''', 'Text("Popover").popover(isPresented: 17) { Text("Invalid") }', [], ['open-popover','dismiss-popover'], {'presentation':'owned native popover present then dismissed','anchor':'own initiating control'}, ['presentation','events/state','accessibility'], ['Native presentation lifecycle & owned secondary window identity','Targeted activation/dismissal; no focus-steal automation','Platform popover anchor/size/dismissal behavior measured separately']),
 'swiftui.animation.spring-interruption': ('spring', '''struct Witness_round2_spring: View {
    @State private var expanded = false
    var body: some View {
        VStack {
            Button("Interrupt spring") {
                withAnimation(.spring) {
                    expanded.toggle()
                }
            }
            Rectangle().frame(width: 40, height: 40).offset(x: expanded ? {{distance}} : 0)
        }
    }
}
''', 'withAnimation(Animation.factoryInvalidSpring) {}', [('distance',[80,100])], ['start-spring','interrupt-spring-before-settlement'], {'state':'two toggles restore initial target','trajectory':'timestamped presentation samples required; no preset golden'}, ['events/state','presentation'], ['Monotonic native clock & real presentation geometry samples','Interruption delivered before observed first animation settlement','No final-state-only animation equivalence claim']),
 'swiftui.text-field-ime': ('ime', '''struct Witness_round2_ime: View {
    @State private var value = ""
    var body: some View {
        VStack { TextField(text: $value, prompt: Text("Compose")) { Text("Compose") }; Text(value) }
    }
}
''', 'TextField("Compose", text: 17)', [], ['begin-ime-composition','update-marked-text','commit-ime-composition'], {'composition':'native marked range lifecycle','committed':'captured committed string matches requested sequence'}, ['events/state','accessibility','ime'], ['Real native IME provider & recorded locale/composition sequence','Targeted owned editable control, explicit focus/session checks','Marked-text range, candidate/commit/cancel facts; ordinary keystrokes insufficient']),
 'swiftui.environment-font-color-scheme': ('environment', '''struct Witness_round2_environment: View {
    var body: some View {
        VStack { Text("Inherited environment"); Text("Inherited child") }
            .environment(\\.font, .system(size: {{font-size}}))
            .environment(\\.colorScheme, .{{scheme}})
    }
}
''', 'Text("Environment").environment(\\.font, 17)', [('font-size',[18,24]),('scheme',['light','dark'])], [], {'font':'both descendants inherit requested descriptor','scheme':'both descendants receive requested color scheme'}, ['layout','paint','events/state'], ['Native inherited font descriptor & color-scheme injection/readback','Real font shaping/paint resources; descriptor alone is not glyph parity','Distinct light/dark actual channel evidence; no aliased capture']),
 'swiftui.context-menu': ('contextmenu', '''struct Witness_round2_context_menu: View {
    @State private var chosen = false
    var body: some View {
        Text(chosen ? "Chosen" : "Open menu")
            .contextMenu { Button("Choose") { chosen = true } }
    }
}
''', 'Text("Menu").contextMenu { 17 }', [], ['open-context-menu','choose-menu-action'], {'state':'Choose action changes state exactly once','menu':'owned native menu lifecycle observed'}, ['events/state','accessibility','presentation'], ['Real native context-menu provider & owned menu identity','Targeted secondary activation + item selection/dismissal','No fake inline menu or fabricated labels'])
}

def write(blocks=None):
 for block,(_,source,negative,axes,stimuli,expected,channels,requirements) in SPECS.items():
  if blocks: block=blocks[block]
  witness_id=block+'.witness';negative_id=block+'.negative.invalid-argument'
  positive=source.encode();neg=('struct Negative_round2: View {\n    var body: some View { '+negative+' }\n}\n').encode()
  (ROOT/'witnesses'/f'{witness_id}.swift').write_bytes(positive)
  (ROOT/'witnesses'/f'{negative_id}.swift').write_bytes(neg)
  r={'kind':'recipe','version':'0.1','id':block+'.recipe','provenance':{'sourceHash':digest(positive),'createdAt':'2026-10-11T00:00:00Z','producer':'factory/recipes/round2-extra-v1','review':{'reviewer':'pending-source-review','at':'2026-10-11T00:00:00Z','decision':'candidate'}},'block':block,'witnesses':[{'id':witness_id,'sourceHash':digest(positive),'resources':[{'id':witness_id+'.swift','hash':digest(positive)}]}],'stimuli':[{'id':s,'logicalAction':s.replace('-',' '),'nativeOnly':True} for s in stimuli],'assertions':[{'id':block+'.assertion.'+c.replace('/','-'),'channel':c,'expected':expected,'observability':'blocked'} for c in channels],'axes':[{'id':k,'values':v,'coverage':'full-product'} for k,v in axes],'statefulSequences':[stimuli] if stimuli else [],'negativeCases':[{'id':negative_id,'mode':'must-not-compile','sourceHash':digest(neg)}],'instrumentationTransparency':{'case':block+'.instrumentation-transparency','channels':['layout','paint']}}
  candidate=ROOT/'dependencies/registry-candidate-manifest.json'
  if candidate.exists():
   candidate_bytes=candidate.read_bytes();candidate_value=json.loads(candidate_bytes);r['provenance']['inputs']=[{'id':candidate_value['id'],'hash':digest(candidate_bytes)}]
  (ROOT/'data'/f'{block}.json').write_text(json.dumps(r,indent=2)+'\n')
if __name__=='__main__': write()
