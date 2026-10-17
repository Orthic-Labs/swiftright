#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f2_fit_fractional_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(Font.system(size: 12.5, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("HIH").font(Font.system(size: 12.5, weight: .regular)).frame(width: 150, height: 15.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("Hamburgefonts gjpqy").font(Font.system(size: 12.5, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("Hamburgefonts gjpqy").font(Font.system(size: 12.5, weight: .regular)).frame(width: 150, height: 15.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("0123456789 42").font(Font.system(size: 12.5, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("0123456789 42").font(Font.system(size: 12.5, weight: .regular)).frame(width: 150, height: 15.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(Font.system(size: 11.5, weight: .semibold)).frame(width: 150, alignment: .leading)
                Text("HIH").font(Font.system(size: 11.5, weight: .semibold)).frame(width: 150, height: 14, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("Hamburgefonts gjpqy").font(Font.system(size: 11.5, weight: .semibold)).frame(width: 150, alignment: .leading)
                Text("Hamburgefonts gjpqy").font(Font.system(size: 11.5, weight: .semibold)).frame(width: 150, height: 14, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("0123456789 42").font(Font.system(size: 11.5, weight: .semibold)).frame(width: 150, alignment: .leading)
                Text("0123456789 42").font(Font.system(size: 11.5, weight: .semibold)).frame(width: 150, height: 14, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(Font.system(size: 12, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("HIH").font(Font.system(size: 12, weight: .regular)).frame(width: 150, height: 15.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("Hamburgefonts gjpqy").font(Font.system(size: 12, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("Hamburgefonts gjpqy").font(Font.system(size: 12, weight: .regular)).frame(width: 150, height: 15.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("0123456789 42").font(Font.system(size: 12, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("0123456789 42").font(Font.system(size: 12, weight: .regular)).frame(width: 150, height: 15.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(Font.caption2).frame(width: 150, alignment: .leading)
                Text("HIH").font(Font.caption2).frame(width: 150, height: 13.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("Hamburgefonts gjpqy").font(Font.caption2).frame(width: 150, alignment: .leading)
                Text("Hamburgefonts gjpqy").font(Font.caption2).frame(width: 150, height: 13.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("0123456789 42").font(Font.caption2).frame(width: 150, alignment: .leading)
                Text("0123456789 42").font(Font.caption2).frame(width: 150, height: 13.2, alignment: .topLeading)
            }
        }
    }
}

struct Witness_f2_fit_fractional_v1: View {
    var body: some View { Witness_f2_fit_fractional_v1_inner().frame(width: 300, height: 200, alignment: .topLeading) }
}
