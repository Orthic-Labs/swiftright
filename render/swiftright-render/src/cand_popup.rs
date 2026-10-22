//! Issue #45 step 2: the candidate popup window and its painter.
//!
//! A small owned, non-activating popup (`SwiftRightImeCandidates`) that shows the IME candidate rows. It is drawn with
//! Direct2D + DirectWrite (system font fallback, colour fonts), never takes focus, and is hidden until the first `show`.
//! The same painter renders into a WIC bitmap (`render_to_rgba`) so tests need no window.
//!
//! Units: everything here is device pixels. `scale` = monitor DPI / 96 and is supplied by the caller; the popup ignores
//! WM_DPICHANGED. The render targets are pinned to 96 dpi so one DIP is one pixel.
//!
//! Threading: all state is single-threaded. The graphics factories live in a thread local of the thread that uses them
//! (the render thread); no thread is created here.

use std::cell::RefCell;
use std::ffi::c_void;
use std::sync::Once;

use windows::core::{w, Interface, PCWSTR, PWSTR};
use windows::Win32::Foundation::{
    ERROR_SUCCESS, E_FAIL, HINSTANCE, HWND, LPARAM, LRESULT, WPARAM,
};
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_ALPHA_MODE_PREMULTIPLIED, D2D1_ALPHA_MODE_UNKNOWN, D2D1_COLOR_F, D2D1_PIXEL_FORMAT, D2D_RECT_F, D2D_SIZE_U,
};
use windows::Win32::Graphics::Direct2D::{
    D2D1CreateFactory, ID2D1Factory, ID2D1HwndRenderTarget, ID2D1RenderTarget, ID2D1StrokeStyle,
    D2D1_DRAW_TEXT_OPTIONS_CLIP, D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT, D2D1_FACTORY_TYPE_SINGLE_THREADED,
    D2D1_FEATURE_LEVEL_DEFAULT, D2D1_HWND_RENDER_TARGET_PROPERTIES, D2D1_PRESENT_OPTIONS_NONE,
    D2D1_RENDER_TARGET_PROPERTIES, D2D1_RENDER_TARGET_TYPE_DEFAULT, D2D1_RENDER_TARGET_TYPE_SOFTWARE,
    D2D1_RENDER_TARGET_USAGE_NONE, D2D1_ROUNDED_RECT, D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE,
};
use windows::Win32::Graphics::Dwm::{DwmSetWindowAttribute, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_ROUND};
use windows::Win32::Graphics::DirectWrite::{
    DWriteCreateFactory, IDWriteFactory, IDWriteFontCollection, IDWriteTextFormat, DWRITE_FACTORY_TYPE_SHARED,
    DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_MEASURING_MODE_NATURAL,
    DWRITE_PARAGRAPH_ALIGNMENT_CENTER, DWRITE_TEXT_METRICS, DWRITE_WORD_WRAPPING_NO_WRAP,
};
use windows::Win32::Graphics::Dxgi::Common::{DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_FORMAT_UNKNOWN};
use windows::Win32::Graphics::Gdi::{
    GetSysColor, ValidateRect, COLOR_HIGHLIGHT, COLOR_HIGHLIGHTTEXT, COLOR_WINDOW, COLOR_WINDOWTEXT,
};
use windows::Win32::Graphics::Imaging::{
    CLSID_WICImagingFactory, GUID_WICPixelFormat32bppPBGRA, IWICImagingFactory, WICBitmapCacheOnLoad,
    WICBitmapLockRead, WICRect,
};
use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_DWORD};
use windows::Win32::UI::Accessibility::{HCF_HIGHCONTRASTON, HIGHCONTRASTW};
use windows::Win32::UI::HiDpi::SystemParametersInfoForDpi;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, LoadCursorW, HCURSOR, RegisterClassExW, SetWindowPos, ShowWindow,
    SystemParametersInfoW, IDC_ARROW, MA_NOACTIVATE, NONCLIENTMETRICSW, SPI_GETHIGHCONTRAST,
    SPI_GETNONCLIENTMETRICS, SWP_NOACTIVATE, SWP_SHOWWINDOW, SW_HIDE, SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS,
    WM_ERASEBKGND, WM_MOUSEACTIVATE, WM_PAINT, WNDCLASSEXW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_POPUP,
};

// ---------------------------------------------------------------------------------------------------------------------
// Public plain data

/// What the popup shows. Row `i` is labelled `first_number + i` when `show_numbers` is set and the label is 1..=9;
/// other labels are left blank. `selected` is an index into `rows`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PopupModel {
    pub rows: Vec<String>,
    pub selected: Option<usize>,
    pub show_numbers: bool,
    pub first_number: usize,
}

/// Colour scheme. `accent` is the selection fill (ignored in high contrast, which uses GetSysColor only).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Theme {
    pub dark: bool,
    pub high_contrast: bool,
    pub accent: (u8, u8, u8),
}

// ---------------------------------------------------------------------------------------------------------------------
// Layout (pure integer math, device pixels)

fn px(v: f32, scale: f32) -> i32 {
    (v * scale).round() as i32
}

/// Height of one candidate row.
pub fn row_height(scale: f32) -> i32 {
    px(24.0, scale).max(1)
}

/// Vertical padding above the first and below the last row.
pub fn padding_y(scale: f32) -> i32 {
    px(4.0, scale)
}

fn padding_x(scale: f32) -> i32 {
    px(10.0, scale)
}

fn number_col(model: &PopupModel, scale: f32) -> i32 {
    if model.show_numbers {
        px(22.0, scale)
    } else {
        0
    }
}

/// Left edge (in popup client pixels) of the candidate text.
pub fn text_left(model: &PopupModel, scale: f32) -> i32 {
    padding_x(scale) + number_col(model, scale)
}

fn height_for(rows: usize, scale: f32) -> i32 {
    rows as i32 * row_height(scale) + 2 * padding_y(scale)
}

fn clamp_width(w: i32, scale: f32) -> i32 {
    w.clamp(px(120.0, scale), px(600.0, scale))
}

/// Row under client point (x, y) of a popup of `width` x `height` with `rows` rows.
fn hit_client(x: i32, y: i32, width: i32, height: i32, rows: usize, scale: f32) -> Option<usize> {
    if x < 0 || y < 0 || x >= width || y >= height {
        return None;
    }
    let rel = y - padding_y(scale);
    if rel < 0 {
        return None;
    }
    let i = (rel / row_height(scale)) as usize;
    (i < rows).then_some(i)
}

// ---------------------------------------------------------------------------------------------------------------------
// Graphics factories (thread local) and fonts

struct Gfx {
    d2d: ID2D1Factory,
    dw: IDWriteFactory,
    /// System message font family, NUL terminated UTF-16.
    family: Vec<u16>,
    /// Em height in pixels at 96 dpi.
    font_px: f32,
}

thread_local! {
    static GFX: RefCell<Option<Gfx>> = const { RefCell::new(None) };
}

fn message_font() -> (Vec<u16>, f32) {
    let mut family: Vec<u16> = "Segoe UI".encode_utf16().chain(Some(0)).collect();
    let mut px_h = 12.0f32;
    unsafe {
        let mut ncm = NONCLIENTMETRICSW { cbSize: std::mem::size_of::<NONCLIENTMETRICSW>() as u32, ..Default::default() };
        // 96 dpi: the result must not depend on the process / system DPI, `scale` is applied by us.
        if SystemParametersInfoForDpi(
            SPI_GETNONCLIENTMETRICS.0,
            ncm.cbSize,
            Some(&mut ncm as *mut NONCLIENTMETRICSW as *mut c_void),
            0,
            96,
        )
        .is_ok()
        {
            let face = &ncm.lfMessageFont.lfFaceName;
            let len = face.iter().position(|&c| c == 0).unwrap_or(face.len());
            if len > 0 {
                family = face[..len].iter().copied().chain(Some(0)).collect();
            }
            let h = ncm.lfMessageFont.lfHeight.unsigned_abs() as f32;
            if h >= 6.0 {
                px_h = h;
            }
        }
    }
    (family, px_h)
}

fn init_gfx() -> Option<Gfx> {
    unsafe {
        let d2d: ID2D1Factory = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, None).ok()?;
        let dw: IDWriteFactory = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED).ok()?;
        let (family, font_px) = message_font();
        Some(Gfx { d2d, dw, family, font_px })
    }
}

fn with_gfx<R>(f: impl FnOnce(&Gfx) -> R) -> Option<R> {
    GFX.with(|c| {
        let mut g = c.borrow_mut();
        if g.is_none() {
            *g = init_gfx();
        }
        g.as_ref().map(f)
    })
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

/// The row text format: system message font scaled by `scale`, no wrapping, vertically centred. DirectWrite applies
/// system font fallback (CJK, emoji) on its own for the system collection.
fn make_format(g: &Gfx, scale: f32) -> Option<IDWriteTextFormat> {
    unsafe {
        let f = g
            .dw
            .CreateTextFormat(
                PCWSTR(g.family.as_ptr()),
                None::<&IDWriteFontCollection>,
                DWRITE_FONT_WEIGHT_NORMAL,
                DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_STRETCH_NORMAL,
                g.font_px * scale,
                w!("en-us"),
            )
            .ok()?;
        f.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP).ok()?;
        f.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER).ok()?;
        Some(f)
    }
}

/// Popup size in pixels (width, height): rows * row height + padding; width is the widest row text plus the number
/// column and padding, clamped to 120*scale..=600*scale.
pub fn measure(model: &PopupModel, scale: f32) -> (i32, i32) {
    let h = height_for(model.rows.len(), scale);
    let text_w = with_gfx(|g| {
        let fmt = make_format(g, scale)?;
        let mut max = 0.0f32;
        for r in &model.rows {
            let w16 = wide(r);
            if w16.is_empty() {
                continue;
            }
            unsafe {
                let layout = g.dw.CreateTextLayout(&w16, &fmt, 10_000.0, row_height(scale) as f32).ok()?;
                let mut m = DWRITE_TEXT_METRICS::default();
                layout.GetMetrics(&mut m).ok()?;
                max = max.max(m.widthIncludingTrailingWhitespace);
            }
        }
        Some(max.ceil() as i32)
    })
    .flatten()
    // No DirectWrite: a rough per-character estimate keeps the popup usable.
    .unwrap_or_else(|| {
        model.rows.iter().map(|r| r.chars().count()).max().unwrap_or(0) as i32 * px(9.0, scale)
    });
    let w = text_left(model, scale) + text_w + padding_x(scale);
    (clamp_width(w, scale), h)
}

// ---------------------------------------------------------------------------------------------------------------------
// Theme

fn colorref(c: u32) -> (u8, u8, u8) {
    ((c & 0xff) as u8, ((c >> 8) & 0xff) as u8, ((c >> 16) & 0xff) as u8)
}

fn sys(index: windows::Win32::Graphics::Gdi::SYS_COLOR_INDEX) -> (u8, u8, u8) {
    colorref(unsafe { GetSysColor(index) })
}

fn reg_dword(subkey: PCWSTR, value: PCWSTR) -> Option<u32> {
    let mut data: u32 = 0;
    let mut size = std::mem::size_of::<u32>() as u32;
    let rc = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            subkey,
            value,
            RRF_RT_REG_DWORD,
            None,
            Some(&mut data as *mut u32 as *mut c_void),
            Some(&mut size),
        )
    };
    (rc == ERROR_SUCCESS).then_some(data)
}

/// The current system theme: dark/light app mode, accent colour, high contrast.
pub fn system_theme() -> Theme {
    let dark = reg_dword(
        w!("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
        w!("AppsUseLightTheme"),
    )
    .map(|v| v == 0)
    .unwrap_or(false);
    // AccentColorMenu is 0xAABBGGRR.
    let accent = reg_dword(w!("Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Accent"), w!("AccentColorMenu"))
        .map(colorref)
        .unwrap_or_else(|| sys(COLOR_HIGHLIGHT));
    let mut hc = HIGHCONTRASTW { cbSize: std::mem::size_of::<HIGHCONTRASTW>() as u32, ..Default::default() };
    hc.lpszDefaultScheme = PWSTR::null();
    let ok = unsafe {
        SystemParametersInfoW(
            SPI_GETHIGHCONTRAST,
            hc.cbSize,
            Some(&mut hc as *mut HIGHCONTRASTW as *mut c_void),
            SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
        )
    }
    .is_ok();
    let high_contrast = ok && (hc.dwFlags.0 & HCF_HIGHCONTRASTON.0) != 0;
    Theme { dark, high_contrast, accent }
}

struct Palette {
    bg: D2D1_COLOR_F,
    text: D2D1_COLOR_F,
    number: D2D1_COLOR_F,
    border: D2D1_COLOR_F,
    sel_bg: D2D1_COLOR_F,
    sel_text: D2D1_COLOR_F,
}

fn col(c: (u8, u8, u8)) -> D2D1_COLOR_F {
    D2D1_COLOR_F { r: c.0 as f32 / 255.0, g: c.1 as f32 / 255.0, b: c.2 as f32 / 255.0, a: 1.0 }
}

fn palette(theme: &Theme) -> Palette {
    if theme.high_contrast {
        let window = col(sys(COLOR_WINDOW));
        let text = col(sys(COLOR_WINDOWTEXT));
        Palette {
            bg: window,
            text,
            number: text,
            border: text,
            sel_bg: col(sys(COLOR_HIGHLIGHT)),
            sel_text: col(sys(COLOR_HIGHLIGHTTEXT)),
        }
    } else if theme.dark {
        Palette {
            bg: col((43, 43, 43)),
            text: col((255, 255, 255)),
            number: col((176, 176, 176)),
            border: col((84, 84, 84)),
            sel_bg: col(theme.accent),
            sel_text: col((255, 255, 255)),
        }
    } else {
        Palette {
            bg: col((243, 243, 243)),
            text: col((27, 27, 27)),
            number: col((96, 96, 96)),
            border: col((200, 200, 200)),
            sel_bg: col(theme.accent),
            sel_text: col((255, 255, 255)),
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// Painter (shared by the window and the offscreen target)

fn fail() -> windows::core::Error {
    windows::core::Error::from(E_FAIL)
}

fn rect(l: f32, t: f32, r: f32, b: f32) -> D2D_RECT_F {
    D2D_RECT_F { left: l, top: t, right: r, bottom: b }
}

/// Paints the whole popup (`w` x `h` pixels) into `rt`, which must be a 96 dpi target.
fn paint(rt: &ID2D1RenderTarget, g: &Gfx, model: &PopupModel, scale: f32, theme: &Theme, w: i32, h: i32) -> windows::core::Result<()> {
    let pal = palette(theme);
    let fmt = make_format(g, scale).ok_or_else(fail)?;
    let (rh, py, tl) = (row_height(scale), padding_y(scale), text_left(model, scale));
    let px_pad = padding_x(scale);
    let (wf, hf) = (w as f32, h as f32);
    unsafe {
        let brush = rt.CreateSolidColorBrush(&pal.bg, None)?;
        rt.BeginDraw();
        rt.Clear(Some(&pal.bg as *const D2D1_COLOR_F));
        for (i, row) in model.rows.iter().enumerate() {
            let top = (py + i as i32 * rh) as f32;
            let bottom = top + rh as f32;
            let selected = model.selected == Some(i);
            if selected {
                let inset_x = px(4.0, scale) as f32;
                let inset_y = px(1.0, scale) as f32;
                let rr = D2D1_ROUNDED_RECT {
                    rect: rect(inset_x, top + inset_y, wf - inset_x, bottom - inset_y),
                    radiusX: px(4.0, scale) as f32,
                    radiusY: px(4.0, scale) as f32,
                };
                brush.SetColor(&pal.sel_bg);
                rt.FillRoundedRectangle(&rr, &brush);
            }
            let ink = if selected { pal.sel_text } else { pal.text };
            if model.show_numbers {
                let label = model.first_number + i;
                if (1..=9).contains(&label) {
                    let s = wide(&label.to_string());
                    brush.SetColor(&if selected { pal.sel_text } else { pal.number });
                    let r = rect(px_pad as f32, top, tl as f32, bottom);
                    rt.DrawText(&s, &fmt, &r, &brush, D2D1_DRAW_TEXT_OPTIONS_CLIP, DWRITE_MEASURING_MODE_NATURAL);
                }
            }
            let s = wide(row);
            if !s.is_empty() {
                brush.SetColor(&ink);
                let r = rect(tl as f32, top, wf - px_pad as f32, bottom);
                rt.DrawText(
                    &s,
                    &fmt,
                    &r,
                    &brush,
                    D2D1_DRAW_TEXT_OPTIONS_CLIP | D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT,
                    DWRITE_MEASURING_MODE_NATURAL,
                );
            }
        }
        // 1 px border, drawn last so selection fills never cover it.
        brush.SetColor(&pal.border);
        rt.DrawRectangle(&rect(0.5, 0.5, wf - 0.5, hf - 0.5), &brush, 1.0, None::<&ID2D1StrokeStyle>);
        rt.EndDraw(None, None)
    }
}

/// Renders the popup offscreen (no window) and returns (width, height, straight RGBA bytes, row-major, tightly packed).
/// Used by the tests; needs COM initialised on the calling thread for WIC (done here, result ignored).
pub fn render_to_rgba(model: &PopupModel, scale: f32, theme: &Theme) -> Option<(u32, u32, Vec<u8>)> {
    let (w, h) = measure(model, scale);
    if w <= 0 || h <= 0 {
        return None;
    }
    unsafe {
        // S_FALSE (already initialised) and RPC_E_CHANGED_MODE (other apartment) are both fine for WIC.
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
        let wic: IWICImagingFactory =
            CoCreateInstance::<Option<&windows::core::IUnknown>, IWICImagingFactory>(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER)
                .ok()?;
        let bitmap = wic
            .CreateBitmap(w as u32, h as u32, &GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnLoad)
            .ok()?;
        with_gfx(|g| {
            let props = D2D1_RENDER_TARGET_PROPERTIES {
                r#type: D2D1_RENDER_TARGET_TYPE_SOFTWARE,
                pixelFormat: D2D1_PIXEL_FORMAT { format: DXGI_FORMAT_B8G8R8A8_UNORM, alphaMode: D2D1_ALPHA_MODE_PREMULTIPLIED },
                dpiX: 96.0,
                dpiY: 96.0,
                usage: D2D1_RENDER_TARGET_USAGE_NONE,
                minLevel: D2D1_FEATURE_LEVEL_DEFAULT,
            };
            let rt = g.d2d.CreateWicBitmapRenderTarget(&bitmap, &props).ok()?;
            // ClearType needs an opaque target; grayscale keeps the output deterministic.
            rt.SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
            paint(&rt, g, model, scale, theme, w, h).ok()?;
            drop(rt);
            let rc = WICRect { X: 0, Y: 0, Width: w, Height: h };
            let lock = bitmap.Lock(&rc, WICBitmapLockRead.0 as u32).ok()?;
            let stride = lock.GetStride().ok()? as usize;
            let mut len = 0u32;
            let mut ptr: *mut u8 = std::ptr::null_mut();
            lock.GetDataPointer(&mut len, &mut ptr).ok()?;
            if ptr.is_null() || (len as usize) < stride * (h as usize - 1) + w as usize * 4 {
                return None;
            }
            let src = std::slice::from_raw_parts(ptr, len as usize);
            let mut out = Vec::with_capacity(w as usize * h as usize * 4);
            for y in 0..h as usize {
                for x in 0..w as usize {
                    let p = &src[y * stride + x * 4..y * stride + x * 4 + 4];
                    let (b, gch, r, a) = (p[0], p[1], p[2], p[3]);
                    let un = |c: u8| if a == 0 || a == 255 { c } else { ((c as u32 * 255 + a as u32 / 2) / a as u32).min(255) as u8 };
                    out.extend_from_slice(&[un(r), un(gch), un(b), a]);
                }
            }
            Some((w as u32, h as u32, out))
        })
        .flatten()
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// The window

static REGISTER: Once = Once::new();

unsafe extern "system" fn popup_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        // Never take activation (or focus) from the render window when clicked.
        WM_MOUSEACTIVATE => LRESULT(MA_NOACTIVATE as isize),
        WM_ERASEBKGND => LRESULT(1),
        // Painting is done synchronously in `show`; DWM keeps the surface, so just validate.
        WM_PAINT => {
            let _ = ValidateRect(Some(hwnd), None);
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// The candidate popup. Created lazily on first `show`, hidden by default, destroyed on drop.
pub struct CandPopup {
    owner: HWND,
    hwnd: HWND,
    hwnd_rt: Option<ID2D1HwndRenderTarget>,
    /// Screen rect and shape of what is currently shown (valid while `visible`).
    left: i32,
    top: i32,
    width: i32,
    height: i32,
    rows: usize,
    scale: f32,
    visible: bool,
}

impl CandPopup {
    pub fn new(owner: HWND) -> Self {
        CandPopup {
            owner,
            hwnd: HWND::default(),
            hwnd_rt: None,
            left: 0,
            top: 0,
            width: 0,
            height: 0,
            rows: 0,
            scale: 1.0,
            visible: false,
        }
    }

    fn ensure_window(&mut self) -> bool {
        if !self.hwnd.is_invalid() {
            return true;
        }
        unsafe {
            let hinst: HINSTANCE = match GetModuleHandleW(None::<PCWSTR>) {
                Ok(h) => HINSTANCE(h.0),
                Err(_) => return false,
            };
            REGISTER.call_once(|| {
                let wc = WNDCLASSEXW {
                    cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
                    lpfnWndProc: Some(popup_proc),
                    hInstance: hinst,
                    hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or(HCURSOR(std::ptr::null_mut())),
                    lpszClassName: w!("SwiftRightImeCandidates"),
                    ..Default::default()
                };
                // 0 when it already exists (another module instance); CreateWindowExW below then still works.
                let _ = RegisterClassExW(&wc);
            });
            // Owned popup: the owner keeps it above itself without making it topmost; WS_EX_NOACTIVATE + MA_NOACTIVATE
            // keep focus in the render window.
            let hwnd = match CreateWindowExW(
                WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
                w!("SwiftRightImeCandidates"),
                w!(""),
                WS_POPUP,
                0,
                0,
                1,
                1,
                Some(self.owner),
                None,
                Some(hinst),
                None,
            ) {
                Ok(h) => h,
                Err(_) => return false,
            };
            // Win11 rounds it; older systems ignore the attribute.
            let pref = DWMWCP_ROUND.0;
            let _ = DwmSetWindowAttribute(
                hwnd,
                DWMWA_WINDOW_CORNER_PREFERENCE,
                &pref as *const i32 as *const c_void,
                std::mem::size_of::<i32>() as u32,
            );
            self.hwnd = hwnd;
        }
        true
    }

    /// Shows (or updates) the popup with its top-left at screen pixel (`left`, `top`). Never activates.
    /// An empty model hides it.
    pub fn show(&mut self, model: &PopupModel, left: i32, top: i32, scale: f32, theme: &Theme) {
        if model.rows.is_empty() {
            self.hide();
            return;
        }
        if !self.ensure_window() {
            return;
        }
        let (w, h) = measure(model, scale);
        unsafe {
            let _ = SetWindowPos(self.hwnd, None, left, top, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }
        self.left = left;
        self.top = top;
        self.width = w;
        self.height = h;
        self.rows = model.rows.len();
        self.scale = scale;
        self.visible = true;
        if !self.paint_window(model, scale, theme, w, h) {
            // Target lost or never created; drop it so the next show recreates it.
            self.hwnd_rt = None;
        }
    }

    fn paint_window(&mut self, model: &PopupModel, scale: f32, theme: &Theme, w: i32, h: i32) -> bool {
        let hwnd = self.hwnd;
        let existing = self.hwnd_rt.clone();
        let rt = with_gfx(|g| unsafe {
            let size = D2D_SIZE_U { width: w as u32, height: h as u32 };
            let hrt = match existing {
                Some(r) => {
                    r.Resize(&size).ok()?;
                    r
                }
                None => {
                    let props = D2D1_RENDER_TARGET_PROPERTIES {
                        r#type: D2D1_RENDER_TARGET_TYPE_DEFAULT,
                        pixelFormat: D2D1_PIXEL_FORMAT { format: DXGI_FORMAT_UNKNOWN, alphaMode: D2D1_ALPHA_MODE_UNKNOWN },
                        dpiX: 96.0,
                        dpiY: 96.0,
                        usage: D2D1_RENDER_TARGET_USAGE_NONE,
                        minLevel: D2D1_FEATURE_LEVEL_DEFAULT,
                    };
                    let hp = D2D1_HWND_RENDER_TARGET_PROPERTIES {
                        hwnd,
                        pixelSize: size,
                        presentOptions: D2D1_PRESENT_OPTIONS_NONE,
                    };
                    g.d2d.CreateHwndRenderTarget(&props, &hp).ok()?
                }
            };
            let base: ID2D1RenderTarget = hrt.cast().ok()?;
            let ok = paint(&base, g, model, scale, theme, w, h).is_ok();
            Some((hrt, ok))
        })
        .flatten();
        match rt {
            Some((hrt, ok)) => {
                if ok {
                    self.hwnd_rt = Some(hrt);
                }
                ok
            }
            None => false,
        }
    }

    /// Hides the popup (no activation change). Safe to call when never shown.
    pub fn hide(&mut self) {
        self.visible = false;
        if !self.hwnd.is_invalid() {
            unsafe {
                let _ = ShowWindow(self.hwnd, SW_HIDE);
            }
        }
    }

    /// Row under screen point (x, y), or None when hidden or outside any row.
    pub fn hit(&self, x: i32, y: i32) -> Option<usize> {
        if !self.visible {
            return None;
        }
        hit_client(x - self.left, y - self.top, self.width, self.height, self.rows, self.scale)
    }
}

impl Drop for CandPopup {
    fn drop(&mut self) {
        // The render target references the window; release it first.
        self.hwnd_rt = None;
        if !self.hwnd.is_invalid() {
            unsafe {
                let _ = DestroyWindow(self.hwnd);
            }
            self.hwnd = HWND::default();
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------------

#[cfg(all(test, windows))]
mod tests {
    use super::*;
    use windows::core::BOOL;

    fn px_at(buf: &[u8], w: u32, x: i32, y: i32) -> [i32; 3] {
        let i = ((y as u32 * w + x as u32) * 4) as usize;
        [buf[i] as i32, buf[i + 1] as i32, buf[i + 2] as i32]
    }

    fn diff(a: [i32; 3], b: [i32; 3]) -> i32 {
        (a[0] - b[0]).abs() + (a[1] - b[1]).abs() + (a[2] - b[2]).abs()
    }

    fn luma(p: [i32; 3]) -> i32 {
        (p[0] * 299 + p[1] * 587 + p[2] * 114) / 1000
    }

    fn latin() -> PopupModel {
        PopupModel {
            rows: vec!["Hello".into(), "World".into(), "Candidate".into()],
            selected: Some(0),
            show_numbers: true,
            first_number: 1,
        }
    }

    fn yu_gothic_present() -> bool {
        unsafe {
            let Ok(f) = DWriteCreateFactory::<IDWriteFactory>(DWRITE_FACTORY_TYPE_SHARED) else { return false };
            let mut c: Option<IDWriteFontCollection> = None;
            if f.GetSystemFontCollection(&mut c, false).is_err() {
                return false;
            }
            let Some(c) = c else { return false };
            let (mut idx, mut exists) = (0u32, BOOL(0));
            c.FindFamilyName(w!("Yu Gothic"), &mut idx, &mut exists).is_ok() && exists.as_bool()
        }
    }

    /// Asserts the structural facts for one render and returns the sampled unselected-row background.
    fn check(model: &PopupModel, scale: f32, theme: &Theme, label: &str) -> [i32; 3] {
        let (w, h, buf) = render_to_rgba(model, scale, theme).unwrap_or_else(|| panic!("{label}: render failed"));
        assert!(w > 0 && h > 0, "{label}: empty image");
        assert_eq!(buf.len(), (w * h * 4) as usize, "{label}: buffer size");
        assert_eq!((w as i32, h as i32), measure(model, scale), "{label}: size vs measure");
        let rh = row_height(scale);
        let py = padding_y(scale);
        let sx = w as i32 - px(6.0, scale);
        let sel = model.selected.expect("model has a selection");
        let row_mid = |i: usize| py + i as i32 * rh + rh / 2;
        let other = (0..model.rows.len()).find(|&i| i != sel).expect("needs an unselected row");
        let sel_bg = px_at(&buf, w, sx, row_mid(sel));
        let bg = px_at(&buf, w, sx, row_mid(other));
        assert!(diff(sel_bg, bg) > 30, "{label}: selected bg {sel_bg:?} vs unselected {bg:?}");
        // Every row has ink (pixels away from its own background) in the text area.
        let tl = text_left(model, scale);
        for i in 0..model.rows.len() {
            let row_bg = if i == sel { sel_bg } else { bg };
            let (y0, y1) = (py + i as i32 * rh + 2, py + (i as i32 + 1) * rh - 2);
            let mut ink = 0;
            for y in y0..y1 {
                for x in tl..(w as i32 - px(8.0, scale)) {
                    if diff(px_at(&buf, w, x, y), row_bg) > 150 {
                        ink += 1;
                    }
                }
            }
            assert!(ink >= 5, "{label}: row {i} has only {ink} ink pixels");
        }
        bg
    }

    #[test]
    fn layout_math_is_consistent() {
        for s in [1.0f32, 1.5, 2.5] {
            let rh = row_height(s);
            let py = padding_y(s);
            assert!(rh > 0);
            let h = height_for(3, s);
            assert_eq!(h, 3 * rh + 2 * py);
            assert_eq!(hit_client(5, py + 1, 200, h, 3, s), Some(0));
            assert_eq!(hit_client(5, py + rh, 200, h, 3, s), Some(1));
            assert_eq!(hit_client(5, py + 3 * rh - 1, 200, h, 3, s), Some(2));
            assert_eq!(hit_client(5, 0, 200, h, 3, s), if py == 0 { Some(0) } else { None });
            assert_eq!(hit_client(5, h, 200, h, 3, s), None);
            assert_eq!(hit_client(-1, py + 1, 200, h, 3, s), None);
            assert_eq!(hit_client(200, py + 1, 200, h, 3, s), None);
        }
        assert_eq!(clamp_width(1, 1.0), 120);
        assert_eq!(clamp_width(9999, 2.0), 1200);
    }

    #[test]
    fn hidden_popup_has_no_hit_and_never_creates_a_window() {
        let p = CandPopup::new(HWND::default());
        assert_eq!(p.hit(0, 0), None);
        assert!(p.hwnd.is_invalid());
    }

    #[test]
    fn measure_is_clamped_and_height_matches_rows() {
        for s in [1.0f32, 2.5] {
            let (w, h) = measure(&latin(), s);
            assert_eq!(h, height_for(3, s));
            assert!(w >= px(120.0, s) && w <= px(600.0, s), "width {w} out of clamp at {s}");
            let long = PopupModel { rows: vec!["x".repeat(500)], ..latin() };
            assert_eq!(measure(&long, s).0, px(600.0, s));
        }
    }

    #[test]
    fn render_latin_light_dark_high_contrast_at_two_scales() {
        let accent = (0, 120, 215);
        let light = Theme { dark: false, high_contrast: false, accent };
        let dark = Theme { dark: true, high_contrast: false, accent };
        let hc = Theme { dark: false, high_contrast: true, accent };
        for scale in [1.0f32, 2.5] {
            let m = latin();
            let bl = check(&m, scale, &light, &format!("light@{scale}"));
            let bd = check(&m, scale, &dark, &format!("dark@{scale}"));
            check(&m, scale, &hc, &format!("hc@{scale}"));
            assert!(luma(bl) > luma(bd), "light bg {bl:?} must be brighter than dark bg {bd:?} at {scale}");
            // No-number variant and a different selection still render with ink.
            let m2 = PopupModel { show_numbers: false, selected: Some(2), ..latin() };
            check(&m2, scale, &light, &format!("light-nonum@{scale}"));
        }
    }

    #[test]
    fn render_cjk_rows_when_yu_gothic_is_installed() {
        if !yu_gothic_present() {
            eprintln!("render_cjk_rows: skipped CJK ink assertions, Yu Gothic is not installed on this machine");
            return;
        }
        let m = PopupModel {
            rows: vec!["日本語".into(), "変換候補".into(), "にほんご".into()],
            selected: Some(1),
            show_numbers: true,
            first_number: 1,
        };
        let accent = (0, 120, 215);
        for scale in [1.0f32, 2.5] {
            check(&m, scale, &Theme { dark: false, high_contrast: false, accent }, &format!("cjk-light@{scale}"));
            check(&m, scale, &Theme { dark: true, high_contrast: false, accent }, &format!("cjk-dark@{scale}"));
        }
    }
}
