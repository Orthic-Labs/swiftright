//! GPUI half of the F0 probe: one page per process, selected by `F0_PAGE` (default "w1"). Fonts are read from `F0_FONTS`
//! (default `.\fonts`: Tinos-Regular.ttf, SRProbeLatin-Regular.ttf, SRProbeGreek-Regular.ttf) and registered through
//! `TextSystem::add_fonts`, the same entry the renderer's swr_font_register uses.

use std::borrow::Cow;
use std::sync::atomic::{AtomicBool, Ordering};

use gpui::{
    black, canvas, div, fill, font, hsla, point, prelude::*, px, size, white, App, Application,
    Bounds, Context, Font, FontFallbacks, FontFeatures, FontStyle, FontWeight, IntoElement, Pixels,
    Point, Render, ShapedLine, SharedString, TextRun, TitlebarOptions, Window,
    WindowBackgroundAppearance, WindowBounds, WindowOptions,
};

#[link(name = "user32")]
extern "system" {
    fn SetProcessDpiAwarenessContext(context: isize) -> i32;
}

static TRACED: AtomicBool = AtomicBool::new(false);
const SAMPLE_X: f32 = 128.0;

struct StderrLog;
impl log::Log for StderrLog {
    fn enabled(&self, _m: &log::Metadata) -> bool {
        true
    }
    fn log(&self, r: &log::Record) {
        eprintln!("GPUILOG {} {}: {}", r.level(), r.target(), r.args());
    }
    fn flush(&self) {}
}
static LOGGER: StderrLog = StderrLog;

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    /// ShapedLine::paint (the renderer's path).
    Normal,
    /// Every glyph painted with Window::paint_glyph / paint_emoji at layout position + `track` logical px per glyph.
    Glyphs(f32),
}

struct Row {
    label: String,
    text: String,
    font: Font,
    size: f32,
    height: f32,
    kind: Kind,
}

fn mk(family: &str, weight: f32, italic: bool) -> Font {
    let mut f = font(family.to_string());
    f.weight = FontWeight(weight);
    if italic {
        f.style = FontStyle::Italic;
    }
    f
}

fn feat(f: &mut Font, tags: &[(&str, u32)]) {
    f.features = FontFeatures(std::sync::Arc::new(
        tags.iter().map(|(t, v)| (t.to_string(), *v)).collect(),
    ));
}

fn row(label: impl Into<String>, text: &str, f: Font, size: f32) -> Row {
    Row {
        label: label.into(),
        text: text.to_string(),
        font: f,
        size,
        height: (size * 1.4).ceil().max(18.0),
        kind: Kind::Normal,
    }
}

const SAMPLE: &str = "Hamburgefonstiv 0123 AVAWAY";
const SHORT: &str = "Hamburg Wag 0123";

fn weight_rows(family: &str, weights: &[f32], size: f32) -> Vec<Row> {
    weights
        .iter()
        .map(|w| {
            row(
                format!("{family} w{}", *w as i32),
                SAMPLE,
                mk(family, *w, false),
                size,
            )
        })
        .collect()
}

fn rows_for(page: &str) -> Vec<Row> {
    let mut r: Vec<Row> = Vec::new();
    match page {
        "w1" => r.extend(weight_rows(
            "Segoe UI Variable",
            &[100., 200., 300., 400., 500., 600., 700., 800., 900.],
            17.0,
        )),
        "w2" => {
            r.extend(weight_rows(
                "Segoe UI Variable Text",
                &[300., 400., 500., 600., 700.],
                17.0,
            ));
            r.extend(weight_rows(
                "Segoe UI Variable Small",
                &[400., 500., 600., 700.],
                17.0,
            ));
        }
        "w3" => {
            r.extend(weight_rows(
                "Segoe UI Variable Display",
                &[300., 400., 500., 600., 700.],
                17.0,
            ));
            r.extend(weight_rows("Segoe UI", &[300., 350., 400., 500.], 17.0));
        }
        "w4" => {
            r.extend(weight_rows("Segoe UI", &[600., 700., 800., 900.], 17.0));
            for fam in [
                "Segoe UI Light",
                "Segoe UI Semilight",
                "Segoe UI Semibold",
                "Segoe UI Black",
            ] {
                r.push(row(
                    format!("{fam} w400"),
                    SAMPLE,
                    mk(fam, 400., false),
                    17.0,
                ));
            }
        }
        "o1" | "o2" => {
            let fams: [&str; 2] = if page == "o1" {
                ["Segoe UI Variable", "Segoe UI Variable Small"]
            } else {
                ["Segoe UI Variable Text", "Segoe UI Variable Display"]
            };
            for fam in fams {
                for sz in [9.0f32, 16.0, 28.0] {
                    r.push(row(
                        format!("{fam} {sz}px w400"),
                        "Hamburgefonstiv",
                        mk(fam, 400., false),
                        sz,
                    ));
                }
            }
        }
        "s1" => {
            r.push(row("Tinos w400", SHORT, mk("Tinos", 400., false), 20.0));
            r.push(row(
                "Tinos w700 (Regular only)",
                SHORT,
                mk("Tinos", 700., false),
                20.0,
            ));
            r.push(row(
                "Tinos w400 italic",
                SHORT,
                mk("Tinos", 400., true),
                20.0,
            ));
            r.push(row(
                "Tinos w700 italic",
                SHORT,
                mk("Tinos", 700., true),
                20.0,
            ));
            r.push(row("Tinos w100", SHORT, mk("Tinos", 100., false), 20.0));
            r.push(row(
                "Segoe UI w400 italic",
                SHORT,
                mk("Segoe UI", 400., true),
                20.0,
            ));
            r.push(row(
                "Segoe UI Variable w400 italic",
                SHORT,
                mk("Segoe UI Variable", 400., true),
                20.0,
            ));
            r.push(row(
                "Segoe UI Variable w700 italic",
                SHORT,
                mk("Segoe UI Variable", 700., true),
                20.0,
            ));
            r.push(row(
                "Cascadia Mono w700 italic",
                SHORT,
                mk("Cascadia Mono", 700., true),
                20.0,
            ));
        }
        "e1" => {
            let e = "Hi \u{1F642}\u{1F600}\u{2764}\u{FE0F}\u{1F44D}\u{1F3FD}\u{1F1EE}\u{1F1F3} end";
            r.push(row("Segoe UI", e, mk("Segoe UI", 400., false), 20.0));
            r.push(row(
                "Tinos (no emoji glyphs)",
                e,
                mk("Tinos", 400., false),
                20.0,
            ));
            r.push(row(
                "Segoe UI Emoji",
                "\u{1F642}\u{1F600}\u{2764}\u{FE0F}\u{1F44D}\u{1F3FD}\u{1F9D1}\u{200D}\u{1F4BB}",
                mk("Segoe UI Emoji", 400., false),
                20.0,
            ));
            r.push(row(
                "Segoe UI Symbol",
                "\u{2713}\u{2717}\u{2600}\u{2660}\u{260E}\u{2B50}",
                mk("Segoe UI Symbol", 400., false),
                20.0,
            ));
            r.push(row(
                "Segoe UI 40px",
                "\u{1F642}\u{1F600}",
                mk("Segoe UI", 400., false),
                40.0,
            ));
        }
        "f1" => {
            let mut push = |label: &str, text: &str, primary: &str, fb: Option<Vec<&str>>| {
                let mut f = mk(primary, 400., false);
                if let Some(list) = fb {
                    f.fallbacks = Some(FontFallbacks::from_fonts(
                        list.iter().map(|s| s.to_string()).collect(),
                    ));
                }
                r.push(row(label, text, f, 20.0));
            };
            let g = "Ab \u{03B2}\u{03B3}";
            let j = "Ab \u{3042}\u{6F22}";
            push("Latin-only, no fallbacks", g, "SRProbeLatin", None);
            push(
                "fallbacks [SRProbeGreek] (PRIVATE)",
                g,
                "SRProbeLatin",
                Some(vec!["SRProbeGreek"]),
            );
            push(
                "fallbacks [Times New Roman]",
                g,
                "SRProbeLatin",
                Some(vec!["Times New Roman"]),
            );
            push(
                "fallbacks [Segoe UI Variable]",
                g,
                "SRProbeLatin",
                Some(vec!["Segoe UI Variable"]),
            );
            push("JA, no fallbacks", j, "SRProbeLatin", None);
            push(
                "JA fallbacks [MS Gothic]",
                j,
                "SRProbeLatin",
                Some(vec!["MS Gothic"]),
            );
            push(
                "JA fallbacks [Yu Gothic UI]",
                j,
                "SRProbeLatin",
                Some(vec!["Yu Gothic UI"]),
            );
            push(
                "JA fallbacks [SRProbeGreek] (PRIVATE)",
                j,
                "SRProbeLatin",
                Some(vec!["SRProbeGreek"]),
            );
        }
        "g1" => {
            let f = mk("Segoe UI Variable", 400., false);
            let t = "Hamburg AVAWAY \u{1F642}";
            r.push(row("A ShapedLine::paint", t, f.clone(), 20.0));
            let mut b = row("B glyph by glyph, +0", t, f.clone(), 20.0);
            b.kind = Kind::Glyphs(0.0);
            r.push(b);
            let mut c = row("C glyph by glyph, +4px", t, f.clone(), 20.0);
            c.kind = Kind::Glyphs(4.0);
            r.push(c);
            let mut d = row("D glyph by glyph, -1px", t, f.clone(), 20.0);
            d.kind = Kind::Glyphs(-1.0);
            r.push(d);
            let mut e = row("E Tinos, +2px", "Pulse Hub", mk("Tinos", 400., false), 24.0);
            e.kind = Kind::Glyphs(2.0);
            r.push(e);
            r.push(row(
                "F Tinos ShapedLine::paint",
                "Pulse Hub",
                mk("Tinos", 400., false),
                24.0,
            ));
        }
        "k1" => {
            let base = |fam: &str| mk(fam, 400., false);
            let mut f = base("Segoe UI Variable");
            r.push(row(
                "SUV default",
                "AVAWAY To Wa 1111 0000",
                f.clone(),
                20.0,
            ));
            feat(&mut f, &[("kern", 0)]);
            r.push(row("SUV kern=0", "AVAWAY To Wa 1111 0000", f.clone(), 20.0));
            let mut f = base("Segoe UI Variable");
            feat(&mut f, &[("tnum", 1)]);
            r.push(row("SUV tnum=1", "AVAWAY To Wa 1111 0000", f.clone(), 20.0));
            let mut f = base("Segoe UI Variable");
            feat(&mut f, &[("pnum", 1)]);
            r.push(row("SUV pnum=1", "AVAWAY To Wa 1111 0000", f.clone(), 20.0));
            let mut f = base("Segoe UI Variable");
            feat(&mut f, &[("kern", 0), ("tnum", 1)]);
            r.push(row(
                "SUV kern=0 tnum=1",
                "AVAWAY To Wa 1111 0000",
                f.clone(),
                20.0,
            ));
            r.push(row(
                "Tinos default",
                "AVAWAY To Wa 1111 0000",
                base("Tinos"),
                20.0,
            ));
            let mut f = base("Tinos");
            feat(&mut f, &[("kern", 0)]);
            r.push(row("Tinos kern=0", "AVAWAY To Wa 1111 0000", f, 20.0));
            let mut f = base("Tinos");
            feat(&mut f, &[("tnum", 1)]);
            r.push(row("Tinos tnum=1", "AVAWAY To Wa 1111 0000", f, 20.0));
        }
        "sz1" | "sz2" => {
            let sizes: &[f32] = if page == "sz1" {
                &[13., 18., 20., 24., 28.]
            } else {
                &[31., 32., 36., 40.]
            };
            for s in sizes {
                r.push(row(
                    format!("Tinos {s}px"),
                    "Pulse Hub Hxg",
                    mk("Tinos", 400., false),
                    *s,
                ));
            }
        }
        _ => {}
    }
    r
}

fn run_of(text: &str, f: &Font) -> TextRun {
    TextRun {
        len: text.len(),
        font: f.clone(),
        color: black(),
        background_color: None,
        underline: None,
        strikethrough: None,
    }
}

fn shape(window: &mut Window, text: &str, f: &Font, size: f32) -> ShapedLine {
    window.text_system().shape_line(
        SharedString::from(text.to_string()),
        px(size),
        &[run_of(text, f)],
        None,
    )
}

fn trace_line(page: &str, label: &str, f: &Font, text: &str, line: &ShapedLine, window: &Window) {
    let ts = window.text_system();
    let size_px: f32 = line.font_size.into();
    let width: f32 = line.width.into();
    let asc: f32 = line.ascent.into();
    let desc: f32 = line.descent.into();
    eprintln!(
        "ROW page={page} label=[{label}] family=[{}] req_weight={} style={:?} features={:?} fallbacks={:?} size={size_px} width={width:.3} width_per_px={:.5} ascent={asc:.4} descent={desc:.4} runs={}",
        f.family,
        f.weight.0,
        f.style,
        f.features,
        f.fallbacks.as_ref().map(|x| x.fallback_list().to_vec()),
        width / size_px.max(0.001),
        line.runs.len()
    );
    eprintln!("ROWTEXT page={page} label=[{label}] text={text:?}");
    for (ri, run) in line.runs.iter().enumerate() {
        let known = ts
            .get_font_for_id(run.font_id)
            .map(|x| format!("{}/{}", x.family, x.weight.0))
            .unwrap_or_else(|| "(not a resolved request: fallback face)".to_string());
        let mut ids = String::new();
        let mut emoji = 0;
        let mut notdef = 0;
        for g in run.glyphs.iter() {
            let id = format!("{:?}", g.id)
                .replace("GlyphId(", "")
                .replace(')', "");
            if id == "0" {
                notdef += 1;
            }
            if g.is_emoji {
                emoji += 1;
            }
            let x: f32 = g.position.x.into();
            ids.push_str(&format!(
                "{id}@{x:.2}{} ",
                if g.is_emoji { "E" } else { "" }
            ));
        }
        eprintln!(
            "RUN page={page} label=[{label}] run={ri} font_id={} request={known} glyphs={} emoji={emoji} notdef={notdef} :: {ids}",
            run.font_id.0,
            run.glyphs.len()
        );
    }
}

fn paint_glyphs(
    line: &ShapedLine,
    origin: Point<Pixels>,
    line_h: f32,
    track: f32,
    window: &mut Window,
) {
    let asc: f32 = line.ascent.into();
    let desc: f32 = line.descent.into();
    let baseline = (line_h - asc - desc) / 2.0 + asc;
    let mut n = 0.0f32;
    for run in line.runs.iter() {
        for g in run.glyphs.iter() {
            let o = point(
                origin.x + g.position.x + px(track * n),
                origin.y + px(baseline),
            );
            if g.is_emoji {
                let _ = window.paint_emoji(o, run.font_id, g.id, line.font_size);
            } else {
                let _ = window.paint_glyph(o, run.font_id, g.id, line.font_size, black());
            }
            n += 1.0;
        }
    }
}

fn paint_page(page: &str, bounds: Bounds<Pixels>, window: &mut Window, cx: &mut App) {
    window.paint_quad(fill(bounds, white()));
    let first = !TRACED.swap(true, Ordering::SeqCst);
    let scale = window.scale_factor();
    if first {
        eprintln!(
            "PAGE {page} scale_factor={scale} bounds_logical={:?}",
            bounds
        );
    }
    let label_font = mk("Segoe UI", 400., false);
    let grey = hsla(0.0, 0.0, 0.35, 1.0);
    if page == "snap" {
        // Tinos 28 and Segoe UI Variable 28 at ten y fractions: where does the baseline land? Column i has origin.y = 12 + i/10.
        for (fi, fam) in ["Tinos", "Segoe UI Variable"].iter().enumerate() {
            let f = mk(fam, 400., false);
            for i in 0..10 {
                let oy = 12.0 + fi as f32 * 100.0 + i as f32 * 0.1;
                let ox = 8.0 + i as f32 * 40.0;
                let line = shape(window, "Hxg", &f, 28.0);
                if first && i == 0 {
                    trace_line(page, &format!("{fam} 28px"), &f, "Hxg", &line, window);
                }
                let asc: f32 = line.ascent.into();
                let desc: f32 = line.descent.into();
                let lh = 40.0f32;
                let baseline_logical = oy + (lh - asc - desc) / 2.0 + asc;
                if first {
                    eprintln!("SNAP family=[{fam}] col={i} origin_y={oy:.2} baseline_logical={baseline_logical:.4} baseline_phys={:.3} floor_phys={}", baseline_logical * scale, (baseline_logical * scale).floor());
                }
                let _ = line.paint(
                    point(bounds.origin.x + px(ox), bounds.origin.y + px(oy)),
                    px(lh),
                    window,
                    cx,
                );
            }
        }
        return;
    }
    let mut y = 4.0f32;
    for r in rows_for(page) {
        // label
        let lrun = TextRun {
            len: r.label.len(),
            font: label_font.clone(),
            color: grey,
            background_color: None,
            underline: None,
            strikethrough: None,
        };
        let lline = window.text_system().shape_line(
            SharedString::from(r.label.clone()),
            px(9.0),
            &[lrun],
            None,
        );
        let _ = lline.paint(
            point(
                bounds.origin.x + px(4.0),
                bounds.origin.y + px(y + (r.height - 12.0) / 2.0),
            ),
            px(12.0),
            window,
            cx,
        );
        // sample
        let line = shape(window, &r.text, &r.font, r.size);
        if first {
            trace_line(page, &r.label, &r.font, &r.text, &line, window);
            eprintln!("LAYOUT page={page} label=[{}] row_top_logical={y} row_height={} sample_x_logical={SAMPLE_X}", r.label, r.height);
        }
        let origin = point(bounds.origin.x + px(SAMPLE_X), bounds.origin.y + px(y));
        match r.kind {
            Kind::Normal => {
                let _ = line.paint(origin, px(r.height), window, cx);
            }
            Kind::Glyphs(track) => paint_glyphs(&line, origin, r.height, track, window),
        }
        y += r.height + 2.0;
    }
}

struct PageView {
    page: String,
}

impl Render for PageView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let page = self.page.clone();
        div().size_full().child(
            canvas(
                |_b, _w, _c| (),
                move |bounds, _, window, cx| paint_page(&page, bounds, window, cx),
            )
            .size_full(),
        )
    }
}

fn load_fonts(cx: &mut App) {
    let dir = std::env::var("F0_FONTS").unwrap_or_else(|_| "fonts".to_string());
    for name in [
        "Tinos-Regular.ttf",
        "SRProbeLatin-Regular.ttf",
        "SRProbeGreek-Regular.ttf",
    ] {
        let path = std::path::Path::new(&dir).join(name);
        match std::fs::read(&path) {
            Ok(bytes) => {
                let leaked: &'static [u8] = Box::leak(bytes.into_boxed_slice());
                let r = cx.text_system().add_fonts(vec![Cow::Borrowed(leaked)]);
                eprintln!(
                    "FONT add_fonts {} ({} bytes) -> {:?}",
                    path.display(),
                    leaked.len(),
                    r.map_err(|e| e.to_string())
                );
            }
            Err(e) => eprintln!("FONT cannot read {}: {e}", path.display()),
        }
    }
    let names = cx.text_system().all_font_names();
    let want = [
        "Segoe UI",
        "Cascadia",
        "Yu Gothic",
        "MS Gothic",
        "Sitka",
        "Bahnschrift",
        "Consolas",
        "Tinos",
        "SRProbe",
        "Meiryo",
        "Malgun",
        "Nirmala",
        "Emoji",
        "Times New Roman",
        "Segoe Fluent",
    ];
    let mut hits: Vec<String> = names
        .iter()
        .filter(|n| want.iter().any(|w| n.contains(w)))
        .cloned()
        .collect();
    hits.sort();
    eprintln!(
        "FONT all_font_names total={} interesting={:?}",
        names.len(),
        hits
    );
}

pub fn run() {
    let _ = log::set_logger(&LOGGER).map(|()| log::set_max_level(log::LevelFilter::Debug));
    let dpi_rc = unsafe { SetProcessDpiAwarenessContext(-4) };
    eprintln!(
        "START f0-text-facts pid={} SetProcessDpiAwarenessContext(-4)->{dpi_rc}",
        std::process::id()
    );
    // Safety net: the capture script kills the process; an orphan exits by itself.
    std::thread::spawn(|| {
        std::thread::sleep(std::time::Duration::from_secs(90));
        std::process::exit(0);
    });
    let page = std::env::var("F0_PAGE").unwrap_or_else(|_| "w1".to_string());
    Application::new().run(move |cx: &mut App| {
        load_fonts(cx);
        let bounds = Bounds::centered(None, size(px(420.0), px(250.0)), cx);
        let p = page.clone();
        let opened = cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                titlebar: Some(TitlebarOptions {
                    title: Some("f0-text-facts".into()),
                    ..Default::default()
                }),
                window_background: WindowBackgroundAppearance::Opaque,
                ..Default::default()
            },
            move |_, cx| cx.new(|_| PageView { page: p }),
        );
        if let Err(e) = opened {
            eprintln!("open_window failed: {e:?}");
            cx.quit();
        }
        cx.activate(true);
    });
}
