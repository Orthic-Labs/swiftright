#if os(Windows)
import Foundation
import WinSDK
import SwiftRightRuntime

// Wave 0 block I1 (docs/foundations-images-fonts.md 1.1): the Windows Imaging Component codec behind `SystemImageCodec`. COM through WinSDK vtables (no C++ wrappers).
// One call decodes one frame to straight-alpha RGBA8 in sRGB. Everything that is policy (format sniffing, completeness, ICO entry choice, EXIF orientation, maxPixel) lives in
// `ImagePolicy` above this file, so the Mac backend (ImageIO) and this one share it.
// WIC facts used (Microsoft Learn, fetched 15 October 2026):
//   - IWICImagingFactory::CreateDecoderFromStream + WICDecodeMetadataCacheOnDemand, GetFrameCount/GetFrame: https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-jpegmetadataencoding
//   - IWICColorTransform "transforms an IWICBitmapSource from one color context to another", initialised once: https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwiccolortransform
//   - built-in codecs (BMP, GIF, ICO, JPEG, PNG, TIFF ...): https://learn.microsoft.com/en-us/windows/win32/wic/native-wic-codecs
// GUIDs and HRESULT values below are read from the SDK header wincodec.h / winerror.h 10.0.26100.0.

enum WIC {
    static func guid(_ a: UInt32, _ b: UInt16, _ c: UInt16, _ d: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)) -> GUID {
        GUID(Data1: a, Data2: b, Data3: c, Data4: d)
    }
    static let clsidFactory = guid(0xcacaf262, 0x9370, 0x4615, (0xa1, 0x3b, 0x9f, 0x55, 0x39, 0xda, 0x4c, 0x0a))
    static let iidFactory = guid(0xec5ec8a9, 0xc395, 0x4314, (0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70))
    static let fmtBGRA = guid(0x6fddc324, 0x4e03, 0x4bfe, (0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x0f))
    static let fmtBGR = guid(0x6fddc324, 0x4e03, 0x4bfe, (0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x0e))
    static let fmtRGBA64 = guid(0x6fddc324, 0x4e03, 0x4bfe, (0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x16))

    static let componentNotFound: HRESULT = HRESULT(bitPattern: 0x88982F50)
    static let unknownImageFormat: HRESULT = HRESULT(bitPattern: 0x88982F07)
    static let badImage: HRESULT = HRESULT(bitPattern: 0x88982F60)
    static let badHeader: HRESULT = HRESULT(bitPattern: 0x88982F61)
    static let frameMissing: HRESULT = HRESULT(bitPattern: 0x88982F62)
    static let badStreamData: HRESULT = HRESULT(bitPattern: 0x88982F70)
    static let streamRead: HRESULT = HRESULT(bitPattern: 0x88982F72)
    static let unsupportedPixelFormat: HRESULT = HRESULT(bitPattern: 0x88982F80)
    static let imageSizeOutOfRange: HRESULT = HRESULT(bitPattern: 0x88982F51)
    static let rpcChangedMode: HRESULT = HRESULT(bitPattern: 0x80010106)

    static func describe(_ hr: HRESULT) -> String { "HRESULT 0x" + String(UInt32(bitPattern: hr), radix: 16, uppercase: true) }

    /// Maps a failing WIC call to the typed error; `stage` names the call.
    static func error(_ hr: HRESULT, _ stage: String) -> ImageDecodeError {
        let text = "WIC \(stage): \(describe(hr))"
        switch hr {
        case componentNotFound, unknownImageFormat: return .notAnImage
        case streamRead: return .truncated(text)
        case badImage, badHeader, badStreamData, frameMissing, imageSizeOutOfRange: return .corrupt(text)
        case unsupportedPixelFormat: return .unsupported(text)
        default: return .corrupt(text)
        }
    }
}

/// One COM object reference, released on deinit. `T` is the C interface struct (every WIC interface starts with an IUnknown vtable).
final class COMRef<T> {
    let ptr: UnsafeMutablePointer<T>
    init(_ p: UnsafeMutablePointer<T>) { ptr = p }
    deinit {
        let unknown = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    }
    /// The same object seen as another WIC interface whose vtable starts with this one's (IWICBitmapFrameDecode as IWICBitmapSource ...).
    func cast<U>(_ type: U.Type) -> UnsafeMutablePointer<U> { UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: U.self) }
}

enum ImageCodecWIC {
    /// nil = leave the profile's own intent. Set from the measurement against the Mac (see G33).
    static let defaultIntent: Int? = nil

    struct Decoded { var image: RGBAImage; var frameCount: Int; var transformedFromProfile: Bool; var sourceFormat: String; var profile: [UInt8]? }

    /// Decodes frame `frameIndex` (0 for everything but ICO) to straight RGBA8 sRGB. `frameSize` of the chosen frame is returned so policy can check an ICO entry.
    static func frameSizes(_ data: Data) throws -> [(Int, Int)] {
        try withDecoder(data) { _, decoder, count in
            var sizes: [(Int, Int)] = []
            for i in 0..<count {
                let frame = try getFrame(decoder, i)
                var w: UINT = 0, h: UINT = 0
                let src = frame.cast(IWICBitmapSource.self)
                let hr = src.pointee.lpVtbl.pointee.GetSize(src, &w, &h)
                if hr < 0 { throw WIC.error(hr, "GetSize") }
                sizes.append((Int(w), Int(h)))
            }
            return sizes
        }
    }

    static func decode(_ data: Data, frameIndex: Int, applyProfile: Bool = true) throws -> Decoded {
        try withDecoder(data) { factory, decoder, count in
            guard frameIndex >= 0, frameIndex < count else { throw ImageDecodeError.corrupt("WIC: frame \(frameIndex) of \(count)") }
            let frame = try getFrame(decoder, frameIndex)
            let source = frame.cast(IWICBitmapSource.self)
            var w: UINT = 0, h: UINT = 0
            var hr = source.pointee.lpVtbl.pointee.GetSize(source, &w, &h)
            if hr < 0 { throw WIC.error(hr, "GetSize") }
            guard w > 0, h > 0, Int(w) <= 16384, Int(h) <= 16384, Int(w) * Int(h) * 4 <= 256 << 20 else { throw ImageDecodeError.unsupported("image \(w)x\(h) is over the decode limit") }
            var native = GUID()
            hr = source.pointee.lpVtbl.pointee.GetPixelFormat(source, &native)
            if hr < 0 { throw WIC.error(hr, "GetPixelFormat") }

            let profile = try embeddedProfile(factory, frame)
            let hasProfile = profile != nil && !ICCProfile.isSRGB(profile!)
            // 16-bit integer sources without a profile: take the 16-bit samples and reduce them with ImageIO's rule, round(v / 257) (measured on macOS 27: all 4096 grey and
            // 12288 RGB ramp samples); WIC's own 16 -> 8 bit conversion truncates (v >> 8) for RGB and differs again for grey, so it would not match the Mac.
            if isWideInteger(native), !(hasProfile && applyProfile) {
                let width = Int(w), height = Int(h)
                // Native 16bppGray, 48bppRGB and 64bppRGBA are read as they are (WIC's gray -> RGBA64 conversion moves some samples by one unit: 16 of 4096 on the grey ramp);
                // other wide formats (BGR order, premultiplied) go through the converter to straight 64bppRGBA.
                let channels = native.Data1 == 0x6fddc324 && native.Data4.7 == 0x0b ? 1 : (native.Data1 == 0x6fddc324 && native.Data4.7 == 0x15 ? 3 : 4)
                var keepWide: COMRef<IWICFormatConverter>?
                var ws = source
                if !(native.Data1 == 0x6fddc324 && [0x0b, 0x15, 0x16].contains(native.Data4.7)) { keepWide = try convert(factory, source, to: WIC.fmtRGBA64); ws = keepWide!.cast(IWICBitmapSource.self) }
                let ch = keepWide == nil ? channels : 4
                var samples = [UInt16](repeating: 0, count: width * height * ch)
                hr = samples.withUnsafeMutableBytes { p in ws.pointee.lpVtbl.pointee.CopyPixels(ws, nil, UINT(width * ch * 2), UINT(p.count), p.baseAddress?.assumingMemoryBound(to: BYTE.self)) }
                withExtendedLifetime(keepWide) {}
                if hr < 0 { throw WIC.error(hr, "CopyPixels(16-bit)") }
                var rgba = [UInt8](repeating: 255, count: width * height * 4)
                func reduce(_ v: UInt16) -> UInt8 { UInt8((Int(UInt16(littleEndian: v)) * 255 + 32767) / 65535) }
                for i in 0..<(width * height) {
                    switch ch {
                    case 1: let g = reduce(samples[i]); rgba[i * 4] = g; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = g
                    case 3: rgba[i * 4] = reduce(samples[i * 3]); rgba[i * 4 + 1] = reduce(samples[i * 3 + 1]); rgba[i * 4 + 2] = reduce(samples[i * 3 + 2])
                    default: for c in 0..<4 { rgba[i * 4 + c] = reduce(samples[i * 4 + c]) }
                    }
                }
                guard let image = RGBAImage(width: width, height: height, rgba: rgba) else { throw ImageDecodeError.corrupt("WIC: pixel buffer") }
                return Decoded(image: image, frameCount: count, transformedFromProfile: false, sourceFormat: describe(native) + "->16bit", profile: hasProfile ? profile : nil)
            }
            // 1. to 8-bit straight-alpha BGRA
            let converted = try convert(factory, source, to: WIC.fmtBGRA)
            var bitmap: UnsafeMutablePointer<IWICBitmapSource> = converted.cast(IWICBitmapSource.self)
            var keep: [AnyObject] = [converted]
            // 2. embedded ICC profile -> sRGB (WIC colour transform)
            var transformed = false
            if hasProfile, applyProfile, let profile {
                let xf = try colorTransform(factory, from: converted, profile: profile)
                bitmap = xf.cast(IWICBitmapSource.self)
                keep.append(xf)
                transformed = true
            }
            // 3. copy out, BGRA -> RGBA
            let width = Int(w), height = Int(h), stride = width * 4
            var bgra = [UInt8](repeating: 0, count: stride * height)
            hr = bgra.withUnsafeMutableBufferPointer { p in bitmap.pointee.lpVtbl.pointee.CopyPixels(bitmap, nil, UINT(stride), UINT(p.count), p.baseAddress) }
            withExtendedLifetime(keep) {}
            if hr < 0 { throw WIC.error(hr, "CopyPixels") }
            var i = 0
            while i < bgra.count { let b = bgra[i]; bgra[i] = bgra[i + 2]; bgra[i + 2] = b; i += 4 }
            guard let image = RGBAImage(width: width, height: height, rgba: bgra) else { throw ImageDecodeError.corrupt("WIC: pixel buffer") }
            return Decoded(image: image, frameCount: count, transformedFromProfile: transformed, sourceFormat: describe(native), profile: (hasProfile && !applyProfile) ? profile : nil)
        }
    }

    // MARK: - COM plumbing

    private static func withDecoder<R>(_ data: Data, _ body: (COMRef<IWICImagingFactory>, COMRef<IWICBitmapDecoder>, Int) throws -> R) throws -> R {
        var hr = CoInitializeEx(nil, DWORD(COINIT_MULTITHREADED.rawValue))
        let uninit = hr >= 0   // S_OK and S_FALSE both need a CoUninitialize; RPC_E_CHANGED_MODE does not
        if hr < 0 && hr != WIC.rpcChangedMode { throw ImageDecodeError.unsupported("WIC: CoInitializeEx \(WIC.describe(hr))") }
        defer { if uninit { CoUninitialize() } }

        var clsid = WIC.clsidFactory, iid = WIC.iidFactory
        var raw: UnsafeMutableRawPointer?
        hr = CoCreateInstance(&clsid, nil, DWORD(CLSCTX_INPROC_SERVER.rawValue), &iid, &raw)
        guard hr >= 0, let raw else { throw ImageDecodeError.unsupported("WIC: CoCreateInstance(CLSID_WICImagingFactory) \(WIC.describe(hr))") }
        let factory = COMRef(raw.assumingMemoryBound(to: IWICImagingFactory.self))

        // the stream reads this memory for as long as the decoder lives
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, data.count))
        defer { buffer.deallocate() }
        data.copyBytes(to: buffer, count: data.count)
        var streamPtr: UnsafeMutablePointer<IWICStream>?
        hr = factory.ptr.pointee.lpVtbl.pointee.CreateStream(factory.ptr, &streamPtr)
        guard hr >= 0, let streamPtr else { throw WIC.error(hr, "CreateStream") }
        let stream = COMRef(streamPtr)
        hr = stream.ptr.pointee.lpVtbl.pointee.InitializeFromMemory(stream.ptr, buffer, DWORD(data.count))
        if hr < 0 { throw WIC.error(hr, "InitializeFromMemory") }

        var decoderPtr: UnsafeMutablePointer<IWICBitmapDecoder>?
        hr = factory.ptr.pointee.lpVtbl.pointee.CreateDecoderFromStream(factory.ptr, stream.cast(IStream.self), nil, WICDecodeMetadataCacheOnDemand, &decoderPtr)
        guard hr >= 0, let decoderPtr else { throw WIC.error(hr, "CreateDecoderFromStream") }
        let decoder = COMRef(decoderPtr)
        var count: UINT = 0
        hr = decoder.ptr.pointee.lpVtbl.pointee.GetFrameCount(decoder.ptr, &count)
        if hr < 0 { throw WIC.error(hr, "GetFrameCount") }
        guard count > 0 else { throw ImageDecodeError.corrupt("WIC: no frames") }
        return try body(factory, decoder, Int(count))
    }

    private static func getFrame(_ decoder: COMRef<IWICBitmapDecoder>, _ index: Int) throws -> COMRef<IWICBitmapFrameDecode> {
        var frame: UnsafeMutablePointer<IWICBitmapFrameDecode>?
        let hr = decoder.ptr.pointee.lpVtbl.pointee.GetFrame(decoder.ptr, UINT(index), &frame)
        guard hr >= 0, let frame else { throw WIC.error(hr, "GetFrame") }
        return COMRef(frame)
    }

    private static func convert(_ factory: COMRef<IWICImagingFactory>, _ source: UnsafeMutablePointer<IWICBitmapSource>, to format: GUID) throws -> COMRef<IWICFormatConverter> {
        var conv: UnsafeMutablePointer<IWICFormatConverter>?
        var hr = factory.ptr.pointee.lpVtbl.pointee.CreateFormatConverter(factory.ptr, &conv)
        guard hr >= 0, let conv else { throw WIC.error(hr, "CreateFormatConverter") }
        let ref = COMRef(conv)
        var fmt = format
        hr = ref.ptr.pointee.lpVtbl.pointee.Initialize(ref.ptr, source, &fmt, WICBitmapDitherTypeNone, nil, 0, WICBitmapPaletteTypeCustom)
        if hr < 0 { throw WIC.error(hr, "FormatConverter.Initialize") }
        return ref
    }

    /// The first embedded colour context that holds an ICC profile (nil for untagged images and for EXIF colour space contexts).
    private static func embeddedProfile(_ factory: COMRef<IWICImagingFactory>, _ frame: COMRef<IWICBitmapFrameDecode>) throws -> [UInt8]? {
        var actual: UINT = 0
        var hr = frame.ptr.pointee.lpVtbl.pointee.GetColorContexts(frame.ptr, 0, nil, &actual)
        if hr < 0 || actual == 0 { return nil }
        var contexts: [COMRef<IWICColorContext>] = []
        var raws: [UnsafeMutablePointer<IWICColorContext>?] = []
        for _ in 0..<Int(actual) {
            var c: UnsafeMutablePointer<IWICColorContext>?
            hr = factory.ptr.pointee.lpVtbl.pointee.CreateColorContext(factory.ptr, &c)
            guard hr >= 0, let c else { return nil }
            contexts.append(COMRef(c)); raws.append(c)
        }
        var got: UINT = 0
        hr = raws.withUnsafeMutableBufferPointer { p in frame.ptr.pointee.lpVtbl.pointee.GetColorContexts(frame.ptr, actual, p.baseAddress, &got) }
        if hr < 0 { return nil }
        for c in contexts {
            var type = WICColorContextUninitialized
            hr = c.ptr.pointee.lpVtbl.pointee.GetType(c.ptr, &type)
            guard hr >= 0, type == WICColorContextProfile else { continue }
            var size: UINT = 0
            hr = c.ptr.pointee.lpVtbl.pointee.GetProfileBytes(c.ptr, 0, nil, &size)
            guard hr >= 0, size > 0 else { continue }
            var bytes = [UInt8](repeating: 0, count: Int(size))
            hr = bytes.withUnsafeMutableBufferPointer { p in c.ptr.pointee.lpVtbl.pointee.GetProfileBytes(c.ptr, size, p.baseAddress, &size) }
            if hr >= 0 { return bytes }
        }
        return nil
    }

    private static func colorTransform(_ factory: COMRef<IWICImagingFactory>, from source: COMRef<IWICFormatConverter>, profile: [UInt8]) throws -> COMRef<IWICColorTransform> {
        var srcPtr: UnsafeMutablePointer<IWICColorContext>?, dstPtr: UnsafeMutablePointer<IWICColorContext>?
        var hr = factory.ptr.pointee.lpVtbl.pointee.CreateColorContext(factory.ptr, &srcPtr)
        guard hr >= 0, let srcPtr else { throw WIC.error(hr, "CreateColorContext") }
        let src = COMRef(srcPtr)
        var mutable = profile
        // Rendering intent: WIC's colour transform takes it from the profile header (bytes 64-67). Diagnostic override for the I1 measurement: SWIFTRIGHT_WIC_INTENT = 0 perceptual,
        // 1 relative colorimetric, 2 saturation, 3 absolute colorimetric. Unset = the intent chosen in `ImageCodecWIC.defaultIntent` (docs/sr1-decisions.md G33).
        let intent = ProcessInfo.processInfo.environment["SWIFTRIGHT_WIC_INTENT"].flatMap { Int($0) } ?? defaultIntent
        if let intent, (0...3).contains(intent), mutable.count >= 68 { mutable[64] = 0; mutable[65] = 0; mutable[66] = 0; mutable[67] = UInt8(intent) }
        hr = mutable.withUnsafeMutableBufferPointer { p in src.ptr.pointee.lpVtbl.pointee.InitializeFromMemory(src.ptr, p.baseAddress, UINT(p.count)) }
        if hr < 0 { throw ImageDecodeError.corrupt("WIC: unreadable ICC profile \(WIC.describe(hr))") }
        hr = factory.ptr.pointee.lpVtbl.pointee.CreateColorContext(factory.ptr, &dstPtr)
        guard hr >= 0, let dstPtr else { throw WIC.error(hr, "CreateColorContext") }
        let dst = COMRef(dstPtr)
        hr = dst.ptr.pointee.lpVtbl.pointee.InitializeFromExifColorSpace(dst.ptr, 1)   // EXIF colour space 1 = sRGB
        if hr < 0 { throw WIC.error(hr, "InitializeFromExifColorSpace") }
        var xfPtr: UnsafeMutablePointer<IWICColorTransform>?
        hr = factory.ptr.pointee.lpVtbl.pointee.CreateColorTransformer(factory.ptr, &xfPtr)
        guard hr >= 0, let xfPtr else { throw WIC.error(hr, "CreateColorTransformer") }
        let xf = COMRef(xfPtr)
        var fmt = WIC.fmtBGRA
        hr = xf.ptr.pointee.lpVtbl.pointee.Initialize(xf.ptr, source.cast(IWICBitmapSource.self), src.ptr, dst.ptr, &fmt)
        if hr < 0 { throw WIC.error(hr, "ColorTransform.Initialize") }
        return xf
    }

    /// 16-bit-per-channel integer pixel formats (16bppGray, 48bppRGB/BGR, 64bppRGB/RGBA/BGRA/PRGBA/PBGRA), by the GUID's first field and last byte (values from wincodec.h).
    private static func isWideInteger(_ g: GUID) -> Bool {
        let wic: [UInt8] = [0x0b, 0x15, 0x16, 0x17]
        if g.Data1 == 0x6fddc324 { return wic.contains(g.Data4.7) }
        return (g.Data1 == 0xe605a384 && g.Data4.7 == 0x13) || (g.Data1 == 0xa1182111 && g.Data4.7 == 0xf9) || (g.Data1 == 0x1562ff7c && g.Data4.7 == 0x46) || (g.Data1 == 0x8c518e8e && g.Data4.7 == 0x30)
    }

    private static func describe(_ g: GUID) -> String {
        let table: [(GUID, String)] = [(WIC.fmtBGRA, "32bppBGRA"), (WIC.fmtBGR, "32bppBGR"), (WIC.fmtRGBA64, "64bppRGBA")]
        for (k, v) in table where k.Data1 == g.Data1 && k.Data2 == g.Data2 && k.Data4.7 == g.Data4.7 { return v }
        return String(g.Data1, radix: 16) + "-" + String(g.Data4.7, radix: 16)
    }
}
#endif
