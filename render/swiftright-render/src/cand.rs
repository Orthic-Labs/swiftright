//! #45 step 1: our own IME candidate list (UI-less TSF mode). This file holds the pure parts: the candidate list state read
//! from `ITfCandidateListUIElement` (filled by tsf.rs) and the placement / hit-test / sizing geometry of the popup. No Windows
//! API is used here, so the unit tests run on any host.
#![allow(dead_code)]

/// A screen rectangle in physical pixels (same convention as Win32 `RECT`: right/bottom exclusive).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

/// What the IME last reported about its candidate list.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct CandState {
    /// Strings of the current page (at most 9).
    pub strings: Vec<String>,
    /// Selected candidate, absolute index as `ITfCandidateListUIElement::GetSelection` returns it.
    pub selection: usize,
    /// Current page number.
    pub page: u32,
    /// First candidate index of every page (`GetPageIndex`); empty when the IME gave no page table.
    pub page_starts: Vec<u32>,
    /// Total number of candidates.
    pub count: u32,
    /// `ITfIntegratableCandidateListUIElement::ShowCandidateNumbers` (true when unknown).
    pub show_numbers: bool,
}

impl CandState {
    /// Absolute index of the first candidate on the current page (0 without a page table).
    pub fn first_on_page(&self) -> usize {
        self.page_starts.get(self.page as usize).map_or(0, |&s| s as usize)
    }

    /// Number of rows on the current page.
    pub fn rows(&self) -> usize {
        self.strings.len()
    }

    /// The selected row relative to the page start, or None when the selection is not on this page.
    pub fn selected_row(&self) -> Option<usize> {
        let first = self.first_on_page();
        let rel = self.selection.checked_sub(first)?;
        (rel < self.rows()).then_some(rel)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    Above,
    Below,
}

/// Places a popup of `size` (w, h) next to `anchor` (the composition / caret rect) inside `work` (monitor work area), all in
/// screen pixels. Prefers below the anchor; flips above when there is no room below; `prev == Some(Above)` keeps it above while
/// that still fits (hysteresis, so the list does not jump between sides while it changes height). When neither side fits it
/// uses the bigger side and clamps to the work area edge.
pub fn place(anchor: Rect, work: Rect, size: (i32, i32), scale: f32, prev: Option<Side>) -> (Rect, Side) {
    let (w, h) = size;
    let g = (2.0 * scale).round() as i32;
    let below_top = anchor.bottom + g;
    let above_top = anchor.top - g - h;
    let (top, side) = if prev == Some(Side::Above) && above_top >= work.top {
        (above_top, Side::Above)
    } else if below_top + h <= work.bottom {
        (below_top, Side::Below)
    } else if above_top >= work.top {
        (above_top, Side::Above)
    } else if (anchor.top - work.top) > (work.bottom - anchor.bottom) {
        (work.top, Side::Above)
    } else {
        (work.bottom - h, Side::Below)
    };
    let mut left = anchor.left - (8.0 * scale).round() as i32;
    left = left.min(work.right - w).max(work.left);
    (Rect { left, top, right: left + w, bottom: top + h }, side)
}

/// The row under (x, y) when rows of height `row_h` stack from `rect.top` across `rect`'s width; None outside.
pub fn hit_row(rect: Rect, row_h: i32, rows: usize, x: i32, y: i32) -> Option<usize> {
    if row_h <= 0 || x < rect.left || x >= rect.right || y < rect.top {
        return None;
    }
    let row = ((y - rect.top) / row_h) as usize;
    (row < rows).then_some(row)
}

/// Popup width: text + number column + padding, clamped to [120, 600] logical px and to the work area width.
pub fn popup_width(max_text_w: i32, number_col_w: i32, pad: i32, scale: f32, work_w: i32) -> i32 {
    let lo = (120.0 * scale).round() as i32;
    let hi = ((600.0 * scale).round() as i32).min(work_w);
    (max_text_w + number_col_w + pad).max(lo).min(hi)
}

#[cfg(test)]
mod tests {
    use super::*;

    const WORK: Rect = Rect { left: 0, top: 0, right: 1920, bottom: 1080 };

    fn r(left: i32, top: i32, right: i32, bottom: i32) -> Rect {
        Rect { left, top, right, bottom }
    }

    #[test]
    fn place_below_when_it_fits() {
        let (rc, side) = place(r(100, 100, 110, 120), WORK, (200, 150), 1.0, None);
        assert_eq!(side, Side::Below);
        assert_eq!(rc, r(92, 122, 292, 272));
    }

    #[test]
    fn place_flips_above_without_room_below() {
        let (rc, side) = place(r(100, 1000, 110, 1020), WORK, (200, 150), 1.0, None);
        assert_eq!(side, Side::Above);
        assert_eq!(rc, r(92, 848, 292, 998));
    }

    #[test]
    fn place_exact_fit_below_and_above() {
        // below_top + h == work.bottom still fits below.
        let (rc, side) = place(r(100, 100, 110, 928), WORK, (200, 150), 1.0, None);
        assert_eq!((side, rc.bottom), (Side::Below, 1080));
        // above_top == work.top still fits above.
        let (rc, side) = place(r(100, 152, 110, 1070), WORK, (200, 150), 1.0, None);
        assert_eq!((side, rc.top), (Side::Above, 0));
    }

    #[test]
    fn place_hysteresis_keeps_above() {
        let a = r(100, 500, 110, 520);
        assert_eq!(place(a, WORK, (200, 150), 1.0, None).1, Side::Below);
        assert_eq!(place(a, WORK, (200, 150), 1.0, Some(Side::Below)).1, Side::Below);
        let (rc, side) = place(a, WORK, (200, 150), 1.0, Some(Side::Above));
        assert_eq!((side, rc.top, rc.bottom), (Side::Above, 348, 498));
    }

    #[test]
    fn place_hysteresis_gives_up_when_above_no_longer_fits() {
        let (rc, side) = place(r(100, 100, 110, 120), WORK, (200, 150), 1.0, Some(Side::Above));
        assert_eq!((side, rc.top), (Side::Below, 122));
    }

    #[test]
    fn place_neither_fits_uses_bigger_side_with_clamp() {
        let work = r(0, 0, 1000, 300);
        // More room below (180) than above (100): below, bottom clamped to the work area.
        let (rc, side) = place(r(50, 100, 60, 120), work, (200, 250), 1.0, None);
        assert_eq!((side, rc.top, rc.bottom), (Side::Below, 50, 300));
        // More room above (180) than below (100): above, top clamped to the work area.
        let (rc, side) = place(r(50, 180, 60, 200), work, (200, 250), 1.0, None);
        assert_eq!((side, rc.top, rc.bottom), (Side::Above, 0, 250));
        // Equal room: below.
        let (_, side) = place(r(50, 140, 60, 160), work, (200, 250), 1.0, None);
        assert_eq!(side, Side::Below);
    }

    #[test]
    fn place_horizontal_clamp_left_and_right() {
        let (rc, _) = place(r(3, 100, 13, 120), WORK, (200, 150), 1.0, None);
        assert_eq!((rc.left, rc.right), (0, 200));
        let (rc, _) = place(r(1900, 100, 1910, 120), WORK, (200, 150), 1.0, None);
        assert_eq!((rc.left, rc.right), (1720, 1920));
        // A work area that does not start at 0 (second monitor).
        let work = r(-1920, 0, 0, 1080);
        let (rc, _) = place(r(-5, 100, 5, 120), work, (200, 150), 1.0, None);
        assert_eq!((rc.left, rc.right), (-200, 0));
    }

    #[test]
    fn place_scale_1_25() {
        // g = round(2.5) = 3, left offset = 10.
        let (rc, side) = place(r(100, 100, 110, 120), WORK, (250, 180), 1.25, None);
        assert_eq!(side, Side::Below);
        assert_eq!(rc, r(90, 123, 340, 303));
        let (rc, side) = place(r(100, 1000, 110, 1020), WORK, (250, 180), 1.25, None);
        assert_eq!((side, rc.top, rc.bottom), (Side::Above, 817, 997));
    }

    #[test]
    fn place_scale_2_5() {
        // g = 5, left offset = 20.
        let (rc, side) = place(r(200, 100, 210, 140), WORK, (500, 300), 2.5, None);
        assert_eq!(side, Side::Below);
        assert_eq!(rc, r(180, 145, 680, 445));
        let (rc, side) = place(r(200, 900, 210, 940), WORK, (500, 300), 2.5, None);
        assert_eq!((side, rc.top, rc.bottom), (Side::Above, 595, 895));
    }

    #[test]
    fn hit_row_inside_and_outside() {
        let rc = r(10, 20, 110, 50);
        assert_eq!(hit_row(rc, 10, 3, 50, 20), Some(0));
        assert_eq!(hit_row(rc, 10, 3, 50, 29), Some(0));
        assert_eq!(hit_row(rc, 10, 3, 50, 30), Some(1));
        assert_eq!(hit_row(rc, 10, 3, 10, 49), Some(2));
        assert_eq!(hit_row(rc, 10, 3, 50, 50), None);
        assert_eq!(hit_row(rc, 10, 3, 50, 19), None);
        assert_eq!(hit_row(rc, 10, 3, 9, 25), None);
        assert_eq!(hit_row(rc, 10, 3, 110, 25), None);
        // Fewer rows than the rect height covers: below the last row is outside.
        assert_eq!(hit_row(rc, 10, 2, 50, 45), None);
        assert_eq!(hit_row(rc, 0, 3, 50, 25), None);
    }

    #[test]
    fn popup_width_clamps() {
        assert_eq!(popup_width(300, 20, 16, 1.0, 1920), 336);
        assert_eq!(popup_width(10, 20, 16, 1.0, 1920), 120);
        assert_eq!(popup_width(2000, 20, 16, 1.0, 1920), 600);
        assert_eq!(popup_width(2000, 20, 16, 1.0, 400), 400);
        assert_eq!(popup_width(10, 20, 16, 2.0, 1920), 240);
        assert_eq!(popup_width(2000, 20, 16, 2.0, 1920), 1200);
        assert_eq!(popup_width(2000, 20, 16, 2.5, 1000), 1000);
    }

    fn state(strings: &[&str], selection: usize, page: u32, starts: &[u32], count: u32) -> CandState {
        CandState {
            strings: strings.iter().map(|s| s.to_string()).collect(),
            selection,
            page,
            page_starts: starts.to_vec(),
            count,
            show_numbers: true,
        }
    }

    #[test]
    fn cand_state_first_page() {
        let s = state(&["a", "b", "c"], 1, 0, &[0, 9], 12);
        assert_eq!(s.first_on_page(), 0);
        assert_eq!(s.rows(), 3);
        assert_eq!(s.selected_row(), Some(1));
    }

    #[test]
    fn cand_state_second_page() {
        let s = state(&["x", "y", "z"], 10, 1, &[0, 9], 12);
        assert_eq!(s.first_on_page(), 9);
        assert_eq!(s.selected_row(), Some(1));
    }

    #[test]
    fn cand_state_selection_off_page_or_no_table() {
        let off = state(&["x", "y", "z"], 3, 1, &[0, 9], 12);
        assert_eq!(off.selected_row(), None);
        let past = state(&["x", "y", "z"], 12, 1, &[0, 9], 12);
        assert_eq!(past.selected_row(), None);
        let no_table = state(&["a", "b"], 1, 0, &[], 2);
        assert_eq!(no_table.first_on_page(), 0);
        assert_eq!(no_table.selected_row(), Some(1));
        let bad_page = state(&["a"], 0, 5, &[0], 1);
        assert_eq!(bad_page.first_on_page(), 0);
        assert_eq!(CandState::default().selected_row(), None);
    }
}
