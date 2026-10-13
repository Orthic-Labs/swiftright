#define UNICODE
#define _UNICODE
#include <windows.h>
#include <dwrite_3.h>
#include <wrl/client.h>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <cwchar>

using Microsoft::WRL::ComPtr;

static constexpr wchar_t kPinnedTinosSha[] =
    L"sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61";

static std::wstring arg(int argc, wchar_t** argv, int index, const wchar_t* fallback) {
    return argc > index ? argv[index] : fallback;
}

static std::wstring jsonString(const std::wstring& value) {
    static constexpr wchar_t hex[] = L"0123456789abcdef";
    std::wstring out = L"\"";
    for (wchar_t ch : value) {
        switch (ch) {
            case L'\\': out += L"\\\\"; break;
            case L'\"': out += L"\\\""; break;
            case L'\b': out += L"\\b"; break;
            case L'\f': out += L"\\f"; break;
            case L'\n': out += L"\\n"; break;
            case L'\r': out += L"\\r"; break;
            case L'\t': out += L"\\t"; break;
            default:
                if (ch < 0x20) {
                    out += L"\\u00";
                    out += hex[(static_cast<unsigned int>(ch) >> 4) & 0x0f];
                    out += hex[static_cast<unsigned int>(ch) & 0x0f];
                } else {
                    out += ch;
                }
                break;
        }
    }
    out += L'\"';
    return out;
}

static void check(HRESULT hr, const char* step) {
    if (FAILED(hr)) throw std::runtime_error(step);
}

static bool systemHasFamily(IDWriteFactory* factory, const std::wstring& family, BOOL checkForUpdates) {
    ComPtr<IDWriteFontCollection> collection;
    check(factory->GetSystemFontCollection(&collection, checkForUpdates), "GetSystemFontCollection");
    UINT32 index = 0;
    BOOL exists = FALSE;
    check(collection->FindFamilyName(family.c_str(), &index, &exists), "FindFamilyName");
    return exists != FALSE;
}

static std::wstring privateFamily(IDWriteFontCollection* collection) {
    if (collection->GetFontFamilyCount() != 1) return L"";
    ComPtr<IDWriteFontFamily> family;
    check(collection->GetFontFamily(0, &family), "GetFontFamily");
    ComPtr<IDWriteLocalizedStrings> names;
    check(family->GetFamilyNames(&names), "GetFamilyNames");
    UINT32 index = 0;
    BOOL exists = FALSE;
    check(names->FindLocaleName(L"en-us", &index, &exists), "FindFamilyLocale");
    if (!exists) index = 0;
    UINT32 length = 0;
    check(names->GetStringLength(index, &length), "GetFamilyNameLength");
    std::wstring value(length + 1, L'\0');
    check(names->GetString(index, value.data(), length + 1), "GetFamilyName");
    value.resize(length);
    return value;
}

static std::wstring privatePostScript(IDWriteFontCollection* collection) {
    if (collection->GetFontFamilyCount() != 1) return L"";
    ComPtr<IDWriteFontFamily> family;
    check(collection->GetFontFamily(0, &family), "GetFontFamilyForPostScript");
    ComPtr<IDWriteFont> font;
    check(family->GetFirstMatchingFont(DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL, &font), "GetFirstMatchingFont");
    ComPtr<IDWriteLocalizedStrings> names;
    BOOL exists = FALSE;
    check(font->GetInformationalStrings(DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME, &names, &exists), "GetPostScriptName");
    if (!exists) return L"";
    UINT32 index = 0; BOOL locale = FALSE;
    check(names->FindLocaleName(L"en-us", &index, &locale), "FindPostScriptLocale");
    if (!locale) index = 0;
    UINT32 length = 0;
    check(names->GetStringLength(index, &length), "GetPostScriptNameLength");
    std::wstring value(length + 1, L'\0');
    check(names->GetString(index, value.data(), length + 1), "ReadPostScriptName");
    value.resize(length);
    return value;
}

class TemporaryFontRegistration final {
public:
    TemporaryFontRegistration(const std::wstring& path, DWORD flags) : path_(path), flags_(flags) {}
    int add() { count_ = AddFontResourceExW(path_.c_str(), flags_, nullptr); return count_; }
    bool removeNow() {
        if (count_ <= 0) return true;
        if (!RemoveFontResourceExW(path_.c_str(), flags_, nullptr)) return false;
        count_ = 0;
        return true;
    }
    ~TemporaryFontRegistration() { removeNow(); }
private:
    std::wstring path_;
    DWORD flags_;
    int count_ = 0;
};

int wmain(int argc, wchar_t** argv) {
    const std::wstring fontPath = arg(argc, argv, 1, L"Tinos-Regular.ttf");
    const std::wstring expectedFamily = arg(argc, argv, 2, L"Tinos");
    const std::wstring expectedPostScript = arg(argc, argv, 3, L"Tinos-Regular");
    const std::wstring suppliedSha = arg(argc, argv, 4, kPinnedTinosSha);
    if (fontPath.size() > 32768 || expectedFamily.size() > 256 || expectedPostScript.size() > 256 || suppliedSha.size() > 80) {
        std::fwprintf(stderr, L"{\"status\":\"failed\",\"reason\":\"argument-size-limit\"}\n");
        return 2;
    }
    if (suppliedSha != kPinnedTinosSha) {
        std::fwprintf(stderr, L"{\"status\":\"failed\",\"reason\":\"pinned-tinos-sha-mismatch\"}\n");
        return 3;
    }

    try {
        ComPtr<IDWriteFactory> shared;
        check(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), &shared), "DWriteCreateFactory-shared");
        const bool beforeFalse = systemHasFamily(shared.Get(), expectedFamily, FALSE);
        const bool beforeTrue = systemHasFamily(shared.Get(), expectedFamily, TRUE);

        TemporaryFontRegistration nonPrivate(fontPath, 0);
        const int nonPrivateCount = nonPrivate.add();
        const bool nonPrivateFalse = systemHasFamily(shared.Get(), expectedFamily, FALSE);
        const bool nonPrivateTrue = systemHasFamily(shared.Get(), expectedFamily, TRUE);
        const bool nonPrivateRemoved = nonPrivate.removeNow();
        if (!nonPrivateRemoved) throw std::runtime_error("RemoveFontResourceExW-flags-0");

        TemporaryFontRegistration privateRegistration(fontPath, FR_PRIVATE);
        const int privateCount = privateRegistration.add();
        const bool privateFalse = systemHasFamily(shared.Get(), expectedFamily, FALSE);
        const bool privateTrue = systemHasFamily(shared.Get(), expectedFamily, TRUE);
        const bool privateRemoved = privateRegistration.removeNow();
        if (!privateRemoved) throw std::runtime_error("RemoveFontResourceExW-FR_PRIVATE");

        ComPtr<IDWriteFactory> isolatedBase;
        check(DWriteCreateFactory(DWRITE_FACTORY_TYPE_ISOLATED, __uuidof(IDWriteFactory), &isolatedBase), "DWriteCreateFactory-isolated");
        ComPtr<IDWriteFactory6> isolated;
        check(isolatedBase.As(&isolated), "QueryInterface-IDWriteFactory6");
        ComPtr<IDWriteFontSetBuilder> builderBase;
        check(isolated->CreateFontSetBuilder(&builderBase), "CreateFontSetBuilder");
        ComPtr<IDWriteFontSetBuilder2> builder;
        check(builderBase.As(&builder), "QueryInterface-IDWriteFontSetBuilder2");
        check(builder->AddFontFile(fontPath.c_str()), "AddFontFile-private-path");
        ComPtr<IDWriteFontSet> fontSet;
        check(builder->CreateFontSet(&fontSet), "CreateFontSet");
        ComPtr<IDWriteFontCollection2> isolatedCollection;
        check(isolated->CreateFontCollectionFromFontSet(fontSet.Get(), DWRITE_FONT_FAMILY_MODEL_TYPOGRAPHIC, &isolatedCollection), "CreateFontCollectionFromFontSet");
        const std::wstring isolatedName = privateFamily(isolatedCollection.Get());
        const std::wstring isolatedPostScript = privatePostScript(isolatedCollection.Get());
        const bool isolatedPositive = isolatedName == expectedFamily && isolatedPostScript == expectedPostScript && fontSet->GetFontCount() == 1;

        const std::wstring output =
            L"{\"status\":\"probe\",\"fontPath\":" + jsonString(fontPath) +
            L",\"resourceSha256\":" + jsonString(suppliedSha) +
            L",\"expectedFamily\":" + jsonString(expectedFamily) +
            L",\"expectedPostScript\":" + jsonString(expectedPostScript) +
            L",\"nonPrivateFlags\":0,\"nonPrivateCount\":" + std::to_wstring(nonPrivateCount) +
            L",\"nonPrivateSystemFalse\":" + (nonPrivateFalse ? L"true" : L"false") +
            L",\"nonPrivateSystemTrue\":" + (nonPrivateTrue ? L"true" : L"false") +
            L",\"beforeSystemFalse\":" + (beforeFalse ? L"true" : L"false") +
            L",\"beforeSystemTrue\":" + (beforeTrue ? L"true" : L"false") +
            L",\"privateFlags\":" + std::to_wstring(static_cast<unsigned long>(FR_PRIVATE)) +
            L",\"privateCount\":" + std::to_wstring(privateCount) +
            L",\"privateSystemFalse\":" + (privateFalse ? L"true" : L"false") +
            L",\"privateSystemTrue\":" + (privateTrue ? L"true" : L"false") +
            L",\"isolatedFamily\":" + jsonString(isolatedName) +
            L",\"isolatedPostScript\":" + jsonString(isolatedPostScript) +
            L",\"isolatedPositive\":" + (isolatedPositive ? L"true" : L"false") +
            L",\"nonPrivateRemoved\":" + (nonPrivateRemoved ? L"true" : L"false") +
            L",\"privateRemoved\":" + (privateRemoved ? L"true" : L"false") +
            L",\"cleanup\":\"RemoveFontResourceExW paired for flags 0 and FR_PRIVATE\"}";
        std::wprintf(L"%ls\n", output.c_str());
        return (nonPrivateCount > 0 && privateCount > 0 && isolatedPositive && nonPrivateRemoved && privateRemoved) ? 0 : 4;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "{\"status\":\"failed\",\"step\":\"%s\"}\n", error.what());
        return 5;
    }
}
