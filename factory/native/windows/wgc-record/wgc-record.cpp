// FactoryWGCRecord: record EVERY Windows.Graphics.Capture frame of one HWND (issue #32, decision H19b).
//   FactoryWGCRecord.exe --hwnd <n> --out <dir> --seconds <s> [--stop-file <path>]
// Writes <dir>\frame-NNNNNN.png (cropped to the frame's ContentSize, BGRA, alpha kept), <dir>\frames.jsonl (one line per FrameArrived),
// <dir>\ready.txt (written once capture runs; the guest waits for it) and <dir>\summary.json. Stops on the stop file or the timeout.
// WGC delivers a frame only when the window content changes, so gaps between frames are expected and say nothing by themselves.
// The FrameArrived handler only copies the texture to CPU memory and closes the frame at once; a writer thread encodes the PNGs,
// so PNG encoding never holds a pool buffer (a held buffer would make WGC skip a change, the very event this tool looks for).
// Owned HWND interop only: no picker and no access request. IsCursorCaptureEnabled and IsBorderRequired are set when the OS has them.
#include <windows.h>
#include <unknwn.h>
#include <d3d11.h>
#include <dxgi.h>
#include <wincodec.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Graphics.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;
namespace fs = std::filesystem;

struct Job { int index; int width; int height; std::vector<BYTE> bgra; };   // bgra is width*height*4, tightly packed

static std::mutex g_lock;                 // guards the D3D context, the staging texture, the jsonl stream, the counters and g_errors
static std::vector<std::string> g_errors;
static std::mutex g_qlock;
static std::condition_variable g_qcv;
static std::deque<Job> g_queue;
static bool g_qdone = false;
static const size_t kQueueCap = 2000;

static std::string esc(std::string s) {
 std::string o; for (char c : s) { if (c == '"' || c == '\\') { o += '\\'; o += c; } else if ((unsigned char)c < 0x20) o += ' '; else o += c; } return o;
}
static std::string narrow(std::wstring const& w) {
 if (w.empty()) return {}; int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0, nullptr, nullptr);
 std::string s(n, 0); WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n, nullptr, nullptr); return s;
}
static void add_error(std::string const& e) { std::lock_guard<std::mutex> g(g_lock); if (g_errors.size() < 50) g_errors.push_back(e); }
static long long qpc_now() { LARGE_INTEGER v; QueryPerformanceCounter(&v); return v.QuadPart; }
static long long qpc_freq() { LARGE_INTEGER v; QueryPerformanceFrequency(&v); return v.QuadPart; }

static void write_png(IWICImagingFactory* factory, fs::path const& path, Job const& j) {
 com_ptr<IWICStream> stream; check_hresult(factory->CreateStream(stream.put())); check_hresult(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE));
 com_ptr<IWICBitmapEncoder> encoder; check_hresult(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, encoder.put())); check_hresult(encoder->Initialize(stream.get(), WICBitmapEncoderNoCache));
 com_ptr<IWICBitmapFrameEncode> frame; check_hresult(encoder->CreateNewFrame(frame.put(), nullptr)); check_hresult(frame->Initialize(nullptr)); check_hresult(frame->SetSize(j.width, j.height));
 WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA; check_hresult(frame->SetPixelFormat(&format));
 if (format != GUID_WICPixelFormat32bppBGRA) throw hresult_error(E_FAIL, L"PNG pixel format changed");
 check_hresult(frame->WritePixels(j.height, j.width * 4, (UINT)j.bgra.size(), const_cast<BYTE*>(j.bgra.data())));
 check_hresult(frame->Commit()); check_hresult(encoder->Commit());
}

static void writer_thread(fs::path dir) {
 try {
  init_apartment(apartment_type::multi_threaded);
  com_ptr<IWICImagingFactory> factory; check_hresult(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, __uuidof(IWICImagingFactory), factory.put_void()));
  for (;;) {
   Job j;
   { std::unique_lock<std::mutex> l(g_qlock); g_qcv.wait(l, [] { return !g_queue.empty() || g_qdone; }); if (g_queue.empty()) return; j = std::move(g_queue.front()); g_queue.pop_front(); }
   wchar_t name[40]; swprintf_s(name, L"frame-%06d.png", j.index);
   try { write_png(factory.get(), dir / name, j); } catch (hresult_error const& e) { add_error("png " + std::to_string(j.index) + " hresult=" + std::to_string((unsigned)e.code().value) + " " + narrow(std::wstring(e.message()))); }
  }
 } catch (hresult_error const& e) { add_error("writer thread: " + narrow(std::wstring(e.message()))); }
}

static std::string arg_value(int argc, wchar_t** argv, const wchar_t* key) {
 for (int i = 1; i + 1 < argc; i++) if (wcscmp(argv[i], key) == 0) return narrow(argv[i + 1]);
 return {};
}
static std::wstring warg_value(int argc, wchar_t** argv, const wchar_t* key) {
 for (int i = 1; i + 1 < argc; i++) if (wcscmp(argv[i], key) == 0) return argv[i + 1];
 return {};
}

int wmain(int argc, wchar_t** argv) {
 fs::path dir; long long freq = qpc_freq(); long long startQpc = 0, endQpc = 0; int rc = 0;
 std::atomic<int> count{0}; std::atomic<int> pngQueued{0}, pngDropped{0}; std::atomic<bool> itemClosed{false};
 long long firstSrt = 0, lastSrt = 0, firstQpc = 0, lastQpc = 0, maxGapSrt = 0; int gapsOver50ms = 0; int resizes = 0;
 bool cursorSet = false, borderSet = false; std::string cursorNote = "not attempted", borderNote = "not attempted";
 int itemW = 0, itemH = 0; bool timedOut = false, stoppedByFile = false; HWND hwnd = nullptr;
 std::ofstream jsonl; std::thread writer;
 try {
  std::wstring hw = warg_value(argc, argv, L"--hwnd"), out = warg_value(argc, argv, L"--out"), secs = warg_value(argc, argv, L"--seconds"), stop = warg_value(argc, argv, L"--stop-file");
  if (hw.empty() || out.empty() || secs.empty()) throw hresult_error(E_INVALIDARG, L"Arguments: --hwnd <n> --out <dir> --seconds <s> [--stop-file <path>]");
  hwnd = (HWND)(uintptr_t)_wcstoui64(hw.c_str(), nullptr, 0); double seconds = _wtof(secs.c_str());
  if (seconds <= 0) throw hresult_error(E_INVALIDARG, L"--seconds must be positive");
  dir = fs::absolute(out); fs::create_directories(dir);
  if (!IsWindow(hwnd)) throw hresult_error(E_INVALIDARG, L"--hwnd is not a window");
  jsonl.open(dir / L"frames.jsonl", std::ios::binary);
  init_apartment(apartment_type::multi_threaded);
  if (!GraphicsCaptureSession::IsSupported()) throw hresult_error(E_NOTIMPL, L"WGC unsupported");
  auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
  GraphicsCaptureItem item{nullptr}; check_hresult(interop->CreateForWindow(hwnd, guid_of<GraphicsCaptureItem>(), put_abi(item)));
  com_ptr<ID3D11Device> device; com_ptr<ID3D11DeviceContext> context; D3D_FEATURE_LEVEL level{};
  check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, device.put(), &level, context.put()));
  auto dxgi = device.as<IDXGIDevice>(); com_ptr<IInspectable> inspectable; check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
  auto captureDevice = inspectable.as<IDirect3DDevice>();
  auto size = item.Size(); itemW = size.Width; itemH = size.Height;
  // Free-threaded pool: FrameArrived runs on a thread-pool thread. Four buffers give the handler slack.
  auto pool = Direct3D11CaptureFramePool::CreateFreeThreaded(captureDevice, DirectXPixelFormat::B8G8R8A8UIntNormalized, 4, size);
  auto session = pool.CreateCaptureSession(item);
  try { session.IsCursorCaptureEnabled(false); cursorSet = true; cursorNote = "IsCursorCaptureEnabled=false"; } catch (hresult_error const& e) { cursorNote = "unavailable: " + narrow(std::wstring(e.message())); }
  try { session.IsBorderRequired(false); borderSet = true; borderNote = "IsBorderRequired=false"; } catch (hresult_error const& e) { borderNote = "unavailable or refused: " + narrow(std::wstring(e.message())); }
  com_ptr<ID3D11Texture2D> staging; D3D11_TEXTURE2D_DESC stagingDesc{}; winrt::Windows::Graphics::SizeInt32 poolSize = size;
  writer = std::thread(writer_thread, dir);
  item.Closed([&](GraphicsCaptureItem const&, IInspectable const&) { itemClosed = true; });
  auto token = pool.FrameArrived([&](Direct3D11CaptureFramePool const& sender, IInspectable const&) {
   // One call per FrameArrived; drain every frame that is queued (TryGetNextFrame returns null when none is left).
   for (;;) {
    auto frame = sender.TryGetNextFrame(); if (!frame) return;
    long long arrival = qpc_now();
    try {
     auto content = frame.ContentSize(); long long srt = frame.SystemRelativeTime().count();
     auto access = frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
     com_ptr<ID3D11Texture2D> texture; check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), texture.put_void()));
     D3D11_TEXTURE2D_DESC desc{}; texture->GetDesc(&desc);
     if (desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM) throw hresult_error(E_INVALIDARG, L"Unexpected capture texture format");
     int cw = content.Width < (int)desc.Width ? content.Width : (int)desc.Width, ch = content.Height < (int)desc.Height ? content.Height : (int)desc.Height;
     if (cw < 1 || ch < 1) throw hresult_error(E_INVALIDARG, L"Empty content size");
     Job job; bool queued = false; int index;
     {
      std::lock_guard<std::mutex> g(g_lock);
      if (!staging || stagingDesc.Width != desc.Width || stagingDesc.Height != desc.Height) {
       stagingDesc = desc; stagingDesc.Usage = D3D11_USAGE_STAGING; stagingDesc.BindFlags = 0; stagingDesc.MiscFlags = 0; stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
       staging = nullptr; check_hresult(device->CreateTexture2D(&stagingDesc, nullptr, staging.put()));
      }
      context->CopyResource(staging.get(), texture.get());
      D3D11_MAPPED_SUBRESOURCE m{}; check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &m));
      job.width = cw; job.height = ch; job.bgra.resize((size_t)cw * ch * 4);
      for (int y = 0; y < ch; y++) memcpy(job.bgra.data() + (size_t)y * cw * 4, (const BYTE*)m.pData + (size_t)y * m.RowPitch, (size_t)cw * 4);
      context->Unmap(staging.get(), 0);
      index = ++count; job.index = index;
      if (index == 1) { firstSrt = srt; firstQpc = arrival; } else { long long gap = srt - lastSrt; if (gap > maxGapSrt) maxGapSrt = gap; if (gap > 500000) gapsOver50ms++; }
      lastSrt = srt; lastQpc = arrival;
      // Resize: the pool keeps its buffer size until recreated; recreate when the window outgrew it so no content is cropped away.
      if (content.Width != poolSize.Width || content.Height != poolSize.Height) { poolSize = content; resizes++; sender.Recreate(captureDevice, DirectXPixelFormat::B8G8R8A8UIntNormalized, 4, content); }
      { std::lock_guard<std::mutex> q(g_qlock); if (g_queue.size() < kQueueCap) { g_queue.push_back(std::move(job)); queued = true; } }
      if (queued) pngQueued++; else pngDropped++;
      jsonl << "{\"index\":" << index << ",\"systemRelativeTimeTicks\":" << srt << ",\"qpc\":" << arrival << ",\"contentSize\":[" << content.Width << "," << content.Height
            << "],\"width\":" << cw << ",\"height\":" << ch << ",\"poolSurface\":[" << desc.Width << "," << desc.Height << "],\"png\":" << (queued ? "true" : "false") << "}\n";
      jsonl.flush();
     }
     if (queued) g_qcv.notify_one();
    } catch (hresult_error const& e) { add_error("frame: hresult=" + std::to_string((unsigned)e.code().value) + " " + narrow(std::wstring(e.message()))); }
    frame.Close();
   }
  });
  session.StartCapture(); startQpc = qpc_now();
  { std::ofstream r(dir / L"ready.txt"); r << "qpc=" << startQpc << "\nfreq=" << freq << "\n"; }
  auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds((long long)(seconds * 1000.0));
  for (;;) {
   if (!stop.empty() && fs::exists(stop)) { stoppedByFile = true; break; }
   if (std::chrono::steady_clock::now() >= deadline) { timedOut = true; break; }
   if (itemClosed) { add_error("capture item closed (window destroyed)"); break; }
   Sleep(25);
  }
  endQpc = qpc_now();
  pool.FrameArrived(token); session.Close(); pool.Close();
 } catch (hresult_error const& e) {
  add_error("fatal: hresult=" + std::to_string((unsigned)e.code().value) + " " + narrow(std::wstring(e.message()))); rc = 78;
 } catch (...) { add_error("fatal: unexpected failure"); rc = 78; }
 { std::lock_guard<std::mutex> q(g_qlock); g_qdone = true; } g_qcv.notify_all();
 if (writer.joinable()) writer.join();
 { std::lock_guard<std::mutex> g(g_lock); if (jsonl.is_open()) jsonl.close(); }
 try {
  if (!dir.empty()) {
   std::ofstream s(dir / L"summary.json", std::ios::binary);
   s << "{\"schema\":\"wgc-record/v1\",\"hwnd\":" << (unsigned long long)(uintptr_t)hwnd << ",\"frameCount\":" << count.load() << ",\"pngWritten\":" << pngQueued.load() << ",\"pngDroppedQueueFull\":" << pngDropped.load()
     << ",\"qpcFrequency\":" << freq << ",\"startQpc\":" << startQpc << ",\"endQpc\":" << endQpc << ",\"firstSystemRelativeTimeTicks\":" << firstSrt << ",\"lastSystemRelativeTimeTicks\":" << lastSrt
     << ",\"firstQpc\":" << firstQpc << ",\"lastQpc\":" << lastQpc << ",\"maxGapTicks\":" << maxGapSrt << ",\"gapsOver50ms\":" << gapsOver50ms << ",\"poolResizes\":" << resizes
     << ",\"itemSize\":[" << itemW << "," << itemH << "],\"stoppedByFile\":" << (stoppedByFile ? "true" : "false") << ",\"timedOut\":" << (timedOut ? "true" : "false")
     << ",\"cursorCapture\":\"" << esc(cursorNote) << "\",\"borderRequired\":\"" << esc(borderNote) << "\""
     << ",\"note\":\"WGC delivers a frame only when the window content changes; gaps between frames are expected and are not dropped frames.\",\"errors\":[";
   for (size_t i = 0; i < g_errors.size(); i++) s << (i ? "," : "") << "\"" << esc(g_errors[i]) << "\"";
   s << "]}\n";
  }
 } catch (...) { }
 if (count.load() == 0 && rc == 0) rc = 79;
 printf("WGC_RECORD frames=%d errors=%d rc=%d\n", count.load(), (int)g_errors.size(), rc);
 return rc;
}
