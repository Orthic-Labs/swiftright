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
static std::wstring arg(int argc, wchar_t** argv, int index, const wchar_t* fallback) {
    return argc > index ? argv[index] : fallback;
}
static std::wstring familyName(IDWriteFontCollection* collection) {
    if (collection->GetFontFamilyCount() == 0) return L"";
    ComPtr<IDWriteFontFamily> family;
    check(collection->GetFontFamily(0, &family), "GetFontFamily");
    ComPtr<IDWriteLocalizedStrings> names;
    check(family->GetFamilyNames(&names), "GetFamilyNames");
    UINT32 index = 0; BOOL exists = FALSE;
    check(names->FindLocaleName(L"en-us", &index, &exists), "FindFamilyLocale");
    if (!exists) index = 0;
    UINT32 length = 0;
    check(names->GetStringLength(index, &length), "GetFamilyNameLength");
    std::wstring value(length + 1, L'\0');
    check(names->GetString(index, value.data(), length + 1), "GetFamilyName");
    value.resize(length);
    return value;
}
static std::wstring postScriptName(IDWriteFontCollection* collection) {
    if (collection->GetFontFamilyCount() == 0) return L"";
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
int wmain(int argc, wchar_t** argv) {
    const std::wstring fontPath = arg(argc, argv, 1, L"Tinos-Regular.ttf");
    const std::wstring expectedFamily = arg(argc, argv, 2, L"Tinos");
    const std::wstring expectedPS = arg(argc, argv, 3, L"Tinos-Regular");
    const std::wstring hwndText = arg(argc, argv, 4, L"0");
    const std::wstring resourceSha = arg(argc, argv, 5, L"sha256:UNBOUND");
    HWND hwnd = reinterpret_cast<HWND>(static_cast<UINT_PTR>(std::wcstoull(hwndText.c_str(), nullptr, 0)));
    RECT client{};
    if (hwnd == nullptr || !GetClientRect(hwnd, &client)) {
        std::fprintf(stderr, "{\"status\":\"held\",\"reason\":\"GetClientRect-unavailable\"}\n");
        return 8;
    }

    // FR_PRIVATE is process-scoped GDI registration. It must not be treated as renderer proof.
    const int privateAdded = AddFontResourceExW(fontPath.c_str(), FR_PRIVATE, nullptr);
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
    ComPtr<IDWriteFontCollection2> privateCollection;
    check(factory->CreateFontCollectionFromFontSet(fontSet.Get(), DWRITE_FONT_FAMILY_MODEL_TYPOGRAPHIC, &privateCollection), "CreateFontCollectionFromFontSet");

    ComPtr<IDWriteFontCollection> systemCollection;
    check(factory->GetSystemFontCollection(&systemCollection, FALSE), "GetSystemFontCollection-read-only");
    UINT32 familyIndex = 0; BOOL systemPresent = FALSE;
    check(systemCollection->FindFamilyName(expectedFamily.c_str(), &familyIndex, &systemPresent), "FindExpectedFamilyInSystemCollection");
    const std::wstring selectedFamily = familyName(privateCollection.Get());
    const std::wstring selectedPS = postScriptName(privateCollection.Get());
    const bool privateIdentity = selectedFamily == expectedFamily && selectedPS == expectedPS;
    std::wprintf(L"{\"status\":\"probe\",\"fontPath\":\"%ls\",\"resourceSha256Provided\":\"%ls\",\"privateRegistrationCount\":%d,\"privateCollectionFamily\":\"%ls\",\"privateCollectionPostScript\":\"%ls\",\"privateIdentity\":%s,\"systemCollectionFamilyPresent\":%s,\"clientRect\":{\"left\":%ld,\"top\":%ld,\"right\":%ld,\"bottom\":%ld,\"width\":%ld,\"height\":%ld},\"rendererOrAbiEdited\":false,\"qualification\":\"held-until-root-native-render\"}\n", fontPath.c_str(), resourceSha.c_str(), privateAdded, selectedFamily.c_str(), selectedPS.c_str(), privateIdentity ? L"true" : L"false", systemPresent ? L"true" : L"false", client.left, client.top, client.right, client.bottom, client.right - client.left, client.bottom - client.top);
    if (privateAdded > 0) RemoveFontResourceExW(fontPath.c_str(), FR_PRIVATE, nullptr);
    return privateIdentity ? 0 : 9;
}
