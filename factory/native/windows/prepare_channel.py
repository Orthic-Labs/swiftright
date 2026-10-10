"""Factory-only known-content/invalidation control, never a native case witness."""
from pathlib import Path
import argparse
from factory.core.artifacts import canonical_hash,file_hash,write_artifact
from .prepare_additive import prepare_additive
SOURCE='''import SwiftRightRuntime
struct FactoryChannelWitness: View {
    @State private var changed = false
    func changeContent() { changed.toggle() }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(changed ? Color.blue : Color.red).frame(width: 48, height: 48)
                Rectangle().fill(changed ? Color.red : Color.blue).frame(width: 48, height: 48)
            }
            HStack(spacing: 0) {
                Rectangle().fill(changed ? Color.red : Color.blue).frame(width: 48, height: 48)
                Rectangle().fill(changed ? Color.blue : Color.red).frame(width: 48, height: 48)
            }
            Text(changed ? "CONTROL phase B" : "CONTROL phase A").font(.system(size: 18, weight: .bold)).frame(width: 220, height: 30)
        }.padding(8)
    }
}
'''
def prepare(output,receipt):
    output=Path(output).resolve();lane=Path(__file__).resolve().parent
    if not output.is_relative_to(lane) or output==lane or output.exists():raise ValueError('fresh owned control root required')
    seed=output/'control-source';seed.mkdir(parents=True);source=seed/'Witness.swift';source.write_text(SOURCE)
    manifest=seed/'manifest.json';write_artifact(manifest,{'sourceFile':source.name,'sourceHash':file_hash(source),'witnessType':'FactoryChannelWitness','case':{'id':'factory.windows.channel-control','hash':canonical_hash({'sourceHash':file_hash(source),'purpose':'observational channel control'})},'compileExpectation':'success','executionEligible':False})
    package=output/'package';plan=prepare_additive(manifest,package,Path(receipt))
    main=package/'Sources/FactoryProbe/main.swift';text=main.read_text()
    text=text.replace('    var started: UInt64?', '    let channelWitness = FactoryChannelWitness()\n    var channelChanged = false\n    var started: UInt64?')
    text=text.replace('Graph(FactoryChannelWitness(),','Graph(channelWitness,')
    text=text.replace('        graph?.tick(now:', '        if time - (started ?? time) > 4_000_000_000 && !channelChanged { channelChanged = true; channelWitness.changeContent(); print("FACTORY_CHANNEL_CONTENT_CHANGE tick=\\(time)"); fflush(stdout) }\n        graph?.tick(now:')
    text=text.replace('> 10_000_000_000','> 20_000_000_000')
    main.write_text(text);plan['sourceBindings']=[{'path':str(p.relative_to(package)),'sha256':file_hash(p)} for p in sorted(package.rglob('*.swift'))]
    plan.update(purpose='fixed channel control host',tupleIndependent=True,nativeReplayAllowed=False,channelContent='native rectangles checker + text, actual State change after four seconds',nativeCaseCaptureCount=0)
    write_artifact(package/'plan.json',plan);return plan
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--runtime-receipt',type=Path,required=True);a=p.parse_args();prepare(a.output,a.runtime_receipt)
