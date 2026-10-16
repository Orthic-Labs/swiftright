//! Rev 0.10 explicit render scale (decision H17): one scale source for the window's physical size, text metrics, the metrics the
//! host reads and the events it receives. A host passes `render_scale` in `swr_run_options_v10`; 0 (or a pre-0.10 options struct)
//! means "none" and every value then comes from the window's DPI exactly as before.
//!
//! Terms: S is the scale the host sees (`swr_window_metrics.scale`, `MeasureRequest.scale`). G is the scale GPUI itself uses
//! (the window's DPI / 96), which decides how GPUI turns its logical pixels into device pixels. Without an override S == G.
//! With an override S is fixed and G is whatever the display says, so everything GPUI-facing is converted with `k = S / G`.
//! Physical (device) pixels are the common currency: the window's client area, pointer positions, hit rectangles and UIA bounds
//! are all physical pixels and never need `k`.

use std::sync::atomic::{AtomicU32, Ordering::SeqCst};

/// Smallest and largest accepted explicit scale (a factor of 96 dpi: 0.25 is 24 dpi, 16 is 1536 dpi).
pub const MIN_RENDER_SCALE: f32 = 0.25;
pub const MAX_RENDER_SCALE: f32 = 16.0;

/// The process-wide override, as f32 bits; 0 bits = none. Set once by `swr_run` before the window exists.
static OVERRIDE_BITS: AtomicU32 = AtomicU32::new(0);
/// The scale GPUI uses for the live window (G), as f32 bits; 0 until the window exists.
static GPUI_BITS: AtomicU32 = AtomicU32::new(0);

/// Validates the `render_scale` word of `swr_run_options_v10`: 0 is "no override"; a finite value inside
/// [MIN_RENDER_SCALE, MAX_RENDER_SCALE] is the override; anything else (NaN, infinite, negative, out of range) is refused.
pub fn parse_render_scale(v: f32) -> Result<Option<f32>, ()> {
    if v == 0.0 {
        return Ok(None);
    }
    if v.is_finite() && (MIN_RENDER_SCALE..=MAX_RENDER_SCALE).contains(&v) {
        Ok(Some(v))
    } else {
        Err(())
    }
}

pub fn set_override(v: Option<f32>) {
    OVERRIDE_BITS.store(v.map_or(0, f32::to_bits), SeqCst);
}

pub fn override_scale() -> Option<f32> {
    match OVERRIDE_BITS.load(SeqCst) {
        0 => None,
        b => Some(f32::from_bits(b)),
    }
}

/// The scale the host sees: the override when set, else the DPI-derived value (`dpi / 96`), else `fallback` when the DPI is
/// unknown (0). With no override this is the exact expression the renderer used before 0.10.
pub fn effective_scale(ovr: Option<f32>, dpi: u32, fallback: f32) -> f32 {
    match ovr {
        Some(s) => s,
        None if dpi == 0 => fallback,
        None => dpi as f32 / 96.0,
    }
}

/// Records GPUI's own scale for the live window. Returns true when it changed (a DPI change while the window lives).
pub fn note_gpui_scale(g: f32) -> bool {
    GPUI_BITS.swap(g.to_bits(), SeqCst) != g.to_bits()
}

pub fn gpui_scale() -> f32 {
    f32::from_bits(GPUI_BITS.load(SeqCst))
}

/// `k = S / G`: how many GPUI logical px one host DIP-at-S spans relative to GPUI's own DIP. 1.0 without an override, so an
/// unmodified run multiplies and divides by exactly 1.0.
pub fn gpui_ratio(ovr: Option<f32>, host_scale: f32, gpui: f32) -> f32 {
    match ovr {
        Some(_) if gpui > 0.0 && host_scale > 0.0 => host_scale / gpui,
        _ => 1.0,
    }
}

/// The logical size to ask GPUI for so the client area is `dip * S` physical px. GPUI turns logical px into physical with G, so
/// the request is `dip * S / G`. Without an override the request is exactly `dip`.
pub fn requested_logical_size(dip: u32, ovr: Option<f32>, gpui: f32) -> f32 {
    match ovr {
        Some(s) if gpui > 0.0 => dip as f32 * s / gpui,
        _ => dip as f32,
    }
}

/// The client size in physical px a window opened at `dip` DIPs has at scale `scale`.
pub fn physical_px(dip: u32, scale: f32) -> u32 {
    (dip as f32 * scale).round() as u32
}

/// Physical -> GPUI logical (what the painter does with every host rectangle).
#[allow(dead_code)]
pub fn to_logical(physical: f32, gpui: f32) -> f32 {
    physical / gpui
}

/// GPUI logical -> physical (what the pointer handler does with every GPUI position).
#[allow(dead_code)]
pub fn to_physical(logical: f32, gpui: f32) -> f32 {
    logical * gpui
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_zero_is_none_and_garbage_is_refused() {
        assert_eq!(parse_render_scale(0.0), Ok(None));
        assert_eq!(parse_render_scale(2.5), Ok(Some(2.5)));
        assert_eq!(parse_render_scale(MIN_RENDER_SCALE), Ok(Some(MIN_RENDER_SCALE)));
        assert_eq!(parse_render_scale(MAX_RENDER_SCALE), Ok(Some(MAX_RENDER_SCALE)));
        for bad in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY, -1.0, 0.1, 16.5] {
            assert_eq!(parse_render_scale(bad), Err(()), "{bad} must be refused");
        }
    }

    #[test]
    fn no_override_keeps_the_dpi_derived_scale_exactly() {
        assert_eq!(effective_scale(None, 240, 1.0), 240.0f32 / 96.0);
        assert_eq!(effective_scale(None, 96, 2.5), 1.0);
        assert_eq!(effective_scale(None, 120, 9.0), 1.25);
        assert_eq!(effective_scale(None, 0, 1.75), 1.75, "an unknown dpi keeps the previous value");
        assert_eq!(gpui_ratio(None, 2.5, 1.25), 1.0);
        assert_eq!(requested_logical_size(320, None, 1.25), 320.0);
    }

    #[test]
    fn an_override_replaces_the_dpi_scale_everywhere() {
        // A 125 percent display (G = 1.25) asked for 2.5.
        assert_eq!(effective_scale(Some(2.5), 120, 1.0), 2.5);
        assert_eq!(effective_scale(Some(2.5), 0, 1.0), 2.5);
        assert_eq!(effective_scale(Some(2.5), 240, 1.0), 2.5);
        assert_eq!(gpui_ratio(Some(2.5), 2.5, 1.25), 2.0);
        assert_eq!(requested_logical_size(320, Some(2.5), 1.25), 640.0);
        assert_eq!(physical_px(320, 2.5), 800);
        assert_eq!(physical_px(240, 2.5), 600);
    }

    #[test]
    fn window_size_follows_the_override_on_any_display() {
        for g in [1.0f32, 1.25, 1.5, 2.0, 2.5, 3.0] {
            let logical = requested_logical_size(320, Some(2.5), g);
            let physical = to_physical(logical, g).round() as u32;
            assert_eq!(physical, physical_px(320, 2.5), "G = {g}");
        }
    }

    #[test]
    fn override_equal_to_the_display_scale_is_the_old_path() {
        // On the 240 dpi sandbox an explicit 2.5 changes nothing: k is exactly 1 and the size request is exactly the DIPs.
        assert_eq!(gpui_ratio(Some(2.5), 2.5, 2.5), 1.0);
        assert_eq!(requested_logical_size(320, Some(2.5), 2.5), 320.0);
    }

    #[test]
    fn pointer_mapping_round_trips() {
        for g in [1.0f32, 1.25, 2.0, 2.5] {
            for phys in [0.0f32, 1.0, 17.0, 400.0, 799.0] {
                let back = to_physical(to_logical(phys, g), g);
                assert!((back - phys).abs() < 1e-3, "G = {g} phys = {phys} back = {back}");
            }
        }
        // A pointer at GPUI logical (160, 120) on a 1.25 display is physical (200, 150), the same physical pixel the host's
        // 2.5 layout uses: hit-testing needs no k.
        assert_eq!(to_physical(160.0, 1.25), 200.0);
    }

    #[test]
    fn override_state_is_set_and_cleared() {
        set_override(Some(2.5));
        assert_eq!(override_scale(), Some(2.5));
        set_override(None);
        assert_eq!(override_scale(), None);
        assert!(note_gpui_scale(1.25));
        assert!(!note_gpui_scale(1.25));
        assert!(note_gpui_scale(2.0));
        assert_eq!(gpui_scale(), 2.0);
    }
}
