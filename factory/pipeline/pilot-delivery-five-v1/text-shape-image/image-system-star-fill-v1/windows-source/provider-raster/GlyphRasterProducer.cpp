#define UNICODE
#define _UNICODE
#define NOMINMAX
#include <windows.h>
#include <dwrite_3.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cwchar>
#include <fstream>
#include <limits>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

void fail(const char* step, HRESULT hr = E_FAIL) {
    std::fprintf(stderr,
        "{\"status\":\"failed\",\"step\":\"%s\",\"hresult\":\"0x%08lx\"}\n",
        step, static_cast<unsigned long>(hr));
    std::exit(2);
}

void requireHr(HRESULT hr, const char* step) { if (FAILED(hr)) fail(step, hr); }

std::wstring utf8Path(const wchar_t* value) {
    if (!value || !*value) fail("missing-argument");
    return std::wstring(value);
}

std::string narrow(const std::wstring& value) {
    if (value.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                value.data(), static_cast<int>(value.size()),
                                nullptr, 0, nullptr, nullptr);
    if (n <= 0) fail("WideCharToMultiByte");
    std::string out(static_cast<size_t>(n), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                            value.data(), static_cast<int>(value.size()),
                            out.data(), n, nullptr, nullptr) != n) {
        fail("WideCharToMultiByte-write");
    }
    return out;
}

std::string jsonString(const std::string& value) {
    std::string out;
    out.reserve(value.size() + 2);
    out.push_back('"');
    for (unsigned char c : value) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20) {
                char buf[7]; std::snprintf(buf, sizeof(buf), "\\u%04x", c); out += buf;
            } else out.push_back(static_cast<char>(c));
        }
    }
    out.push_back('"');
    return out;
}

std::wstring familyName(IDWriteFontFamily* family) {
    ComPtr<IDWriteLocalizedStrings> names;
    requireHr(family->GetFamilyNames(&names), "GetFamilyNames");
    UINT32 index = 0; BOOL exists = FALSE;
    requireHr(names->FindLocaleName(L"en-us", &index, &exists), "FindFamilyLocale");
    if (!exists) index = 0;
    UINT32 length = 0;
    requireHr(names->GetStringLength(index, &length), "GetFamilyNameLength");
    std::wstring value(length + 1, L'\0');
    requireHr(names->GetString(index, value.data(), length + 1), "GetFamilyName");
    value.resize(length);
    return value;
}

std::wstring postScriptName(IDWriteFont* font) {
    ComPtr<IDWriteLocalizedStrings> names;
    BOOL exists = FALSE;
    requireHr(font->GetInformationalStrings(
        DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME, &names, &exists),
        "GetPostScriptName");
    if (!exists) return L"";
    UINT32 index = 0; BOOL locale = FALSE;
    requireHr(names->FindLocaleName(L"en-us", &index, &locale), "FindPostScriptLocale");
    if (!locale) index = 0;
    UINT32 length = 0;
    requireHr(names->GetStringLength(index, &length), "GetPostScriptNameLength");
    std::wstring value(length + 1, L'\0');
    requireHr(names->GetString(index, value.data(), length + 1), "GetPostScriptName");
    value.resize(length);
    return value;
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    // output RGBA, metadata JSON, font size DIP, expected font path, font SHA-256.
    if (argc != 6 && argc != 7) fail("usage");
    const std::wstring rgbaPath = utf8Path(argv[1]);
    const std::wstring metadataPath = utf8Path(argv[2]);
    const float emSize = static_cast<float>(std::wcstod(argv[3], nullptr));
    const std::wstring fontPath = utf8Path(argv[4]);
    const std::string fontSha256 = narrow(utf8Path(argv[5]));
    const bool faultEmptyCoverage = argc == 7 && std::wcscmp(argv[6], L"--fault-empty-coverage") == 0;
    if (argc == 7 && !faultEmptyCoverage) fail("unknown-fault-control");
    if (!(emSize > 0.0f) || !std::isfinite(emSize) || emSize > 512.0f) fail("font-size");
    if (fontSha256.size() != 64) fail("font-sha256");

    HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(init) && init != RPC_E_CHANGED_MODE) fail("CoInitializeEx", init);

    ComPtr<IDWriteFactory> factory;
    requireHr(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,
                                  __uuidof(IDWriteFactory), &factory),
              "DWriteCreateFactory-shared");
    ComPtr<IDWriteFontCollection> collection;
    requireHr(factory->GetSystemFontCollection(&collection, FALSE),
              "GetSystemFontCollection-read-only");
    UINT32 familyIndex = 0; BOOL familyExists = FALSE;
    requireHr(collection->FindFamilyName(L"Segoe Fluent Icons", &familyIndex, &familyExists),
              "FindFamilyName");
    if (!familyExists) fail("Segoe-Fluent-Icons-family-missing");
    ComPtr<IDWriteFontFamily> family;
    requireHr(collection->GetFontFamily(familyIndex, &family), "GetFontFamily");
    const std::wstring resolvedFamily = familyName(family.Get());
    if (resolvedFamily != L"Segoe Fluent Icons") fail("family-identity");
    ComPtr<IDWriteFont> font;
    requireHr(family->GetFirstMatchingFont(DWRITE_FONT_WEIGHT_NORMAL,
                                           DWRITE_FONT_STRETCH_NORMAL,
                                           DWRITE_FONT_STYLE_NORMAL, &font),
              "GetFirstMatchingFont");
    ComPtr<IDWriteFontFace> face;
    requireHr(font->CreateFontFace(&face), "CreateFontFace");

    // Bind caller's measured font file to exact system face reference key;
    // caller hash alone cannot establish provider identity.
    ComPtr<IDWriteFontFile> suppliedFile;
    requireHr(factory->CreateFontFileReference(fontPath.c_str(), nullptr, &suppliedFile),
              "CreateFontFileReference");
    UINT32 systemFileCount = 0;
    requireHr(face->GetFiles(&systemFileCount, nullptr), "GetSystemFaceFileCount");
    if (systemFileCount == 0 || systemFileCount > 16) fail("system-face-file-count");
    std::vector<IDWriteFontFile*> systemFiles(systemFileCount, nullptr);
    UINT32 requestedFiles = systemFileCount;
    requireHr(face->GetFiles(&requestedFiles, systemFiles.data()), "GetSystemFaceFiles");
    const void* suppliedKey = nullptr; UINT32 suppliedKeySize = 0;
    requireHr(suppliedFile->GetReferenceKey(&suppliedKey, &suppliedKeySize),
              "GetSuppliedFontReferenceKey");
    bool fontFileMatched = false;
    for (IDWriteFontFile* candidate : systemFiles) {
        const void* candidateKey = nullptr; UINT32 candidateKeySize = 0;
        if (candidate && SUCCEEDED(candidate->GetReferenceKey(&candidateKey, &candidateKeySize)) &&
            candidateKeySize == suppliedKeySize &&
            std::memcmp(candidateKey, suppliedKey, suppliedKeySize) == 0) {
            fontFileMatched = true;
        }
        if (candidate) candidate->Release();
    }
    if (!fontFileMatched) fail("font-file-not-system-face");

    UINT32 unicode = 0xE735;
    UINT16 glyph = 0;
    requireHr(face->GetGlyphIndices(&unicode, 1, &glyph), "GetGlyphIndices");
    if (glyph == 0) fail("FavoriteStarFill-glyph-missing");
    DWRITE_FONT_METRICS metrics{};
    face->GetMetrics(&metrics);
    DWRITE_GLYPH_METRICS glyphMetrics{};
    requireHr(face->GetDesignGlyphMetrics(&glyph, 1, &glyphMetrics, FALSE),
              "GetDesignGlyphMetrics");

    if (metrics.designUnitsPerEm == 0) fail("font-metrics-design-units");
    FLOAT advance = static_cast<FLOAT>(glyphMetrics.advanceWidth) * emSize /
                    static_cast<FLOAT>(metrics.designUnitsPerEm);
    DWRITE_GLYPH_OFFSET offset{};
    DWRITE_GLYPH_RUN run{};
    run.fontFace = face.Get();
    run.fontEmSize = emSize;
    run.glyphCount = 1;
    run.glyphIndices = &glyph;
    run.glyphAdvances = &advance;
    run.glyphOffsets = &offset;
    run.bidiLevel = 0;

    ComPtr<IDWriteGlyphRunAnalysis> analysis;
    requireHr(factory->CreateGlyphRunAnalysis(
        &run, 1.0f, nullptr, DWRITE_RENDERING_MODE_NATURAL,
        DWRITE_MEASURING_MODE_NATURAL, 0.0f, emSize, &analysis),
        "CreateGlyphRunAnalysis");
    constexpr DWRITE_TEXTURE_TYPE textureType = DWRITE_TEXTURE_CLEARTYPE_3x1;
    RECT bounds{};
    requireHr(analysis->GetAlphaTextureBounds(textureType, &bounds),
              "GetAlphaTextureBounds");
    const LONG width = bounds.right - bounds.left;
    const LONG height = bounds.bottom - bounds.top;
    if (width <= 0 || height <= 0 || width > 4096 || height > 4096) fail("texture-bounds");
    const size_t pixelCount = static_cast<size_t>(width) * static_cast<size_t>(height);
    if (pixelCount > (64u * 1024u * 1024u) / 4u) fail("texture-cap");
    std::vector<BYTE> alpha(pixelCount * 3u);
    requireHr(analysis->CreateAlphaTexture(textureType, &bounds,
                                           alpha.data(), static_cast<UINT32>(alpha.size())),
              "CreateAlphaTexture");
    std::vector<BYTE> rgba(pixelCount * 4);
    size_t nonZeroAlpha = 0;
    for (size_t i = 0; i < pixelCount; ++i) {
        const BYTE coverage = std::max(alpha[i * 3u], std::max(alpha[i * 3u + 1u], alpha[i * 3u + 2u]));
        if (coverage != 0) ++nonZeroAlpha;
        rgba[i * 4 + 0] = 0xFF;
        rgba[i * 4 + 1] = 0xCC;
        rgba[i * 4 + 2] = 0x00;
        rgba[i * 4 + 3] = coverage;
    }
    if (faultEmptyCoverage) {
        for (size_t i = 3; i < rgba.size(); i += 4) rgba[i] = 0;
        nonZeroAlpha = 0;
    }
    if (nonZeroAlpha == 0) fail("empty-coverage");
    {
        std::ofstream out(rgbaPath, std::ios::binary | std::ios::trunc);
        if (!out) fail("open-rgba");
        out.write(reinterpret_cast<const char*>(rgba.data()), static_cast<std::streamsize>(rgba.size()));
        if (!out) fail("write-rgba");
    }
    const std::string familyUtf8 = narrow(resolvedFamily);
    const std::string pathUtf8 = narrow(fontPath);
    const std::string psUtf8 = narrow(postScriptName(font.Get()));
    std::ofstream meta(metadataPath, std::ios::binary | std::ios::trunc);
    if (!meta) fail("open-metadata");
    meta << "{\n"
         << "  \"kind\":\"factory-system-image-provider-raster-v1\",\n"
         << "  \"identity\":\"star.fill\",\n"
         << "  \"provider\":\"Segoe Fluent Icons\",\n"
         << "  \"providerFamily\":" << jsonString(familyUtf8) << ",\n"
         << "  \"postScriptName\":" << jsonString(psUtf8) << ",\n"
         << "  \"fontPath\":" << jsonString(pathUtf8) << ",\n"
         << "  \"fontSha256\":" << jsonString("sha256:" + fontSha256) << ",\n"
         << "  \"fontFileMatched\":true,\n"
         << "  \"unicode\":\"E735\",\n"
         << "  \"glyphIndex\":" << glyph << ",\n"
         << "  \"fontEmSize\":" << emSize << ",\n"
         << "  \"fontMetrics\":{\"designUnitsPerEm\":" << metrics.designUnitsPerEm
         << ",\"ascent\":" << metrics.ascent << ",\"descent\":" << metrics.descent
         << ",\"lineGap\":" << metrics.lineGap << "},\n"
         << "  \"glyphMetrics\":{\"leftSideBearing\":" << glyphMetrics.leftSideBearing
         << ",\"advanceWidth\":" << glyphMetrics.advanceWidth
         << ",\"rightSideBearing\":" << glyphMetrics.rightSideBearing
         << ",\"topSideBearing\":" << glyphMetrics.topSideBearing
         << ",\"advanceHeight\":" << glyphMetrics.advanceHeight
         << ",\"bottomSideBearing\":" << glyphMetrics.bottomSideBearing << "},\n"
         << "  \"texture\":{\"type\":\"DWRITE_TEXTURE_CLEARTYPE_3X1\",\"left\":" << bounds.left
         << ",\"top\":" << bounds.top << ",\"right\":" << bounds.right
         << ",\"bottom\":" << bounds.bottom << ",\"width\":" << width
         << ",\"height\":" << height << "},\n"
         << "  \"rgbaBytes\":" << rgba.size() << ",\n"
         << "  \"nonZeroAlphaPixels\":" << nonZeroAlpha << ",\n"
         << "  \"rgbaSha256\":null,\n"
         << "  \"status\":\"producer-complete-pending-root-hash\"\n"
         << "}\n";
    if (!meta) fail("write-metadata");
    std::printf("{\"status\":\"produced\",\"identity\":\"star.fill\",\"family\":\"Segoe Fluent Icons\",\"glyph\":\"E735\",\"glyphIndex\":%u,\"width\":%ld,\"height\":%ld,\"rgbaBytes\":%zu,\"nonZeroAlphaPixels\":%zu}\n",
                glyph, width, height, rgba.size(), nonZeroAlpha);
    if (init == S_OK) CoUninitialize();
    return 0;
}
