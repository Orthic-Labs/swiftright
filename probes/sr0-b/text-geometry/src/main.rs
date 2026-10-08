//! SR0-B text-geometry probe (Windows x64).
//!
//! A SwiftRight-owned retained text node, held as plain data outside GPUI view
//! state, is measured through GPUI's text system (synchronous, cached), committed
//! in physical pixels, painted by a GPUI canvas, and published as an AccessKit
//! MultilineTextInput with one TextRun child per wrapped line. A timer cycles the
//! proposed width across a wrap threshold; each phase waits for the UIA driver
//! (ack file) before advancing. Every AccessKit action request is logged.

#[cfg(windows)]
mod probe {
    use accesskit::{
        Action, ActionData, ActionHandler, ActionRequest, ActivationHandler, Node, NodeId, Rect,
        Role, TextDirection, TextPosition, TextSelection, TreeId, TreeInfo, TreeUpdate,
    };
    use accesskit_windows::{HWND, SubclassingAdapter};
    use gpui::{
        App, Application, Bounds, Context, IntoElement, Pixels, Render, SharedString, TextAlign,
        TextRun, Window, WindowBounds, WindowHandle, WindowOptions, WrappedLine, black, canvas,
        div, fill, font, hsla, point, prelude::*, px, size,
    };
    use raw_window_handle::{HasWindowHandle, RawWindowHandle};
    use std::{
        collections::HashMap,
        ffi::c_void,
        fs::{File, OpenOptions},
        io::Write,
        path::PathBuf,
        sync::{Arc, Mutex, OnceLock},
        time::{Duration, Instant},
    };

    const FONT_FAMILY: &str = "Segoe UI";
    const FONT_PX: f32 = 16.0;
    const LINE_PX: f32 = 24.0;
    const PAD_PX: f32 = 12.0;
    const TEXT: &str =
        "Alpha beta 日本語のテキスト 🙂 gamma delta 漢字 epsilon zeta 🙂🙂 eta theta iota kappa.";
    /// Proposed text widths (logical px). Phases cycle through them across the wrap threshold.
    const WIDTHS: [f32; 3] = [260.0, 180.0, 340.0];
    /// Width index per phase. Phases 3 and 4 revisit widths 0 and 1 (must hit the cache).
    const PHASE_WIDTH: [usize; 5] = [0, 1, 2, 0, 1];
    const CARET_START: &str = "beta";
    /// Selection driven by UIA `TextPatternRange.Select` in phase 0.
    const SELECT_LABEL: &str = "Alpha";
    const ROOT_ID: NodeId = NodeId(1);
    const INPUT_ID: NodeId = NodeId(2);
    const RUN_BASE: u64 = 100;

    static LOG: OnceLock<Mutex<File>> = OnceLock::new();

    fn log(line: impl AsRef<str>) {
        let line = line.as_ref();
        eprintln!("{line}");
        if let Some(file) = LOG.get() {
            if let Ok(mut f) = file.lock() {
                let _ = writeln!(f, "{line}");
                let _ = f.flush();
            }
        }
    }

    fn find_range(chars: &[char], sub: &str) -> (usize, usize) {
        let sub: Vec<char> = sub.chars().collect();
        for i in 0..=chars.len() - sub.len() {
            if chars[i..i + sub.len()] == sub[..] {
                return (i, i + sub.len());
            }
        }
        panic!("substring not in TEXT");
    }

    /// Five sample ranges: ASCII word, CJK run, emoji, multi-word span, word at end.
    fn sample_ranges(chars: &[char]) -> Vec<(&'static str, usize, usize)> {
        let mut out = Vec::new();
        for label in ["Alpha", "日本語", "🙂", "gamma delta", "kappa."] {
            let (a, b) = find_range(chars, label);
            out.push((label, a, b));
        }
        out
    }

    /// Word starts: a non-space char that follows a space, or any CJK/emoji char,
    /// or that follows one. Each CJK/emoji char is its own word.
    fn word_starts_of(chars: &[char]) -> Vec<bool> {
        let is_wide = |c: char| (c as u32) >= 0x3000;
        (0..chars.len())
            .map(|i| {
                let c = chars[i];
                if c.is_whitespace() {
                    false
                } else if i == 0 {
                    true
                } else {
                    let p = chars[i - 1];
                    p.is_whitespace() || is_wide(c) || is_wide(p)
                }
            })
            .collect()
    }

    /// Logical-px geometry for one character: `line` is the visual line, x0/x1 are
    /// line-local. Logical px in `Measured`; physical px in `Committed`.
    #[derive(Clone, Copy, Debug)]
    struct Cell {
        line: usize,
        x0: f32,
        x1: f32,
    }

    /// Result of synchronous measurement. `wrapped` is GPUI's retained shaped handle.
    #[derive(Clone)]
    struct Measured {
        wrapped: WrappedLine,
        cells: Vec<Cell>,
        line_first: Vec<usize>,
        line_len: Vec<usize>,
        line_width: Vec<f32>,
        line_text: Vec<String>,
        word_start: Vec<bool>,
        char_at_byte: Vec<usize>,
        ascent: f32,
        size: (f32, f32),
        ms: f64,
    }

    fn measure(window: &Window, width: f32) -> Measured {
        let t0 = Instant::now();
        let chars: Vec<char> = TEXT.chars().collect();
        let run = TextRun {
            len: TEXT.len(),
            font: font(FONT_FAMILY),
            color: black(),
            background_color: None,
            underline: None,
            strikethrough: None,
        };
        let mut lines = window
            .text_system()
            .shape_text(
                SharedString::from(TEXT),
                px(FONT_PX),
                &[run],
                Some(px(width)),
                None,
            )
            .expect("shape_text failed");
        let wrapped = lines.remove(0);
        let layout = wrapped.unwrapped_layout.clone();

        // GPUI convention (see LineLayout::index_for_position): each wrap boundary
        // glyph is the first glyph of the new visual line.
        let mut starts = vec![0usize];
        for b in wrapped.wrap_boundaries.iter() {
            starts.push(layout.runs[b.run_ix].glyphs[b.glyph_ix].index);
        }

        let mut cells = Vec::with_capacity(chars.len());
        let mut line_first: Vec<usize> = Vec::new();
        let mut line_start_x: Vec<f32> = Vec::new();
        let mut line_len: Vec<usize> = Vec::new();
        let mut line_text: Vec<String> = Vec::new();
        let mut char_at_byte = vec![usize::MAX; TEXT.len()];
        let mut byte = 0usize;
        for (i, ch) in chars.iter().enumerate() {
            let len = ch.len_utf8();
            let line = starts
                .iter()
                .rposition(|&s| s <= byte)
                .expect("line for byte");
            if line == line_first.len() {
                line_first.push(i);
                line_start_x.push(f32::from(layout.x_for_index(byte)));
                line_len.push(0);
                line_text.push(String::new());
            }
            let xs = line_start_x[line];
            let x0 = f32::from(layout.x_for_index(byte)) - xs;
            let x1 = f32::from(layout.x_for_index(byte + len)) - xs;
            cells.push(Cell { line, x0, x1 });
            line_len[line] += 1;
            line_text[line].push(*ch);
            for k in 0..len {
                char_at_byte[byte + k] = i;
            }
            byte += len;
        }

        let mut line_width = vec![0f32; line_first.len()];
        for c in &cells {
            if c.x1 > line_width[c.line] {
                line_width[c.line] = c.x1;
            }
        }
        let width_max = line_width.iter().cloned().fold(0f32, f32::max);
        let size = (width_max, line_first.len() as f32 * LINE_PX);
        Measured {
            wrapped,
            cells,
            line_first,
            line_len,
            line_width,
            line_text,
            word_start: word_starts_of(&chars),
            char_at_byte,
            ascent: f32::from(layout.ascent),
            size,
            ms: t0.elapsed().as_secs_f64() * 1000.0,
        }
    }

    /// Physical-pixel commit. `cells` are physical, line-local; origin = PAD * scale.
    #[derive(Clone)]
    struct Committed {
        version: u64,
        width: f32,
        scale: f32,
        m: Measured,
        cells: Vec<Cell>,
        line_top: Vec<f32>,
        line_w: Vec<f32>,
        anchor: usize,
        focus: usize,
    }

    fn commit(m: Measured, width: f32, scale: f32, anchor: usize, focus: usize, version: u64) -> Committed {
        let cells: Vec<Cell> = m
            .cells
            .iter()
            .map(|c| Cell { line: c.line, x0: c.x0 * scale, x1: c.x1 * scale })
            .collect();
        let line_top: Vec<f32> = (0..m.line_first.len())
            .map(|k| k as f32 * LINE_PX * scale)
            .collect();
        let line_w: Vec<f32> = m.line_width.iter().map(|w| w * scale).collect();
        Committed { version, width, scale, m, cells, line_top, line_w, anchor, focus }
    }

    impl Committed {
        fn origin(&self) -> f32 {
            PAD_PX * self.scale
        }
        fn lines(&self) -> usize {
            self.line_top.len()
        }
        fn n_chars(&self) -> usize {
            self.cells.len()
        }
        /// Physical client-px rect of one character cell.
        fn cell_rect(&self, i: usize) -> [f32; 4] {
            let c = self.cells[i];
            [
                self.origin() + c.x0,
                self.origin() + self.line_top[c.line],
                c.x1 - c.x0,
                LINE_PX * self.scale,
            ]
        }
        /// Physical caret rect at char index `i` (left edge of that char, or end of text).
        fn caret_rect(&self, i: usize) -> [f32; 4] {
            let (line, x) = if i < self.cells.len() {
                (self.cells[i].line, self.cells[i].x0)
            } else {
                let last = self.cells[self.cells.len() - 1];
                (last.line, last.x1)
            };
            [
                self.origin() + x,
                self.origin() + self.line_top[line],
                self.scale,
                LINE_PX * self.scale,
            ]
        }
        /// Probe-owned hit test: physical client point -> char index.
        fn index_for_point(&self, x: f32, y: f32) -> usize {
            let lh = LINE_PX * self.scale;
            let line = (((y - self.origin()) / lh).floor().max(0.0) as usize).min(self.lines() - 1);
            for (i, c) in self.cells.iter().enumerate() {
                if c.line == line && x < self.origin() + c.x1 {
                    return i;
                }
            }
            self.cells
                .iter()
                .rposition(|c| c.line == line)
                .map(|i| i + 1)
                .unwrap_or(0)
        }
    }

    /// Plain, Send data published to AccessKit (no GPUI handles).
    #[derive(Clone, Default, Debug)]
    struct AxLine {
        node: u64,
        text: String,
        lengths: Vec<u8>,
        positions: Vec<f32>,
        widths: Vec<f32>,
        word_starts: Vec<u8>,
        bounds: [f64; 4],
        first: usize,
    }

    #[derive(Clone, Default, Debug)]
    struct AxData {
        version: u64,
        lines: Vec<AxLine>,
        input_bounds: [f64; 4],
        anchor: usize,
        focus: usize,
    }

    fn build_ax(c: &Committed) -> AxData {
        let mut lines = Vec::new();
        for k in 0..c.lines() {
            let first = c.m.line_first[k];
            let text = c.m.line_text[k].clone();
            let mut lengths = Vec::new();
            let mut positions = Vec::new();
            let mut widths = Vec::new();
            let mut word_starts = Vec::new();
            for (j, ch) in text.chars().enumerate() {
                let cell = c.cells[first + j];
                lengths.push(ch.len_utf8() as u8);
                positions.push(cell.x0);
                widths.push(cell.x1 - cell.x0);
                if c.m.word_start[first + j] {
                    word_starts.push(j as u8);
                }
            }
            let x0 = c.origin() as f64;
            let y0 = (c.origin() + c.line_top[k]) as f64;
            let bounds = [x0, y0, x0 + c.line_w[k] as f64, y0 + (LINE_PX * c.scale) as f64];
            lines.push(AxLine {
                node: RUN_BASE + k as u64,
                text,
                lengths,
                positions,
                widths,
                word_starts,
                bounds,
                first,
            });
        }
        let input_w = ((2.0 * PAD_PX + c.width) * c.scale) as f64;
        let input_h = ((2.0 * PAD_PX + c.lines() as f32 * LINE_PX) * c.scale) as f64;
        AxData {
            version: c.version,
            lines,
            input_bounds: [0.0, 0.0, input_w, input_h],
            anchor: c.anchor,
            focus: c.focus,
        }
    }

    fn rect(r: [f64; 4]) -> Rect {
        Rect { x0: r[0], y0: r[1], x1: r[2], y1: r[3] }
    }

    fn text_position(ax: &AxData, c: usize) -> TextPosition {
        for l in &ax.lines {
            if c >= l.first && c < l.first + l.lengths.len() {
                return TextPosition { node: NodeId(l.node), character_index: c - l.first };
            }
        }
        let l = ax.lines.last().expect("at least one line");
        TextPosition { node: NodeId(l.node), character_index: l.lengths.len() }
    }

    fn global_char(ax: &AxData, node: u64, idx: usize) -> usize {
        for l in &ax.lines {
            if l.node == node {
                return l.first + idx.min(l.lengths.len());
            }
        }
        0
    }

    /// AccessKit-published rect (physical, client-relative) for char `i`, with its line.
    fn ax_char_rect(ax: &AxData, i: usize) -> (usize, [f32; 4]) {
        for (k, l) in ax.lines.iter().enumerate() {
            if i >= l.first && i < l.first + l.lengths.len() {
                let j = i - l.first;
                let x = l.bounds[0] as f32 + l.positions[j];
                let y = l.bounds[1] as f32;
                let h = (l.bounds[3] - l.bounds[1]) as f32;
                return (k, [x, y, l.widths[j], h]);
            }
        }
        (0, [f32::NAN; 4])
    }

    /// Build the AccessKit tree from plain data. Callable from any thread.
    fn build_tree(ax: &AxData) -> TreeUpdate {
        let mut nodes: Vec<(NodeId, Node)> = Vec::new();

        let mut root = Node::new(Role::Window);
        root.set_label("SR0-B text geometry window");
        root.set_children(vec![INPUT_ID]);
        nodes.push((ROOT_ID, root));

        let mut input = Node::new(Role::MultilineTextInput);
        input.set_label("SR0-B text geometry input");
        input.set_value(TEXT);
        input.add_action(Action::Focus);
        input.add_action(Action::SetValue);
        input.add_action(Action::SetTextSelection);
        input.set_bounds(rect(ax.input_bounds));
        let run_ids: Vec<NodeId> = ax.lines.iter().map(|l| NodeId(l.node)).collect();
        input.set_children(run_ids);
        input.set_text_selection(TextSelection {
            anchor: text_position(ax, ax.anchor),
            focus: text_position(ax, ax.focus),
        });
        nodes.push((INPUT_ID, input));

        for l in &ax.lines {
            let mut run = Node::new(Role::TextRun);
            run.set_value(l.text.as_str());
            run.set_text_direction(TextDirection::LeftToRight);
            run.set_character_lengths(l.lengths.clone());
            run.set_character_positions(l.positions.clone());
            run.set_character_widths(l.widths.clone());
            run.set_word_starts(l.word_starts.clone());
            run.set_bounds(rect(l.bounds));
            nodes.push((NodeId(l.node), run));
        }

        TreeUpdate {
            nodes,
            tree: Some(TreeInfo::new(ROOT_ID)),
            tree_id: TreeId::ROOT,
            focus: INPUT_ID,
        }
    }

    #[derive(Debug)]
    enum AxEvent {
        Focus,
        Select { anchor: (u64, usize), focus: (u64, usize) },
        SetValue(String),
        Other(String),
    }

    struct Activation {
        ax: Arc<Mutex<AxData>>,
    }

    impl ActivationHandler for Activation {
        fn request_initial_tree(&mut self) -> Option<TreeUpdate> {
            let ax = self.ax.lock().unwrap().clone();
            log(format!("ACTIVATION initial_tree version={} lines={}", ax.version, ax.lines.len()));
            Some(build_tree(&ax))
        }
    }

    /// Must be Send. Logs and enqueues only; never calls into GPUI.
    struct Actions {
        events: Arc<Mutex<Vec<AxEvent>>>,
    }

    impl ActionHandler for Actions {
        fn do_action(&mut self, request: ActionRequest) {
            let event = match (&request.action, &request.data) {
                (Action::Focus, _) => AxEvent::Focus,
                (Action::SetTextSelection, Some(ActionData::SetTextSelection(sel))) => {
                    AxEvent::Select {
                        anchor: (sel.anchor.node.0, sel.anchor.character_index),
                        focus: (sel.focus.node.0, sel.focus.character_index),
                    }
                }
                (Action::SetValue, Some(ActionData::Value(v))) => AxEvent::SetValue(v.to_string()),
                (other, _) => AxEvent::Other(format!("{other:?}")),
            };
            log(format!("ACTION {event:?} target={:?}", request.target_node));
            self.events.lock().unwrap().push(event);
        }
    }

    /// Paint-time rects, physical client px, one per char (x, y, w, h).
    #[derive(Clone, Default)]
    struct PaintSnap {
        version: u64,
        chars: Vec<[f32; 4]>,
    }

    /// Merge consecutive same-line char rects into one rect per visual line.
    fn merge_lines(items: &[(usize, [f32; 4])]) -> Vec<[f32; 4]> {
        let mut out: Vec<(usize, [f32; 4])> = Vec::new();
        for (line, r) in items {
            if let Some((l, last)) = out.last_mut() {
                if *l == *line {
                    let left = last[0].min(r[0]);
                    let right = (last[0] + last[2]).max(r[0] + r[2]);
                    *last = [left, last[1], right - left, last[3]];
                    continue;
                }
            }
            out.push((*line, *r));
        }
        out.into_iter().map(|(_, r)| r).collect()
    }

    fn fmt_rects(rs: &[[f32; 4]]) -> String {
        if rs.is_empty() {
            return "none".to_string();
        }
        rs.iter()
            .map(|r| format!("{:.2},{:.2},{:.2},{:.2}", r[0], r[1], r[2], r[3]))
            .collect::<Vec<_>>()
            .join("|")
    }

    fn max_err(a: &[[f32; 4]], b: &[[f32; 4]]) -> f32 {
        if a.len() != b.len() {
            return f32::INFINITY;
        }
        let mut m = 0f32;
        for (p, q) in a.iter().zip(b) {
            for k in 0..4 {
                m = m.max((p[k] - q[k]).abs());
            }
        }
        m
    }

    /// Paints the committed snapshot through GPUI and records paint-time rects.
    fn paint_committed(
        c: &Committed,
        bounds: Bounds<Pixels>,
        window: &mut Window,
        cx: &mut App,
        snap: &Arc<Mutex<PaintSnap>>,
    ) {
        let s = window.scale_factor();
        let text_origin = point(bounds.origin.x + px(PAD_PX), bounds.origin.y + px(PAD_PX));

        let (a, b) = (c.anchor.min(c.focus), c.anchor.max(c.focus));
        if a < b {
            let items: Vec<(usize, [f32; 4])> = (a..b).map(|i| (c.cells[i].line, c.cell_rect(i))).collect();
            for r in merge_lines(&items) {
                let quad = Bounds {
                    origin: point(
                        bounds.origin.x + px(r[0] / c.scale),
                        bounds.origin.y + px(r[1] / c.scale),
                    ),
                    size: size(px(r[2] / c.scale), px(LINE_PX)),
                };
                window.paint_quad(fill(quad, hsla(0.6, 0.8, 0.6, 0.35)));
            }
        }

        c.m.wrapped
            .paint(text_origin, px(LINE_PX), TextAlign::Left, None, window, cx)
            .expect("WrappedLine::paint failed");

        let cr = c.caret_rect(c.focus);
        let caret = Bounds {
            origin: point(bounds.origin.x + px(cr[0] / c.scale), bounds.origin.y + px(cr[1] / c.scale)),
            size: size(px(1.5), px(LINE_PX)),
        };
        window.paint_quad(fill(caret, black()));

        // Paint-time rects: GPUI-shaped cell geometry mapped with the paint-time origin and scale.
        let ox = f32::from(bounds.origin.x) + PAD_PX;
        let oy = f32::from(bounds.origin.y) + PAD_PX;
        let chars: Vec<[f32; 4]> = c
            .m
            .cells
            .iter()
            .map(|cell| {
                [
                    (ox + cell.x0) * s,
                    (oy + cell.line as f32 * LINE_PX) * s,
                    (cell.x1 - cell.x0) * s,
                    LINE_PX * s,
                ]
            })
            .collect();
        *snap.lock().unwrap() = PaintSnap { version: c.version, chars };
    }

    fn hwnd_of(window: &Window) -> HWND {
        let handle = HasWindowHandle::window_handle(window)
            .expect("gpui window has no native window handle");
        match handle.as_raw() {
            RawWindowHandle::Win32(h) => HWND(h.hwnd.get() as *mut c_void),
            other => panic!("expected a Win32 window handle, got {other:?}"),
        }
    }

    struct ProbeView {
        adapter: Option<SubclassingAdapter>,
        ax: Arc<Mutex<AxData>>,
        events: Arc<Mutex<Vec<AxEvent>>>,
        paint: Arc<Mutex<PaintSnap>>,
        cache: HashMap<(u32, u32), Measured>,
        hits: u32,
        misses: u32,
        measure_calls: u32,
        committed: Option<Committed>,
        version: u64,
        anchor: usize,
        focus: usize,
        ranges: Vec<(&'static str, usize, usize)>,
        phase: usize,
        commit_tick: Option<u64>,
        ready: bool,
        ready_tick: u64,
        tick: u64,
        run_dir: PathBuf,
        done: bool,
    }

    impl ProbeView {
        fn width_for(phase: usize) -> f32 {
            WIDTHS[PHASE_WIDTH[phase]]
        }

        /// Synchronous measurement through the cache, then commit and publish.
        fn commit_width(&mut self, window: &mut Window, cx: &mut Context<Self>, width: f32, phase: Option<usize>) {
            let scale = window.scale_factor();
            let key = (width.to_bits(), scale.to_bits());
            self.measure_calls += 1;
            if self.cache.contains_key(&key) {
                self.hits += 1;
                log(format!("MEASURE phase={phase:?} width={width} scale={scale} cache=hit sync=true"));
            } else {
                self.misses += 1;
                let m = measure(window, width);
                log(format!(
                    "MEASURE phase={phase:?} width={width} scale={scale} cache=miss sync=true ms={:.3} lines={} size={:.1}x{:.1}",
                    m.ms,
                    m.line_first.len(),
                    m.size.0,
                    m.size.1
                ));
                self.cache.insert(key, m);
            }
            let m = self.cache[&key].clone();
            self.publish(window, cx, m, width, scale, phase);
        }

        /// Commit physical geometry, update the plain AX snapshot, push the AccessKit tree.
        fn publish(&mut self, window: &mut Window, cx: &mut Context<Self>, m: Measured, width: f32, scale: f32, phase: Option<usize>) {
            self.version += 1;
            let c = commit(m, width, scale, self.anchor, self.focus, self.version);
            let ax = build_ax(&c);
            *self.ax.lock().unwrap() = ax;
            let shared = self.ax.clone();
            if let Some(adapter) = self.adapter.as_mut() {
                if let Some(events) =
                    adapter.update_if_active(move || build_tree(&shared.lock().unwrap()))
                {
                    events.raise();
                }
            }
            let line0_phys = c.line_w.first().copied().unwrap_or(0.0);
            let line0_expect = c.m.line_width.first().copied().unwrap_or(0.0) * scale;
            log(format!(
                "COMMIT phase={phase:?} version={} width={width} scale={scale} dpi={:.1} line0_w_phys={line0_phys:.3} expect_phys={line0_expect:.3} lines={} anchor={} focus={} tree=pushed",
                c.version,
                scale * 96.0,
                c.lines(),
                c.anchor,
                c.focus
            ));
            self.committed = Some(c);
            if phase.is_some() {
                self.commit_tick = Some(self.tick);
                self.ready = false;
            }
            window.refresh();
            cx.notify();
        }

        /// Compare paint-time rects, committed rects, AX rects and hit tests for the phase.
        fn self_check(&mut self, phase: usize) {
            let Some(c) = self.committed.clone() else { return };
            let snap = self.paint.lock().unwrap().clone();
            let ax = self.ax.lock().unwrap().clone();
            let version_ok = snap.version == c.version && snap.chars.len() == c.n_chars();
            let mut paint_err = 0f32;
            let mut ax_err = 0f32;
            let mut hit_bad = 0usize;
            let mut gpui_bad = 0usize;

            for (ri, &(label, a, b)) in self.ranges.iter().enumerate() {
                let paint_items: Vec<(usize, [f32; 4])> = (a..b)
                    .map(|i| (c.m.cells[i].line, snap.chars.get(i).copied().unwrap_or([f32::NAN; 4])))
                    .collect();
                let commit_items: Vec<(usize, [f32; 4])> =
                    (a..b).map(|i| (c.cells[i].line, c.cell_rect(i))).collect();
                let ax_items: Vec<(usize, [f32; 4])> = (a..b).map(|i| ax_char_rect(&ax, i)).collect();
                let paint_r = merge_lines(&paint_items);
                let commit_r = merge_lines(&commit_items);
                let ax_r = merge_lines(&ax_items);
                paint_err = paint_err.max(max_err(&paint_r, &commit_r));
                ax_err = ax_err.max(max_err(&ax_r, &commit_r));
                log(format!("PAINT phase={phase} r={ri} label={label} rects={}", fmt_rects(&paint_r)));
                log(format!("AX phase={phase} r={ri} label={label} rects={}", fmt_rects(&ax_r)));
                log(format!("COMMITTED phase={phase} r={ri} label={label} rects={}", fmt_rects(&commit_r)));

                let mut ok = 0usize;
                let mut gok = 0usize;
                for i in a..b {
                    let r = snap.chars.get(i).copied().unwrap_or([f32::NAN; 4]);
                    let cxp = r[0] + r[2] * 0.5;
                    let cyp = r[1] + r[3] * 0.5;
                    if c.index_for_point(cxp, cyp) == i {
                        ok += 1;
                    } else {
                        hit_bad += 1;
                    }
                    // GPUI's own hit test on the same shaped handle, logical text-local coords.
                    let lx = cxp / c.scale - PAD_PX;
                    let ly = cyp / c.scale - PAD_PX;
                    let byte = match c.m.wrapped.index_for_position(point(px(lx), px(ly)), px(LINE_PX)) {
                        Ok(v) | Err(v) => v,
                    };
                    if c.m.char_at_byte.get(byte).copied() == Some(i) {
                        gok += 1;
                    } else {
                        gpui_bad += 1;
                    }
                }
                log(format!(
                    "HIT phase={phase} r={ri} probe_ok={ok}/{} gpui_ok={gok}/{}",
                    b - a,
                    b - a
                ));
            }

            let caret_commit = c.caret_rect(c.focus);
            let (_, caret_ax_char) = ax_char_rect(&ax, c.focus.min(c.n_chars() - 1));
            let caret_ax = [caret_ax_char[0], caret_ax_char[1], 0.0, caret_ax_char[3]];
            log(format!(
                "CARET phase={phase} idx={} commit_rect={} ax_rect={}",
                c.focus,
                fmt_rects(&[caret_commit]),
                fmt_rects(&[caret_ax])
            ));
            let ok = version_ok && paint_err <= 1.0 && ax_err <= 1.0 && hit_bad == 0 && gpui_bad == 0;
            log(format!(
                "SELFCHECK phase={phase} version_ok={version_ok} paint_vs_commit_max={paint_err:.4} ax_vs_commit_max={ax_err:.4} hit_mismatch={hit_bad} gpui_hit_mismatch={gpui_bad} pass={ok}"
            ));
            log(format!("PHASE {phase} ready"));
            self.ready = true;
            self.ready_tick = self.tick;
            self.commit_tick = None;
        }

        /// Called every 100 ms from a GPUI task. Returns false when the probe is done.
        fn tick(&mut self, window: &mut Window, cx: &mut Context<Self>) -> bool {
            if self.done {
                return false;
            }
            self.tick += 1;

            let evs: Vec<AxEvent> = std::mem::take(&mut *self.events.lock().unwrap());
            for ev in evs {
                match ev {
                    AxEvent::Focus => log("APPLY focus"),
                    AxEvent::Select { anchor, focus } => {
                        let ax = self.ax.lock().unwrap().clone();
                        self.anchor = global_char(&ax, anchor.0, anchor.1);
                        self.focus = global_char(&ax, focus.0, focus.1);
                        log(format!("APPLY select anchor={} focus={}", self.anchor, self.focus));
                        if let Some(c) = self.committed.clone() {
                            self.publish(window, cx, c.m.clone(), c.width, c.scale, None);
                        }
                    }
                    AxEvent::SetValue(v) => log(format!(
                        "APPLY setvalue refused text_len={} (text edits are Swift-owned; not exercised here)",
                        v.len()
                    )),
                    AxEvent::Other(s) => log(format!("APPLY ignored {s}")),
                }
            }

            let phase = self.phase;
            if self.commit_tick.is_some_and(|t| self.tick >= t + 5) && !self.ready {
                self.self_check(phase);
            }

            if self.ready {
                let waited = self.tick - self.ready_tick;
                let acked = self.run_dir.join(format!("ack-{phase}.txt")).exists();
                if acked || waited >= 600 {
                    if !acked {
                        log(format!("NOACK phase={phase} waited_ticks={waited}"));
                    }
                    if phase + 1 < PHASE_WIDTH.len() {
                        self.phase += 1;
                        let w = Self::width_for(self.phase);
                        self.commit_width(window, cx, w, Some(self.phase));
                    } else {
                        log(format!(
                            "CACHE hits={} misses={} measure_calls={}",
                            self.hits, self.misses, self.measure_calls
                        ));
                        log("DONE");
                        self.done = true;
                        cx.quit();
                        return false;
                    }
                }
            }
            true
        }
    }

    impl Render for ProbeView {
        fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
            let committed = self.committed.clone();
            let snap = self.paint.clone();
            div().size_full().child(
                canvas(
                    |_bounds, _window, _cx| (),
                    move |bounds, _, window, cx| {
                        if let Some(c) = &committed {
                            paint_committed(c, bounds, window, cx, &snap);
                        }
                    },
                )
                .size_full(),
            )
        }
    }

    pub fn run() {
        let log_path = std::env::var("SR0B_TG_LOG").expect("SR0B_TG_LOG not set");
        let run_dir = PathBuf::from(std::env::var("SR0B_TG_RUN").expect("SR0B_TG_RUN not set"));
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .expect("open log file");
        let _ = LOG.set(Mutex::new(file));

        let chars: Vec<char> = TEXT.chars().collect();
        let ws = word_starts_of(&chars);
        let word_moves = ws.iter().enumerate().filter(|(i, w)| *i > 0 && **w).count();
        let next_word = ws
            .iter()
            .enumerate()
            .skip(1)
            .find(|(_, w)| **w)
            .map(|(i, _)| i)
            .unwrap_or(chars.len());
        let first_word: String = chars[..next_word].iter().collect();
        let ranges = sample_ranges(&chars);
        let (caret_a, _) = find_range(&chars, CARET_START);
        let (sel_a, sel_b) = find_range(&chars, SELECT_LABEL);
        log(format!(
            "START pid={} chars={} bytes={} text={}",
            std::process::id(),
            chars.len(),
            TEXT.len(),
            TEXT
        ));
        log(format!("EXPECT chars={} words={} firstword={}", chars.len(), word_moves, first_word));
        for (i, (label, a, b)) in ranges.iter().enumerate() {
            let text: String = chars[*a..*b].iter().collect();
            log(format!("RANGE {i} a={a} b={b} label={label} text={text}"));
        }
        log(format!("CARET_START idx={caret_a} SELECT a={sel_a} b={sel_b}"));
        log(format!("WIDTHS {:?} PHASE_WIDTH {:?}", WIDTHS, PHASE_WIDTH));

        let ax = Arc::new(Mutex::new(AxData::default()));
        let events: Arc<Mutex<Vec<AxEvent>>> = Arc::new(Mutex::new(Vec::new()));
        let paint = Arc::new(Mutex::new(PaintSnap::default()));

        Application::new().run(move |cx: &mut App| {
            let bounds = Bounds::centered(None, size(px(640.), px(480.)), cx);
            let (ax_v, events_v, paint_v) = (ax.clone(), events.clone(), paint.clone());
            let ranges_v = ranges.clone();
            let run_dir_v = run_dir.clone();
            let handle: WindowHandle<ProbeView> = cx
                .open_window(
                    WindowOptions {
                        window_bounds: Some(WindowBounds::Windowed(bounds)),
                        // The accesskit subclassing adapter must exist before the window is shown.
                        show: false,
                        ..Default::default()
                    },
                    move |_, cx| {
                        cx.new(|_| ProbeView {
                            adapter: None,
                            ax: ax_v,
                            events: events_v,
                            paint: paint_v,
                            cache: HashMap::new(),
                            hits: 0,
                            misses: 0,
                            measure_calls: 0,
                            committed: None,
                            version: 0,
                            anchor: caret_a,
                            focus: caret_a,
                            ranges: ranges_v,
                            phase: 0,
                            commit_tick: None,
                            ready: false,
                            ready_tick: 0,
                            tick: 0,
                            run_dir: run_dir_v,
                            done: false,
                        })
                    },
                )
                .expect("open_window failed");

            handle
                .update(cx, |view, window, cx| {
                    let w = ProbeView::width_for(0);
                    view.commit_width(window, cx, w, Some(0));
                    let hwnd = hwnd_of(window);
                    view.adapter = Some(SubclassingAdapter::new(
                        hwnd,
                        Activation { ax: view.ax.clone() },
                        Actions { events: view.events.clone() },
                    ));
                    log(format!("ADAPTER attached hwnd={:?}", hwnd.0));
                    window.activate_window();
                    cx.spawn(async move |_this, cx| loop {
                        cx.background_executor()
                            .timer(Duration::from_millis(100))
                            .await;
                        match handle.update(cx, |view, window, cx| view.tick(window, cx)) {
                            Ok(true) => {}
                            _ => break,
                        }
                    })
                    .detach();
                })
                .expect("attaching accesskit adapter failed");

            cx.activate(true);
        });
    }
}

#[cfg(windows)]
fn main() {
    probe::run();
}

#[cfg(not(windows))]
fn main() {
    eprintln!("sr0b-text-geometry is a Windows-only probe");
    std::process::exit(2);
}
