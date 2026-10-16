import Foundation
import SwiftUI
import PulseHub
import PulseHubFixtures
import RightKitHub
import RightKitHubQA

/// A section whose view is already built (data loaded), shown in place of the original (as pulse-hub-render/main.swift does).
struct PreparedSection: HubSection, @unchecked Sendable {
    let base: any HubSection
    let content: AnyView
    var id: String { base.id }
    var title: String { base.title }
    var symbol: String { base.symbol }
    var order: Int { base.order }
    var group: String? { base.group }
    var settings: [HubSettingsGroup] { base.settings }
    var searchEntries: [HubSearchEntry] { base.searchEntries }
    @MainActor func makeView(_ ctx: HubContext) -> AnyView { content }
}

/// The picture of section `frame / 2` in the full HubShell at 900x600, with its data loaded, as pulse-hub-render does on the Mac.
/// The graph's root must be a user view (a bare AnyView container has no body of its own).
struct HubRootView: View {
    let content: AnyView
    var body: some View { content }
}

/// A stand-in section for the bisect mode 2.
struct ProbeSection: HubSection, @unchecked Sendable {
    var id: String { "probe" }
    var title: String { "Probe" }
    var symbol: String { "square" }
    var order: Int { 0 }
    @MainActor func makeView(_ ctx: HubContext) -> AnyView { AnyView(Text("probe section").padding(20)) }
}

@MainActor func makeHubRoot(frame rawFrame: Int) async -> HubRootView {
    // Bisect modes (frame / 100): 0 the full shell; 1 the section view alone; 2 the shell around a one-Text section.
    let mode = rawFrame / 100, frame = rawFrame % 100
    print("HOST_HUB mode=\(mode) raw=\(rawFrame)"); fflush(stdout)
    if mode == 3 { return HubRootView(content: AnyView(Text("hello").padding(20))) }
    let engine = PulseHubFixtures.engine()
    let context = HubContext(engine: engine, services: ProbeHubServices(), theme: PulseHub.theme, toasts: ToastSink())
    let sections = PulseHub.sections(notch: PulseHubFixtures.notch())
    let section = sections[min(max(frame / 2, 0), sections.count - 1)]
    print("HOST_HUB frame=\(frame) section=\(section.id) scheme=\(frame % 2 == 1 ? "dark" : "light") sections=\(sections.map { $0.id }.joined(separator: ","))"); fflush(stdout)
    let content: AnyView
    if let pulse = section as? any PulseSection { content = await pulse.preparedView(context) } else { content = section.makeView(context) }
    print("HOST_HUB prepared"); fflush(stdout)
    if mode == 1 { return HubRootView(content: AnyView(content.frame(width: 900, height: 600))) }
    if mode == 2 {
        let probe = ProbeSection()
        return HubRootView(content: AnyView(HubShell(sections: [probe], selection: .constant("probe"), context: context, initialLifecycle: .ready, footer: PulseSidebarFooter()).frame(width: 900, height: 600)))
    }
    let prepared = PreparedSection(base: section, content: content)
    let shell = HubShell(
        sections: sections.map { $0.id == section.id ? prepared : $0 },
        selection: .constant(section.id),
        context: context,
        initialLifecycle: .ready,
        footer: PulseSidebarFooter()
    )
    return HubRootView(content: AnyView(shell.environment(\.colorScheme, frame % 2 == 1 ? .dark : .light).frame(width: 900, height: 600)))
}
