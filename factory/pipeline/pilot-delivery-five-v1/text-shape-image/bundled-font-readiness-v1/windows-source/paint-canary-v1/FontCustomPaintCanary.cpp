#define UNICODE
#define _UNICODE
#define NOMINMAX
#include <windows.h>
#include <dwrite_3.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {
void fail(const char* step, HRESULT hr = E_FAIL) {
    std::fprintf(stderr, "{\"status\":\"held\",\"step\":\"%s\",\"hresult\":\"0x%08lx\"}\n", step, static_cast<unsigned long>(hr));
    std::exit(2);
}
void ok(HRESULT hr, const char* step) { if (FAILED(hr)) fail(step, hr); }
std::wstring arg(int argc, wchar_t** argv, int index) {
    if (argc <= index || !argv[index] || !*argv[index]) fail("argument-missing");
    return argv[index];
}
std::string narrow(const std::wstring& value) {
    int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (n <= 0) fail("utf8-conversion");
    std::string out(static_cast<size_t>(n), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), out.data(), n, nullptr, nullptr) != n) fail("utf8-write");
    return out;
}
std::string js(const std::string& value) {
    std::string out = "\"";
    for (unsigned char c : value) {
        if (c == '\\') out += "\\\\";
        else if (c == '"') out += "\\\"";
        else if (c == '\n') out += "\\n";
        else out.push_back(static_cast<char>(c));
    }
    return out + "\"";
}
std::wstring localized(IDWriteLocalizedStrings* names) {
    UINT32 index = 0; BOOL exists = FALSE; ok(names->FindLocaleName(L"en-us", &index, &exists), "FindLocaleName");
    if (!exists) index = 0;
    UINT32 length = 0; ok(names->GetStringLength(index, &length), "GetStringLength");
    std::wstring out(length + 1, L'\0'); ok(names->GetString(index, out.data(), length + 1), "GetString"); out.resize(length); return out;
}
std::wstring familyName(IDWriteFontFamily* family) {
    ComPtr<IDWriteLocalizedStrings> names; ok(family->GetFamilyNames(&names), "GetFamilyNames"); return localized(names.Get());
}
std::wstring postScriptName(IDWriteFont* font) {
    ComPtr<IDWriteLocalizedStrings> names; BOOL exists = FALSE;
    ok(font->GetInformationalStrings(DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME, &names, &exists), "GetPostScriptName");
    if (!exists) fail("postscript-name-missing");
    return localized(names.Get());
}
}

int wmain(int argc, wchar_t** argv) {
    // font path, expected SHA-256, raw RGBA output, metadata output, size DIP.
    if (argc != 6 && argc != 7) fail("usage");
    const std::wstring fontPath = arg(argc, argv, 1);
    const std::string resourceSha = narrow(arg(argc, argv, 2));
    const std::wstring rgbaPath = arg(argc, argv, 3);
    const std::wstring metadataPath = arg(argc, argv, 4);
    const float emSize = static_cast<float>(std::wcstod(arg(argc, argv, 5).c_str(), nullptr));
    const bool faultEmptyCoverage = argc == 7 && arg(argc, argv, 6) == L"--fault-empty-coverage";
    if (argc == 7 && !faultEmptyCoverage) fail("unknown-fault-control");
    if (resourceSha.size() != 71 || resourceSha.rfind("sha256:", 0) != 0 || !std::isfinite(emSize) || emSize != 18.0f) fail("input-contract");

    HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(init) && init != RPC_E_CHANGED_MODE) fail("CoInitializeEx", init);
    ComPtr<IDWriteFactory> base;
    ok(DWriteCreateFactory(DWRITE_FACTORY_TYPE_ISOLATED, __uuidof(IDWriteFactory), &base), "DWriteCreateFactory-isolated");
    ComPtr<IDWriteFactory6> factory; ok(base.As(&factory), "QueryInterface-IDWriteFactory6");
    ComPtr<IDWriteFontSetBuilder> builderBase; ok(factory->CreateFontSetBuilder(&builderBase), "CreateFontSetBuilder");
    ComPtr<IDWriteFontSetBuilder2> builder; ok(builderBase.As(&builder), "QueryInterface-IDWriteFontSetBuilder2");
    ok(builder->AddFontFile(fontPath.c_str()), "AddFontFile-exact-resource");
    ComPtr<IDWriteFontSet> set; ok(builder->CreateFontSet(&set), "CreateFontSet");
    ComPtr<IDWriteFontCollection2> collection; ok(factory->CreateFontCollectionFromFontSet(set.Get(), DWRITE_FONT_FAMILY_MODEL_TYPOGRAPHIC, &collection), "CreateFontCollectionFromFontSet");
    if (collection->GetFontFamilyCount() != 1) fail("custom-family-count");
    ComPtr<IDWriteFontFamily> family; ok(collection->GetFontFamily(0, &family), "GetFontFamily");
    const std::wstring familyText = familyName(family.Get()); if (familyText != L"Tinos") fail("family-identity");
    ComPtr<IDWriteFont> font; ok(family->GetFirstMatchingFont(DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL, &font), "GetFirstMatchingFont");
    const std::wstring psText = postScriptName(font.Get()); if (psText != L"Tinos-Regular") fail("postscript-identity");
    ComPtr<IDWriteFontFace> face; ok(font->CreateFontFace(&face), "CreateFontFace");
    DWRITE_FONT_METRICS fm{}; face->GetMetrics(&fm); if (fm.designUnitsPerEm == 0) fail("font-metrics");

    const std::wstring sample = L"SwiftRight bundled Tinos font witness";
    std::vector<UINT32> codepoints(sample.begin(), sample.end());
    std::vector<UINT16> glyphs(codepoints.size()); ok(face->GetGlyphIndices(codepoints.data(), static_cast<UINT32>(codepoints.size()), glyphs.data()), "GetGlyphIndices");
    for (UINT16 glyph : glyphs) if (glyph == 0) fail("missing-sample-glyph");
    if (fm.designUnitsPerEm == 0) fail("font-metrics-design-units");
    std::vector<DWRITE_GLYPH_METRICS> glyphMetrics(glyphs.size());
    ok(face->GetDesignGlyphMetrics(glyphs.data(), static_cast<UINT32>(glyphs.size()), glyphMetrics.data(), FALSE), "GetDesignGlyphMetrics");
    std::vector<FLOAT> advances(glyphs.size());
    const FLOAT scale = emSize / static_cast<FLOAT>(fm.designUnitsPerEm);
    for (size_t i = 0; i < advances.size(); ++i) advances[i] = static_cast<FLOAT>(glyphMetrics[i].advanceWidth) * scale;
    FLOAT totalAdvance = 0.0f; for (FLOAT advance : advances) totalAdvance += advance * scale;
    const LONG width = static_cast<LONG>(std::ceil(totalAdvance)) + 8; const LONG height = static_cast<LONG>(std::ceil((fm.ascent + fm.descent) * scale)) + 8;
    if (width <= 0 || height <= 0 || width > 4096 || height > 512) fail("paint-bounds");
    std::vector<BYTE> rgba(static_cast<size_t>(width) * static_cast<size_t>(height) * 4, 0);
    size_t nonZeroAlpha = 0; size_t nonEmptyGlyphs = 0; size_t clippedCoverage = 0;
    FLOAT x = 4.0f; const FLOAT baseline = 4.0f + static_cast<FLOAT>(fm.ascent) * scale;
    for (size_t i = 0; i < glyphs.size(); ++i) {
        DWRITE_GLYPH_RUN run{}; run.fontFace = face.Get(); run.fontEmSize = emSize; run.glyphCount = 1; run.glyphIndices = &glyphs[i];
        FLOAT advance = advances[i] * scale; run.glyphAdvances = &advance; DWRITE_GLYPH_OFFSET offset{}; run.glyphOffsets = &offset;
        ComPtr<IDWriteGlyphRunAnalysis> analysis; ok(factory->CreateGlyphRunAnalysis(&run, 1.0f, nullptr, DWRITE_RENDERING_MODE_NATURAL, DWRITE_MEASURING_MODE_NATURAL, x, baseline, &analysis), "CreateGlyphRunAnalysis");
        constexpr DWRITE_TEXTURE_TYPE textureType = DWRITE_TEXTURE_CLEARTYPE_3x1;
        RECT bounds{}; ok(analysis->GetAlphaTextureBounds(textureType, &bounds), "GetAlphaTextureBounds");
        LONG tw = bounds.right - bounds.left, th = bounds.bottom - bounds.top; if (tw < 0 || th < 0 || tw > width || th > height || bounds.left < 0 || bounds.top < 0 || bounds.right > width || bounds.bottom > height) fail("glyph-texture-bounds");
        if (tw == 0 || th == 0) { x += advance; continue; }
        ++nonEmptyGlyphs;
        std::vector<BYTE> alpha(static_cast<size_t>(tw) * static_cast<size_t>(th) * 3u); ok(analysis->CreateAlphaTexture(textureType, &bounds, alpha.data(), static_cast<UINT32>(alpha.size())), "CreateAlphaTexture");
        for (LONG py = 0; py < th; ++py) for (LONG px = 0; px < tw; ++px) {
            size_t source = (static_cast<size_t>(py) * static_cast<size_t>(tw) + static_cast<size_t>(px)) * 3u;
            BYTE a = std::max(alpha[source], std::max(alpha[source + 1u], alpha[source + 2u]));
            LONG dx = bounds.left + px, dy = bounds.top + py; if (dx < 0 || dx >= width || dy < 0 || dy >= height) { if (a != 0) ++clippedCoverage; continue; }
            if (a != 0) ++nonZeroAlpha;
            size_t dst = (static_cast<size_t>(dy) * static_cast<size_t>(width) + static_cast<size_t>(dx)) * 4;
            rgba[dst + 0] = 0; rgba[dst + 1] = 0; rgba[dst + 2] = 0; rgba[dst + 3] = rgba[dst + 3] > a ? rgba[dst + 3] : a;
        }
        x += advance;
    }
    if (clippedCoverage != 0) fail("coverage-clipped");
    if (faultEmptyCoverage) {
        for (size_t i = 3; i < rgba.size(); i += 4) rgba[i] = 0;
        nonZeroAlpha = 0;
    }
    if (nonEmptyGlyphs == 0 || nonZeroAlpha == 0) fail("empty-coverage");
    std::ofstream raw(rgbaPath, std::ios::binary | std::ios::trunc); if (!raw) fail("open-rgba"); raw.write(reinterpret_cast<const char*>(rgba.data()), static_cast<std::streamsize>(rgba.size())); if (!raw) fail("write-rgba");
    std::ofstream meta(metadataPath, std::ios::binary | std::ios::trunc); if (!meta) fail("open-metadata");
    meta << "{\n  \"kind\":\"factory-bundled-font-paint-canary-v1\",\n  \"fontPath\":" << js(narrow(fontPath)) << ",\n  \"resourceSha256\":" << js(resourceSha) << ",\n  \"family\":\"Tinos\",\n  \"postScriptName\":\"Tinos-Regular\",\n  \"fontFileSelection\":\"isolated-custom-font-set\",\n  \"text\":" << js(narrow(sample)) << ",\n  \"fontSizeDIP\":18,\n  \"designUnitsPerEm\":" << fm.designUnitsPerEm << ",\n  \"ascent\":" << fm.ascent << ",\n  \"descent\":" << fm.descent << ",\n  \"lineGap\":" << fm.lineGap << ",\n  \"glyphCount\":" << glyphs.size() << ",\n  \"width\":" << width << ",\n  \"height\":" << height << ",\n  \"rgbaBytes\":" << rgba.size() << ",\n  \"nonEmptyGlyphs\":" << nonEmptyGlyphs << ",\n  \"nonZeroAlphaPixels\":" << nonZeroAlpha << ",\n  \"rendererSelection\":\"unproven\",\n  \"bridgeMeasurementSelection\":\"unproven\"\n}\n";
    if (!meta) fail("write-metadata");
    std::printf("{\"status\":\"paint-canary-produced\",\"family\":\"Tinos\",\"postScriptName\":\"Tinos-Regular\",\"glyphCount\":%zu,\"width\":%ld,\"height\":%ld,\"rendererSelection\":\"unproven\",\"bridgeMeasurementSelection\":\"unproven\"}\n", glyphs.size(), width, height);
    if (init == S_OK) CoUninitialize(); return 0;
}
