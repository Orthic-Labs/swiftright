// Owned HWND interop capture only; no picker/access request/border suppression.
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <wincodec.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <chrono>
#include <fstream>
#include <filesystem>
#include <cstdio>
using namespace winrt;
using namespace Windows::Graphics::Capture;
using namespace Windows::Graphics::DirectX;
using namespace Windows::Graphics::DirectX::Direct3D11;
static void png(ID3D11Device* device,ID3D11DeviceContext* context,ID3D11Texture2D* source,const wchar_t* path){
 D3D11_TEXTURE2D_DESC desc{};source->GetDesc(&desc);
 if(!desc.Width||!desc.Height||desc.Width>4096||desc.Height>4096||desc.Format!=DXGI_FORMAT_B8G8R8A8_UNORM)throw hresult_error(E_INVALIDARG,L"Unexpected capture texture");
 desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.MiscFlags=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
 com_ptr<ID3D11Texture2D> staging;check_hresult(device->CreateTexture2D(&desc,nullptr,staging.put()));context->CopyResource(staging.get(),source);
 D3D11_MAPPED_SUBRESOURCE pixels{};check_hresult(context->Map(staging.get(),0,D3D11_MAP_READ,0,&pixels));
 try{
  com_ptr<IWICImagingFactory> factory;check_hresult(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,__uuidof(IWICImagingFactory),factory.put_void()));
  com_ptr<IWICStream> stream;check_hresult(factory->CreateStream(stream.put()));check_hresult(stream->InitializeFromFilename(path,GENERIC_WRITE));
  com_ptr<IWICBitmapEncoder> encoder;check_hresult(factory->CreateEncoder(GUID_ContainerFormatPng,nullptr,encoder.put()));check_hresult(encoder->Initialize(stream.get(),WICBitmapEncoderNoCache));
  com_ptr<IWICBitmapFrameEncode> frame;check_hresult(encoder->CreateNewFrame(frame.put(),nullptr));check_hresult(frame->Initialize(nullptr));check_hresult(frame->SetSize(desc.Width,desc.Height));
  WICPixelFormatGUID format=GUID_WICPixelFormat32bppBGRA;check_hresult(frame->SetPixelFormat(&format));if(format!=GUID_WICPixelFormat32bppBGRA)throw hresult_error(E_FAIL,L"PNG pixel format changed");
  check_hresult(frame->WritePixels(desc.Height,pixels.RowPitch,pixels.RowPitch*desc.Height,(BYTE*)pixels.pData));check_hresult(frame->Commit());check_hresult(encoder->Commit());
 }catch(...){context->Unmap(staging.get(),0);throw;}
 context->Unmap(staging.get(),0);
}
int wmain(int argc,wchar_t** argv){
 try{
  if(argc!=4)throw hresult_error(E_INVALIDARG,L"Arguments: owned HWND expected PID new archive directory");
  HWND hwnd=(HWND)(uintptr_t)_wcstoui64(argv[1],nullptr,10);DWORD expected=wcstoul(argv[2],nullptr,10),actual=0;GetWindowThreadProcessId(hwnd,&actual);
  if(!IsWindow(hwnd)||!expected||actual!=expected)throw hresult_error(E_ACCESSDENIED,L"Target not owned HWND");
  std::filesystem::path directory=std::filesystem::absolute(argv[3]);auto text=directory.wstring();
  if(text.rfind(L"D:\\Claude\\swiftright\\factory\\native\\windows\\",0)!=0||!std::filesystem::is_directory(directory))throw hresult_error(E_ACCESSDENIED,L"Owned existing archive directory required");
  if(std::filesystem::exists(directory/L"wgc-1.png")||std::filesystem::exists(directory/L"wgc-2.png"))throw hresult_error(E_ACCESSDENIED,L"Fresh capture paths required");
  init_apartment(apartment_type::multi_threaded);
  if(!GraphicsCaptureSession::IsSupported())throw hresult_error(E_NOTIMPL,L"WGC unsupported");
  auto interop=get_activation_factory<GraphicsCaptureItem,IGraphicsCaptureItemInterop>();GraphicsCaptureItem item{nullptr};check_hresult(interop->CreateForWindow(hwnd,guid_of<GraphicsCaptureItem>(),put_abi(item)));
  com_ptr<ID3D11Device> device;com_ptr<ID3D11DeviceContext> context;D3D_FEATURE_LEVEL level{};
  check_hresult(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,nullptr,0,D3D11_SDK_VERSION,device.put(),&level,context.put()));
  auto dxgi=device.as<IDXGIDevice>();com_ptr<IInspectable> inspectable;check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(),inspectable.put()));auto captureDevice=inspectable.as<IDirect3DDevice>();
  auto size=item.Size();auto pool=Direct3D11CaptureFramePool::CreateFreeThreaded(captureDevice,DirectXPixelFormat::B8G8R8A8UIntNormalized,2,size);auto session=pool.CreateCaptureSession(item);
  // Default capture border remains enabled. No API requesting user consent is invoked.
  session.StartCapture();int saved=0;auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
  std::ofstream metadata(directory/L"wgc-frames.json");metadata<<"{\"kind\":\"owned-hwnd-WGC-observation\",\"ownedPID\":"<<actual<<",\"hwnd\":"<<(uintptr_t)hwnd<<",\"defaultBorderRequired\":true,\"permissionPromptRequested\":false,\"nativeCaseCaptureCount\":0,\"qualified\":false,\"frames\":[";
  while(saved<2&&std::chrono::steady_clock::now()<deadline){
   DWORD owner=0;GetWindowThreadProcessId(hwnd,&owner);if(owner!=expected)throw hresult_error(E_ACCESSDENIED,L"Owned target lost");
   auto frame=pool.TryGetNextFrame();if(!frame){Sleep(10);continue;}
   auto access=frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();com_ptr<ID3D11Texture2D> texture;check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D),texture.put_void()));
   auto target=directory/(saved?L"wgc-2.png":L"wgc-1.png");png(device.get(),context.get(),texture.get(),target.c_str());
   auto dimensions=frame.ContentSize();auto relative=frame.SystemRelativeTime();if(saved)metadata<<",";metadata<<"{\"index\":"<<saved+1<<",\"width\":"<<dimensions.Width<<",\"height\":"<<dimensions.Height<<",\"systemRelativeTime100ns\":"<<relative.count()<<"}";
   saved++;frame.Close();
  }
  session.Close();pool.Close();metadata<<"],\"frameCount\":"<<saved<<"}";metadata.close();
  if(saved!=2)throw hresult_error(HRESULT_FROM_WIN32(WAIT_TIMEOUT),L"Owned WGC frame deadline");
  printf("FACTORY_WGC_RAW_FRAME_COUNT=2 defaultBorderRequired=true permissionPromptRequested=false\n");return 0;
 }catch(hresult_error const& error){fwprintf(stderr,L"FACTORY_WGC_HOLD hresult=%08x message=%s\n",(unsigned)error.code().value,error.message().c_str());return 78;}
 catch(...){fprintf(stderr,"FACTORY_WGC_HOLD unexpected helper failure\n");return 78;}
}
