#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_ts_text_fixed_size: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).fixedSize().overlay { Color.red }; Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.blue } }.frame(width: 110, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).fixedSize().overlay { Color.red }; Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.blue } }.frame(width: 170, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).fixedSize().overlay { Color.red }.layoutPriority(1); Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.blue } }.frame(width: 130, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }; Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).fixedSize().overlay { Color.blue }.layoutPriority(1); Text("Hi").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.green } }.frame(width: 150, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).fixedSize().overlay { Color.red } }.frame(width: 60, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Hi").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }; Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).fixedSize().overlay { Color.blue } }.frame(width: 110, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Settings and preferences for the application").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).fixedSize().overlay { Color.red } }.frame(width: 240, height: 23, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
