//! F0 renderer text facts probe (Windows x64). Standalone exe, not the renderer.
//!
//! Default mode (what the renderer does): open a GPUI 0.2.2 window, paint ONE page of text tests chosen by `F0_PAGE`
//! and write an API trace (shaped glyph ids, positions, advances, resolved fonts, gpui's own log lines) to stderr.
//! The Sandbox capture script (factory/tools/pair/capture.ps1) PrintWindows the page.
//! `--dw` mode (what an own DirectWrite path could do): talk to DirectWrite directly, no gpui window: face matching and
//! simulations the way gpui does it, variable-font axes, glyph rasters to BMP, rendering mode and grid-fit tables.
//! Pages and the questions they answer: docs/probes/f0-renderer-text-facts.md.

#[cfg(windows)]
mod dw;
#[cfg(windows)]
mod gp;

#[cfg(windows)]
fn main() {
    let dw_mode = std::env::args().any(|a| a == "--dw")
        || std::env::var("F0_MODE").map_or(false, |m| m == "dw");
    if dw_mode {
        let out = std::env::var("F0_OUT").unwrap_or_else(|_| ".".to_string());
        dw::run(&out);
        return;
    }
    gp::run();
}

#[cfg(not(windows))]
fn main() {
    eprintln!("f0-text-facts is a Windows-only probe");
    std::process::exit(2);
}
