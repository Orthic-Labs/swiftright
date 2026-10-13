#define UNICODE
#define _UNICODE
#include <windows.h>
#include <dwrite_3.h>
#include <wrl/client.h>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <cwchar>

using Microsoft::WRL::ComPtr;

static void check(HRESULT hr, const char* step) {
    if (FAILED(hr)) {
        std::fprintf(stderr, "{\"status\":\"failed\",\"step\":\"%s\",\"hresult\":\"0x%08lx\"}\n", step, static_cast<unsigned long>(hr));
        std::exit(2);
    }
}

static std::wstring read_arg(int argc, wchar_t** argv, int index, const wchar_t* fallback) {
    return argc > index ? argv[index] : fallback;
}

int wmain(int argc, wchar_t** argv) {
    const std::wstring fontPath = read_arg(argc, argv, 1, L"Tinos-Regular.ttf");
    const std::wstring expectedPs = read_arg(argc, argv, 2, L"Tinos-Regular");
    const std::wstring expectedFamily = read_arg(argc, argv, 3, L"Tinos");

    ComPtr<IDWriteFactory> baseFactory;
    check(DWriteCreateFactory(DWRITE_FACTORY_TYPE_ISOLATED, __uuidof(IDWriteFactory), &baseFactory), "DWriteCreateFactory-isolated");
    ComPtr<IDWriteFactory6> factory;
    check(baseFactory.As(&factory), "QueryInterface-IDWriteFactory6");

    ComPtr<IDWriteFontSetBuilder> builderBase;
    check(factory->CreateFontSetBuilder(&builderBase), "CreateFontSetBuilder");
    ComPtr<IDWriteFontSetBuilder2> builder;
    check(builderBase.As(&builder), "QueryInterface-IDWriteFontSetBuilder2");
    check(builder->AddFontFile(fontPath.c_str()), "AddFontFile-private-path");

    ComPtr<IDWriteFontSet> fontSet;
    check(builder->CreateFontSet(&fontSet), "CreateFontSet");
    ComPtr<IDWriteFontCollection2> collection;
    check(factory->CreateFontCollectionFromFontSet(fontSet.Get(), DWRITE_FONT_FAMILY_MODEL_TYPOGRAPHIC, &collection), "CreateFontCollectionFromFontSet");

    ComPtr<IDWriteFontCollection> systemCollection;
    check(factory->GetSystemFontCollection(&systemCollection, FALSE), "GetSystemFontCollection-read-only");
    UINT32 systemFamilyIndex = 0;
    BOOL systemFamilyPresent = FALSE;
    check(systemCollection->FindFamilyName(L"Tinos", &systemFamilyIndex, &systemFamilyPresent), "FindTinosInSystemCollection");

    const UINT32 familyCount = collection->GetFontFamilyCount();
    if (familyCount != 1) {
        std::fprintf(stderr, "{\"status\":\"failed\",\"step\":\"private-family-count\",\"actual\":%u}\n", familyCount);
        return 3;
    }
    ComPtr<IDWriteFontFamily> family;
    check(collection->GetFontFamily(0, &family), "GetFontFamily");
    ComPtr<IDWriteLocalizedStrings> names;
    check(family->GetFamilyNames(&names), "GetFamilyNames");
    UINT32 localeIndex = 0;
    BOOL exists = FALSE;
    check(names->FindLocaleName(L"en-us", &localeIndex, &exists), "FindLocaleName");
    if (!exists) localeIndex = 0;
    UINT32 familyLength = 0;
    check(names->GetStringLength(localeIndex, &familyLength), "GetFamilyNameLength");
    std::wstring familyName(familyLength + 1, L'\0');
    check(names->GetString(localeIndex, familyName.data(), familyLength + 1), "GetFamilyName");
    familyName.resize(familyLength);
    if (familyName != expectedFamily) {
        std::fprintf(stderr, "{\"status\":\"failed\",\"step\":\"private-family-name\"}\n");
        return 4;
    }

    ComPtr<IDWriteFont> font;
    check(family->GetFirstMatchingFont(DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL, &font), "GetFirstMatchingFont");
    ComPtr<IDWriteFontFace> face;
    check(font->CreateFontFace(&face), "CreateFontFace");
    ComPtr<IDWriteLocalizedStrings> psNames;
    BOOL psExists = FALSE;
    check(font->GetInformationalStrings(DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME, &psNames, &psExists), "GetPostScriptName");
    if (!psExists) return 5;
    check(psNames->FindLocaleName(L"en-us", &localeIndex, &exists), "FindPostScriptLocale");
    if (!exists) localeIndex = 0;
    UINT32 psLength = 0;
    check(psNames->GetStringLength(localeIndex, &psLength), "GetPostScriptNameLength");
    std::wstring postScript(psLength + 1, L'\0');
    check(psNames->GetString(localeIndex, postScript.data(), psLength + 1), "ReadPostScriptName");
    postScript.resize(psLength);
    if (postScript != expectedPs) {
        std::fprintf(stderr, "{\"status\":\"failed\",\"step\":\"private-postscript-name\"}\n");
        return 6;
    }

    DWRITE_FONT_METRICS metrics{};
    face->GetMetrics(&metrics);
    const wchar_t sample[] = L"Tinos font metrics";
    UINT16 glyphs[sizeof(sample) / sizeof(sample[0])]{};
    check(face->GetGlyphIndices(reinterpret_cast<const UINT32*>(sample), static_cast<UINT32>(wcslen(sample)), glyphs), "GetGlyphIndices");
    DWRITE_GLYPH_METRICS glyphMetrics[sizeof(sample) / sizeof(sample[0])]{};
    face->GetDesignGlyphMetrics(glyphs, static_cast<UINT32>(wcslen(sample)), glyphMetrics, FALSE);
    long long advance = 0;
    for (size_t i = 0; i < wcslen(sample); ++i) advance += glyphMetrics[i].advanceWidth;

    ComPtr<IDWriteTextFormat> format;
    check(factory->CreateTextFormat(familyName.c_str(), collection.Get(), DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, 18.0f, L"en-us", &format), "CreateTextFormat-private-collection");
    ComPtr<IDWriteTextLayout> layout;
    check(factory->CreateTextLayout(sample, static_cast<UINT32>(wcslen(sample)), format.Get(), 240.0f, 80.0f, &layout), "CreateTextLayout");
    DWRITE_TEXT_METRICS textMetrics{};
    check(layout->GetMetrics(&textMetrics), "GetTextMetrics");
    if (metrics.designUnitsPerEm == 0 || advance <= 0 || textMetrics.width <= 0 || textMetrics.height <= 0) return 7;

    std::wprintf(L"{\"status\":\"qualified\",\"factoryType\":\"isolated\",\"collectionScope\":\"process-local custom font set\",\"family\":\"%ls\",\"postScriptName\":\"%ls\",\"familyCount\":%u,\"faceCount\":%u,\"systemFamilyPresent\":%s,\"designUnitsPerEm\":%u,\"ascent\":%u,\"descent\":%u,\"lineGap\":%d,\"sample\":\"Tinos font metrics\",\"glyphCount\":%zu,\"designAdvanceSum\":%lld,\"textLayoutWidth\":%.3f,\"textLayoutHeight\":%.3f,\"systemInstallOrGlobalRegistration\":false}\n", familyName.c_str(), postScript.c_str(), familyCount, fontSet->GetFontCount(), systemFamilyPresent ? L"true" : L"false", metrics.designUnitsPerEm, metrics.ascent, metrics.descent, metrics.lineGap, wcslen(sample), advance, textMetrics.width, textMetrics.height);
    return 0;
}
