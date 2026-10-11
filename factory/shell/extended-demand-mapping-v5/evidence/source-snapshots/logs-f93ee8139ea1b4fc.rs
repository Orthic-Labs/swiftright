use rightkit_db::rusqlite::{Connection, OpenFlags, OptionalExtension};
use rightkit_logs::{
    collect_diagnostics as collect_shared, BundleMetadata, CollectionPolicy, DiagnosticsBundle,
    EventRecord, JsonlStore, Level, LogSource, RedactionPolicy,
};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicI8, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::app_paths::app_data_namespace;

const MAX_LOG_BYTES: u64 = 4 * 1024 * 1024;
const SETTINGS_KEY: &str = "vr.settings.v1";
static DIAGNOSTICS_ENABLED: AtomicI8 = AtomicI8::new(-1);
static LOG_WRITE_LOCK: Mutex<()> = Mutex::new(());

pub fn log_path() -> PathBuf {
    dirs::data_local_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(app_data_namespace())
        .join("logs")
        .join("events.jsonl")
}
fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

fn enabled_from_settings(raw: Option<&str>) -> bool {
    raw.and_then(|value| serde_json::from_str::<Value>(value).ok())
        .and_then(|value| value.get("diagnostics").and_then(Value::as_bool))
        .unwrap_or(true)
}

fn load_persisted_enabled() -> bool {
    let Ok(connection) = Connection::open_with_flags(
        crate::persistence::db_path(),
        OpenFlags::SQLITE_OPEN_READ_ONLY,
    ) else {
        return true;
    };
    let raw = connection
        .query_row(
            "SELECT value FROM settings_kv WHERE key = ?1",
            [SETTINGS_KEY],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .ok()
        .flatten();
    enabled_from_settings(raw.as_deref())
}

fn diagnostics_enabled() -> bool {
    match DIAGNOSTICS_ENABLED.load(Ordering::Acquire) {
        0 => false,
        1 => true,
        _ => {
            let enabled = load_persisted_enabled();
            match DIAGNOSTICS_ENABLED.compare_exchange(
                -1,
                if enabled { 1 } else { 0 },
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => enabled,
                Err(current) => current == 1,
            }
        }
    }
}

/// Update native logging gate after renderer settings mirror writes. Startup reads the same
/// persisted mirror before first native event, so off survives relaunch.
pub fn set_enabled(enabled: bool) {
    let _guard = LOG_WRITE_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    DIAGNOSTICS_ENABLED.store(if enabled { 1 } else { 0 }, Ordering::Release);
}

pub fn record(event: impl Into<String>, level: Level) {
    let _guard = LOG_WRITE_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if !diagnostics_enabled() {
        return;
    }
    JsonlStore::new(log_path(), MAX_LOG_BYTES).append_best_effort(&EventRecord::new(
        now_ms(),
        level,
        event,
    ));
}

/// Record an event with a free-form detail field. Used for startup errors and
/// panic hooks where the message carries diagnostic context (error text, panic
/// location) that a bare event name can't convey.
pub fn record_detail(event: impl Into<String>, level: Level, detail: impl Into<String>) {
    let _guard = LOG_WRITE_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if !diagnostics_enabled() {
        return;
    }
    JsonlStore::new(log_path(), MAX_LOG_BYTES).append_best_effort(
        &EventRecord::new(now_ms(), level, event).with_field("detail", json!(detail.into())),
    );
}

pub fn collect_for_path(path: &Path) -> DiagnosticsBundle {
    let _guard = LOG_WRITE_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let mut policy = CollectionPolicy::default();
    for fragment in ["path", "url", "html", "query", "text"] {
        policy
            .redaction
            .additional_key_fragments
            .insert(fragment.to_string());
    }
    collect_shared(
        &[LogSource::new("app", path)],
        BundleMetadata {
            app_name: "ViewRight".to_string(),
            app_version: env!("CARGO_PKG_VERSION").to_string(),
            build: if cfg!(debug_assertions) {
                "debug"
            } else {
                "release"
            }
            .to_string(),
            os: std::env::consts::OS.to_string(),
            settings: json!({}),
        },
        &policy,
    )
}

pub fn clear_path(path: &Path) -> std::io::Result<()> {
    let _guard = LOG_WRITE_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    JsonlStore::new(path, MAX_LOG_BYTES).clear()
}

pub fn write_for_path(path: &Path, events: Vec<Value>) -> Result<(), String> {
    let _guard = LOG_WRITE_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if !diagnostics_enabled() {
        return Ok(());
    }
    const MAX_BATCH_EVENTS: usize = 500;
    let store = JsonlStore::new(path, MAX_LOG_BYTES);
    let dropped = events.len().saturating_sub(MAX_BATCH_EVENTS);

    if dropped > 0 {
        store
            .append(
                &EventRecord::new(now_ms(), Level::Warn, "logs_dropped")
                    .with_field("dropped_count", json!(dropped)),
            )
            .map_err(|error| format!("write diagnostic log: {error}"))?;
    }

    for mut value in events.into_iter().skip(dropped) {
        RedactionPolicy::default().redact_value(&mut value);
        let event: EventRecord = serde_json::from_value(value)
            .map_err(|error| format!("invalid diagnostic event: {error}"))?;
        store
            .append(&event)
            .map_err(|error| format!("write diagnostic log: {error}"))?;
    }
    Ok(())
}

#[tauri::command]
pub fn rightkit_logs_write(events: Vec<Value>) -> Result<(), String> {
    write_for_path(&log_path(), events)
}

#[tauri::command]
pub fn rightkit_logs_collect() -> DiagnosticsBundle {
    collect_for_path(&log_path())
}

#[tauri::command]
pub fn rightkit_logs_clear() -> Result<(), String> {
    clear_path(&log_path()).map_err(|error| format!("clear diagnostic logs: {error}"))
}
