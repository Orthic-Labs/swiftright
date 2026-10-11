use std::path::PathBuf;

use tauri::AppHandle;
#[cfg(not(any(
    feature = "qa-native",
    feature = "bench-native",
    feature = "dev-native"
)))]
use tauri::Emitter;
#[cfg(any(
    target_os = "macos",
    not(any(
        feature = "qa-native",
        feature = "bench-native",
        feature = "dev-native"
    ))
))]
use tauri::Manager;

use crate::commands;

#[cfg(not(any(
    feature = "qa-native",
    feature = "bench-native",
    feature = "dev-native"
)))]
fn requested_file_paths(argv: &[String]) -> Vec<&str> {
    argv.iter()
        .skip(1)
        .filter(|arg| !arg.starts_with('-'))
        .map(String::as_str)
        .collect()
}
/// Single-instance handler: a second launch focuses the existing window and, if a file path
/// was passed on the command line, asks the webview to open it.
#[cfg(not(any(
    feature = "qa-native",
    feature = "bench-native",
    feature = "dev-native"
)))]
pub fn on_second_instance(app: &AppHandle, argv: Vec<String>, _cwd: String) {
    let prepare_setup = argv.iter().skip(1).any(|arg| arg == "--prepare-setup");
    if prepare_setup {
        let _ = app.emit("prepare-setup", ());
        return;
    }
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.show();
        let _ = win.unminimize();
        let _ = win.set_focus();
    }
    let paths = requested_file_paths(&argv);
    if paths.is_empty() {
        return;
    }
    commands::route_open_paths(app, paths.into_iter().map(PathBuf::from).collect());
}

#[cfg(target_os = "macos")]
fn requested_file_paths_from_urls(urls: Vec<tauri::Url>) -> Vec<PathBuf> {
    urls.into_iter()
        .filter_map(|url| url.to_file_path().ok())
        .collect()
}

#[cfg(target_os = "macos")]
fn restore_main_window(app: &AppHandle) {
    // Open-document events arrive through AppKit while ViewRight may be hidden or minimized.
    // Activate the process before focusing its window; set_focus alone does not reliably make a
    // background macOS application frontmost.
    crate::pdf_bench::activate_macos_foreground();
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.show();
        let _ = win.unminimize();
        let _ = win.set_focus();
    }
}

/// Finder, `open -a`, and macOS document handoff use an Apple open-document event, not argv.
#[cfg(target_os = "macos")]
pub fn on_opened_urls(app: &AppHandle, urls: Vec<tauri::Url>) {
    restore_main_window(app);
    commands::route_open_paths(app, requested_file_paths_from_urls(urls));
}
