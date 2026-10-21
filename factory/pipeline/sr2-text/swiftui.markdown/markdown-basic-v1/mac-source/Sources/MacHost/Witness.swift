#if os(Windows)
import SwiftRightRuntime
import MarkdownUI
#else
import SwiftUI
import MarkdownUI
#endif

// Issue #68 rendered sample, case markdown-basic-v1: swift-markdown-ui 2.4.1 (default .basic theme) rendering a small document. The Mac side uses the real package from
// SwiftPM (mac-source/Package.swift); the Windows side uses the SwiftRight-patched build, probes/markdownui-compat (see prebuild.json).
struct Witness_r68_markdown_basic_v1_inner: View {
    var body: some View {
        Markdown("""
        ## Heading

        A paragraph with **bold**, *italic*, `code` and a [link](https://example.test).

        - one
        - two
        - three

        | A | B |
        |---|---|
        | 1 | 2 |
        """)
    }
}

struct Witness_r68_markdown_basic_v1: View {
    var body: some View { Witness_r68_markdown_basic_v1_inner().frame(width: 280, height: 220, alignment: .topLeading) }
}
