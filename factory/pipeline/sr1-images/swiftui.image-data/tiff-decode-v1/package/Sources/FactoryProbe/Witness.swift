#if os(Windows)
import Foundation
import SwiftRightRuntime
import SwiftRightHost
#else
import SwiftUI
import ImageIO
#endif

// Issue #61, tiff-decode-v1: uncompressed baseline TIFF (little endian, one strip): RGB 8-bit, RGBA 8-bit unassociated alpha (alpha 0 or 255 only), grey 8-bit ramp. System decoder (WIC) on Windows, ImageIO on the Mac.
private let tiff_rgb = "SUkqAAgAAAAKAAABAwABAAAAGAAAAAEBAwABAAAAFAAAAAIBAwADAAAAhgAAAAMBAwABAAAAAQAAAAYBAwABAAAAAgAAABEBBAABAAAAjAAAABUBAwABAAAAAwAAABYBAwABAAAAFAAAABcBBAABAAAAoAUAABwBAwABAAAAAQAAAAAAAAAIAAgACAD/AAD/AAAA/wAA/wAAAP8AAP///wD//wAA//8A////AP//AP/IMjLIMjIyyDIyyDIyMsgyMsjmeB7meB4eeOYeeOZklshklsj/AAD/AAAA/wAA/wAAAP8AAP///wD//wAA//8A////AP//AP/IMjLIMjIyyDIyyDIyMsgyMsjmeB7meB4eeOYeeOZklshklsj/AAD/AAAA/wAA/wAAAP8AAP///wD//wAA//8A////AP//AP/IMjLIMjIyyDIyyDIyMsgyMsjmeB7meB4eeOYeeOZklshklsj/AAD/AAAA/wAA/wAAAP8AAP///wD//wAA//8A////AP//AP/IMjLIMjIyyDIyyDIyMsgyMsjmeB7meB4eeOYeeOZklshklsj/AAD/AAAA/wAA/wAAAP8AAP///wD//wAA//8A////AP//AP/IMjLIMjIyyDIyyDIyMsgyMsjmeB7meB4eeOYeeOZklshklsj/AAD/AAAA/wAA/wAAAP8AAP///wD//wAA//8A////AP//AP/IMjLIMjIyyDIyyDIyMsgyMsjmeB7meB4eeOYeeOZklshklsj/AAD/AAAA/wAA/wAAAP8AAP///wD//wAA//8A////AP//AP/IMjLIMjIyyDIyyDIyMsgyMsjmeB7meB4eeOYeeOZklshklsj/AAD/AAAA/wAA/wAAAP8AAP///wD//wAA//8A////AP//AP/IMjLIMjIyyDIyyDIyMsgyMsjmeB7meB4eeOYeeOZklshklsj/AAD/AAAA/wAA/wAAAP8AAP///wD//wAA//8A////AP//AP/IMjLIMjIyyDIyyDIyMsgyMsjmeB7meB4eeOYeeOZklshklsj/AAD/AAAA/wAA/wAAAP8AAP///wD//wAA//8A////AP//AP/IMjLIMjIyyDIyyDIyMsgyMsjmeB7meB4eeOYeeOZklshklsi0Woy0WowKFB4KFB7w5tzw5tyAgICAgIBAQEBAQED/gAD/gAAAgP8AgP8RY8kRY8npDE3pDE0AAAAAAAD////////AwMDAwMC0Woy0WowKFB4KFB7w5tzw5tyAgICAgIBAQEBAQED/gAD/gAAAgP8AgP8RY8kRY8npDE3pDE0AAAAAAAD////////AwMDAwMC0Woy0WowKFB4KFB7w5tzw5tyAgICAgIBAQEBAQED/gAD/gAAAgP8AgP8RY8kRY8npDE3pDE0AAAAAAAD////////AwMDAwMC0Woy0WowKFB4KFB7w5tzw5tyAgICAgIBAQEBAQED/gAD/gAAAgP8AgP8RY8kRY8npDE3pDE0AAAAAAAD////////AwMDAwMC0Woy0WowKFB4KFB7w5tzw5tyAgICAgIBAQEBAQED/gAD/gAAAgP8AgP8RY8kRY8npDE3pDE0AAAAAAAD////////AwMDAwMC0Woy0WowKFB4KFB7w5tzw5tyAgICAgIBAQEBAQED/gAD/gAAAgP8AgP8RY8kRY8npDE3pDE0AAAAAAAD////////AwMDAwMC0Woy0WowKFB4KFB7w5tzw5tyAgICAgIBAQEBAQED/gAD/gAAAgP8AgP8RY8kRY8npDE3pDE0AAAAAAAD////////AwMDAwMC0Woy0WowKFB4KFB7w5tzw5tyAgICAgIBAQEBAQED/gAD/gAAAgP8AgP8RY8kRY8npDE3pDE0AAAAAAAD////////AwMDAwMC0Woy0WowKFB4KFB7w5tzw5tyAgICAgIBAQEBAQED/gAD/gAAAgP8AgP8RY8kRY8npDE3pDE0AAAAAAAD////////AwMDAwMC0Woy0WowKFB4KFB7w5tzw5tyAgICAgIBAQEBAQED/gAD/gAAAgP8AgP8RY8kRY8npDE3pDE0AAAAAAAD////////AwMDAwMA="
private let tiff_rgba = "SUkqAAgAAAALAAABAwABAAAAGAAAAAEBAwABAAAAFAAAAAIBAwAEAAAAkgAAAAMBAwABAAAAAQAAAAYBAwABAAAAAgAAABEBBAABAAAAmgAAABUBAwABAAAABAAAABYBAwABAAAAFAAAABcBBAABAAAAgAcAABwBAwABAAAAAQAAAFIBAwABAAAAAgAAAAAAAAAIAAgACAAIAAAAyAALAMP/FgC+/yEAuf8sALT/NwCv/0IAqv9NAKUAWACg/2MAm/9uAJb/eQCR/4QAjP+PAIf/mgCCAKUAff+wAHj/uwBz/8YAbv/RAGn/3ABk/+cAXwDyAFr//QBV/wAMyP8LDMP/Fgy+/yEMuf8sDLT/Nwyv/0IMqgBNDKX/WAyg/2MMm/9uDJb/eQyR/4QMjP+PDIcAmgyC/6UMff+wDHj/uwxz/8YMbv/RDGn/3AxkAOcMX//yDFr//QxV/wAYyP8LGMP/Fhi+/yEYuf8sGLT/NxivAEIYqv9NGKX/WBig/2MYm/9uGJb/eRiR/4QYjACPGIf/mhiC/6UYff+wGHj/uxhz/8YYbv/RGGkA3Bhk/+cYX//yGFr//RhV/wAkyP8LJMP/FiS+/yEkuf8sJLQANySv/0Ikqv9NJKX/WCSg/2Mkm/9uJJb/eSSRAIQkjP+PJIf/miSC/6Ukff+wJHj/uyRz/8YkbgDRJGn/3CRk/+ckX//yJFr//SRV/wAwyP8LMMP/FjC+/yEwuQAsMLT/NzCv/0Iwqv9NMKX/WDCg/2Mwm/9uMJYAeTCR/4QwjP+PMIf/mjCC/6Uwff+wMHj/uzBzAMYwbv/RMGn/3DBk/+cwX//yMFr//TBV/wA8yP8LPMP/Fjy+ACE8uf8sPLT/Nzyv/0I8qv9NPKX/WDyg/2M8mwBuPJb/eTyR/4Q8jP+PPIf/mjyC/6U8ff+wPHgAuzxz/8Y8bv/RPGn/3Dxk/+c8X//yPFr//TxVAABIyP8LSMMAFki+/yFIuf8sSLT/N0iv/0JIqv9NSKX/WEigAGNIm/9uSJb/eUiR/4RIjP+PSIf/mkiC/6VIfQCwSHj/u0hz/8ZIbv/RSGn/3Ehk/+dIX//ySFoA/UhV/wBUyAALVMP/FlS+/yFUuf8sVLT/N1Sv/0JUqv9NVKUAWFSg/2NUm/9uVJb/eVSR/4RUjP+PVIf/mlSCAKVUff+wVHj/u1Rz/8ZUbv/RVGn/3FRk/+dUXwDyVFr//VRV/wBgyP8LYMP/FmC+/yFguf8sYLT/N2Cv/0JgqgBNYKX/WGCg/2Ngm/9uYJb/eWCR/4RgjP+PYIcAmmCC/6Vgff+wYHj/u2Bz/8Zgbv/RYGn/3GBkAOdgX//yYFr//WBV/wBsyP8LbMP/Fmy+/yFsuf8sbLT/N2yvAEJsqv9NbKX/WGyg/2Nsm/9ubJb/eWyR/4RsjACPbIf/mmyC/6Vsff+wbHj/u2xz/8Zsbv/RbGkA3Gxk/+dsX//ybFr//WxV/wB4yP8LeMP/Fni+/yF4uf8seLQAN3iv/0J4qv9NeKX/WHig/2N4m/9ueJb/eXiRAIR4jP+PeIf/mniC/6V4ff+weHj/u3hz/8Z4bgDReGn/3Hhk/+d4X//yeFr//XhV/wCEyP8LhMP/FoS+/yGEuQAshLT/N4Sv/0KEqv9NhKX/WISg/2OEm/9uhJYAeYSR/4SEjP+PhIf/moSC/6WEff+whHj/u4RzAMaEbv/RhGn/3IRk/+eEX//yhFr//YRV/wCQyP8LkMP/FpC+ACGQuf8skLT/N5Cv/0KQqv9NkKX/WJCg/2OQmwBukJb/eZCR/4SQjP+PkIf/mpCC/6WQff+wkHgAu5Bz/8aQbv/RkGn/3JBk/+eQX//ykFr//ZBVAACcyP8LnMMAFpy+/yGcuf8snLT/N5yv/0Kcqv9NnKX/WJygAGOcm/9unJb/eZyR/4ScjP+PnIf/mpyC/6WcfQCwnHj/u5xz/8acbv/RnGn/3Jxk/+ecX//ynFoA/ZxV/wCoyAALqMP/Fqi+/yGouf8sqLT/N6iv/0Koqv9NqKUAWKig/2Oom/9uqJb/eaiR/4SojP+PqIf/mqiCAKWoff+wqHj/u6hz/8aobv/RqGn/3Khk/+eoXwDyqFr//ahV/wC0yP8LtMP/FrS+/yG0uf8stLT/N7Sv/0K0qgBNtKX/WLSg/2O0m/9utJb/ebSR/4S0jP+PtIcAmrSC/6W0ff+wtHj/u7Rz/8a0bv/RtGn/3LRkAOe0X//ytFr//bRV/wDAyP8LwMP/FsC+/yHAuf8swLT/N8CvAELAqv9NwKX/WMCg/2PAm/9uwJb/ecCR/4TAjACPwIf/msCC/6XAff+wwHj/u8Bz/8bAbv/RwGkA3MBk/+fAX//ywFr//cBV/wDMyP8LzMP/Fsy+/yHMuf8szLQAN8yv/0LMqv9NzKX/WMyg/2PMm/9uzJb/ecyRAITMjP+PzIf/msyC/6XMff+wzHj/u8xz/8bMbgDRzGn/3Mxk/+fMX//yzFr//cxV/wDYyP8L2MP/Fti+/yHYuQAs2LT/N9iv/0LYqv9N2KX/WNig/2PYm/9u2JYAediR/4TYjP+P2If/mtiC/6XYff+w2Hj/u9hzAMbYbv/R2Gn/3Nhk/+fYX//y2Fr//dhV/wDkyP8L5MP/FuS+ACHkuf8s5LT/N+Sv/0Lkqv9N5KX/WOSg/2PkmwBu5Jb/eeSR/4TkjP+P5If/muSC/6Xkff+w5HgAu+Rz/8bkbv/R5Gn/3ORk/+fkX//y5Fr//eRVAA=="
private let tiff_grey = "SUkqAAgAAAAKAAABAwABAAAAEAAAAAEBAwABAAAAEAAAAAIBAwABAAAACAAAAAMBAwABAAAAAQAAAAYBAwABAAAAAQAAABEBBAABAAAAiAAAABUBAwABAAAAAQAAABYBAwABAAAAEAAAABcBBAABAAAAAAEAABwBAwABAAAAAQAAAAAAAAAIAAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj9AQUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVpbXF1eX2BhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4SFhoeIiYqLjI2Oj5CRkpOUlZaXmJmam5ydnp+goaKjpKWmp6ipqqusra6vsLGys7S1tre4ubq7vL2+v8DBwsPExcbHyMnKy8zNzs/Q0dLT1NXW19jZ2tvc3d7f4OHi4+Tl5ufo6err7O3u7/Dx8vP09fb3+Pn6+/z9/v8="

/// Windows: the SYSTEM decoder (WIC through ImagePolicy: iCCP colour management, TIFF); the default Swift decoder ignores iCCP and refuses TIFF. Mac: ImageIO.
@MainActor @ViewBuilder func witnessImage(_ base64: String, label: String) -> some View {
#if os(Windows)
    let pixels: RGBAImage = {
        ImageDecoder.backend = .system
        return try! ImageDecoder.decode(Data(base64Encoded: base64)!, maxPixel: 0)
    }()
    Image(decorative: pixels, scale: 2.5).accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityAddTraits(.isImage)
#else
    let source = CGImageSourceCreateWithData(Data(base64Encoded: base64)! as CFData, nil)!
    let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    Image(decorative: cgImage, scale: 2.5).accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityAddTraits(.isImage)
#endif
}

struct Witness_i61_tiff_decode_v1: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) { witnessImage(tiff_rgb, label: "TIFF RGB"); witnessImage(tiff_rgba, label: "TIFF RGBA"); witnessImage(tiff_grey, label: "TIFF grey") }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
