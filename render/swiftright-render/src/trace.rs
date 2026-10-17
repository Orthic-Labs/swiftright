//! Performance traces for the R10 work: where the UI thread's time and the process's memory go, per frame.
//!
//! * Allocation counters (`CountingAlloc`, the crate's global allocator): live bytes and allocation counts of everything the
//!   renderer, GPUI and the Rust dependencies hold. Two relaxed atomics per allocation. The host's own heap (Swift) and the
//!   GPU driver's are not in it, so `private bytes - rust live bytes` is "everything else".
//! * An optional trace (environment `SWR_FRAME_LOG=<file>`, read once): spans of the UI thread's phases (WM_PAINT arrival,
//!   the whole frame, `paint_root`, a commit, a host tick, a host drain, the paced paint handler), the DWM composition edges
//!   the pacing thread observed (with the time the paint message was posted), and once-a-second memory samples. Everything is
//!   QPC ticks (the harness clock) so it joins PresentMon rows and the host's own CSVs by time. The buffers are preallocated
//!   and bounded (they stop taking records when full), so they are not a growth source; they are written once, at shutdown.
//!   Without the variable nothing is recorded and every call is one relaxed load.
//!
//! File format (one record per line, comma separated; `#` lines are headers):
//!   `E,edge_qpc,post_qpc`       a DWM composition edge (DwmFlush return) and when the paced paint was posted (0 = none)
//!   `S,kind,t0,t1`              a UI-thread span; kind is one of the K_* names below
//!   `M,qpc,rust_live,rust_allocs,private,working_set`  a memory sample
//!   with SWR_MEM_DEEP=1 (slow: walks the heaps and the address space every 5th sample): `H,qpc,heap,committed,allocated`,
//!   `V,qpc,private,image,mapped,regions` and `R,first|last,base,size,protect` (private committed regions of the first / last deep sample)

use std::alloc::{GlobalAlloc, Layout, System};
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering::Relaxed};
use std::sync::Mutex;

use crate::rt::{qpc_freq, qpc_now};

// ---------------------------------------------------------------- allocator

pub struct CountingAlloc;

static LIVE_BYTES: AtomicI64 = AtomicI64::new(0);
static ALLOCS: AtomicU64 = AtomicU64::new(0);

unsafe impl GlobalAlloc for CountingAlloc {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        let p = System.alloc(l);
        if !p.is_null() {
            LIVE_BYTES.fetch_add(l.size() as i64, Relaxed);
            ALLOCS.fetch_add(1, Relaxed);
        }
        p
    }
    unsafe fn alloc_zeroed(&self, l: Layout) -> *mut u8 {
        let p = System.alloc_zeroed(l);
        if !p.is_null() {
            LIVE_BYTES.fetch_add(l.size() as i64, Relaxed);
            ALLOCS.fetch_add(1, Relaxed);
        }
        p
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        System.dealloc(p, l);
        LIVE_BYTES.fetch_sub(l.size() as i64, Relaxed);
    }
    unsafe fn realloc(&self, p: *mut u8, l: Layout, new_size: usize) -> *mut u8 {
        let q = System.realloc(p, l, new_size);
        if !q.is_null() {
            LIVE_BYTES.fetch_add(new_size as i64 - l.size() as i64, Relaxed);
            ALLOCS.fetch_add(1, Relaxed);
        }
        q
    }
}

pub fn rust_live_bytes() -> i64 {
    LIVE_BYTES.load(Relaxed)
}

pub fn rust_allocs() -> u64 {
    ALLOCS.load(Relaxed)
}

/// PROCESS_MEMORY_COUNTERS_EX (psapi.h), x64.
#[repr(C)]
struct ProcessMemoryCounters {
    cb: u32,
    page_fault_count: u32,
    peak_working_set: usize,
    working_set: usize,
    quota_peak_paged_pool: usize,
    quota_paged_pool: usize,
    quota_peak_non_paged_pool: usize,
    quota_non_paged_pool: usize,
    pagefile_usage: usize,
    peak_pagefile_usage: usize,
    private_usage: usize,
}

#[repr(C)]
struct HeapSummary {
    cb: u32,
    allocated: usize,
    committed: usize,
    reserved: usize,
    max_reserve: usize,
}

#[repr(C)]
struct MemInfo {
    base: usize,
    alloc_base: usize,
    alloc_protect: u32,
    _pad1: u32,
    size: usize,
    state: u32,
    protect: u32,
    kind: u32,
    _pad2: u32,
}

#[link(name = "kernel32")]
extern "system" {
    fn K32GetProcessMemoryInfo(process: *mut c_void, counters: *mut ProcessMemoryCounters, cb: u32) -> i32;
    fn GetProcessHeaps(n: u32, out: *mut *mut c_void) -> u32;
    fn HeapSummary(heap: *mut c_void, flags: u32, out: *mut HeapSummary) -> i32;
    fn VirtualQuery(addr: *const c_void, out: *mut MemInfo, len: usize) -> usize;
}

/// (private bytes, working set) of this process.
pub fn process_memory() -> (u64, u64) {
    let mut c = ProcessMemoryCounters {
        cb: std::mem::size_of::<ProcessMemoryCounters>() as u32,
        page_fault_count: 0,
        peak_working_set: 0,
        working_set: 0,
        quota_peak_paged_pool: 0,
        quota_paged_pool: 0,
        quota_peak_non_paged_pool: 0,
        quota_non_paged_pool: 0,
        pagefile_usage: 0,
        peak_pagefile_usage: 0,
        private_usage: 0,
    };
    // -1 is the pseudo handle of the current process.
    let ok = unsafe { K32GetProcessMemoryInfo(usize::MAX as *mut c_void, &mut c, c.cb) };
    if ok == 0 {
        return (0, 0);
    }
    (c.private_usage as u64, c.working_set as u64)
}

// -------------------------------------------------------------------- trace

pub const K_WM_PAINT: u8 = 1; // a WM_PAINT reached the subclass (t0 == t1)
pub const K_FRAME: u8 = 2; // GPUI's whole frame: WM_PAINT dispatch -> Present returned
pub const K_PAINT: u8 = 3; // paint_root (our paint callback inside the frame)
pub const K_HANDLER: u8 = 4; // the paced-paint message handler (includes the frame)
pub const K_COMMIT: u8 = 5; // swr_commit
pub const K_TICK: u8 = 6; // host tick callback
pub const K_DRAIN: u8 = 7; // host drain callback
pub const K_PRESENT: u8 = 8; // present(): AX publish + dirty marking
pub const K_IME: u8 = 9; // an ime_* host callback (a key's text-store replace)

const MAX_SPANS: usize = 150_000;
const MAX_EDGES: usize = 20_000;
const MAX_MEM: usize = 4_096;

static ENABLED: AtomicBool = AtomicBool::new(false);
static PATH: Mutex<Option<String>> = Mutex::new(None);
static SPANS: Mutex<Vec<(u8, i64, i64)>> = Mutex::new(Vec::new());
static EDGES: Mutex<Vec<(i64, i64)>> = Mutex::new(Vec::new());
static MEM: Mutex<Vec<(i64, i64, u64, u64, u64)>> = Mutex::new(Vec::new());
/// Deep memory lines (SWR_MEM_DEEP=1): `H,qpc,heap_index,committed,allocated` per process heap and `V,qpc,private,image,mapped,regions` per sample,
/// and the private regions of the first and the last deep sample (`R,tag,base,size,protect`).
static DEEP: AtomicBool = AtomicBool::new(false);
static DEEP_LINES: Mutex<Vec<String>> = Mutex::new(Vec::new());
static DEEP_FIRST: Mutex<Vec<(usize, usize, u32)>> = Mutex::new(Vec::new());
static DEEP_COUNT: AtomicU64 = AtomicU64::new(0);

/// Private committed regions of the address space (base, size, protect) plus (private, image, mapped) committed totals.
fn vq_sweep() -> (Vec<(usize, usize, u32)>, [u64; 3]) {
    let mut regions = Vec::new();
    let mut tot = [0u64; 3];
    let mut addr: usize = 0;
    let mut mi = MemInfo { base: 0, alloc_base: 0, alloc_protect: 0, _pad1: 0, size: 0, state: 0, protect: 0, kind: 0, _pad2: 0 };
    while addr < 0x7FFF_FFFF_0000 {
        let n = unsafe { VirtualQuery(addr as *const c_void, &mut mi, std::mem::size_of::<MemInfo>()) };
        if n == 0 {
            break;
        }
        if mi.state == 0x1000 {
            // MEM_COMMIT; type: MEM_PRIVATE 0x20000, MEM_MAPPED 0x40000, MEM_IMAGE 0x1000000
            match mi.kind {
                0x20000 => {
                    tot[0] += mi.size as u64;
                    regions.push((mi.base, mi.size, mi.protect));
                }
                0x1000000 => tot[1] += mi.size as u64,
                0x40000 => tot[2] += mi.size as u64,
                _ => {}
            }
        }
        addr = mi.base + mi.size.max(0x1000);
    }
    (regions, tot)
}

fn deep_sample() {
    let t = qpc_now();
    let mut lines = Vec::new();
    let mut heaps = [std::ptr::null_mut::<c_void>(); 32];
    let n = unsafe { GetProcessHeaps(32, heaps.as_mut_ptr()) } as usize;
    for (i, h) in heaps.iter().take(n.min(32)).enumerate() {
        let mut hs = HeapSummary { cb: std::mem::size_of::<HeapSummary>() as u32, allocated: 0, committed: 0, reserved: 0, max_reserve: 0 };
        if unsafe { HeapSummary(*h, 0, &mut hs) } != 0 {
            lines.push(format!("H,{t},{i},{},{}", hs.committed, hs.allocated));
        }
    }
    let (regions, tot) = vq_sweep();
    lines.push(format!("V,{t},{},{},{},{}", tot[0], tot[1], tot[2], regions.len()));
    let first = DEEP_COUNT.fetch_add(1, Relaxed) == 0;
    if first {
        *DEEP_FIRST.lock().unwrap_or_else(|e| e.into_inner()) = regions.clone();
    }
    // The latest private regions replace the previous "last" list.
    let mut last = DEEP_LINES.lock().unwrap_or_else(|e| e.into_inner());
    last.retain(|l| !l.starts_with("R,last"));
    last.extend(lines);
    for (b, sz, pr) in regions {
        last.push(format!("R,last,{b},{sz},{pr}"));
    }
}

/// Reads `SWR_FRAME_LOG` and, when set, allocates the buffers. Call once, early.
pub fn init() {
    let Ok(path) = std::env::var("SWR_FRAME_LOG") else { return };
    if path.trim().is_empty() {
        return;
    }
    *PATH.lock().unwrap_or_else(|e| e.into_inner()) = Some(path);
    SPANS.lock().unwrap_or_else(|e| e.into_inner()).reserve_exact(MAX_SPANS);
    EDGES.lock().unwrap_or_else(|e| e.into_inner()).reserve_exact(MAX_EDGES);
    MEM.lock().unwrap_or_else(|e| e.into_inner()).reserve_exact(MAX_MEM);
    if std::env::var("SWR_MEM_DEEP").map(|v| v.trim() == "1").unwrap_or(false) {
        DEEP.store(true, Relaxed);
    }
    ENABLED.store(true, Relaxed);
}

#[inline]
pub fn enabled() -> bool {
    ENABLED.load(Relaxed)
}

/// Records a UI-thread span (no-op unless the trace is on or the buffer is full).
#[inline]
pub fn span(kind: u8, t0: i64, t1: i64) {
    if !enabled() {
        return;
    }
    let mut v = SPANS.lock().unwrap_or_else(|e| e.into_inner());
    if v.len() < v.capacity() {
        v.push((kind, t0, t1));
    }
}

/// Records a composition edge seen by the pacing thread and the time its paint message was posted (0 = none).
pub fn edge(edge_qpc: i64, post_qpc: i64) {
    if !enabled() {
        return;
    }
    let mut v = EDGES.lock().unwrap_or_else(|e| e.into_inner());
    if v.len() < v.capacity() {
        v.push((edge_qpc, post_qpc));
    }
}

/// Memory sample: Rust allocator live bytes and count, process private bytes and working set.
pub fn memory_sample() {
    if !enabled() {
        return;
    }
    let (private, ws) = process_memory();
    let n = {
        let mut v = MEM.lock().unwrap_or_else(|e| e.into_inner());
        if v.len() < v.capacity() {
            v.push((qpc_now(), rust_live_bytes(), rust_allocs(), private, ws));
        }
        v.len()
    };
    if DEEP.load(Relaxed) && n % 5 == 1 {
        deep_sample();
    }
}

/// Writes the trace file (UI thread, after the loop ended). Failures are reported on stderr, never fatal.
pub fn dump() {
    if !enabled() {
        return;
    }
    ENABLED.store(false, Relaxed);
    let Some(path) = PATH.lock().unwrap_or_else(|e| e.into_inner()).clone() else { return };
    let mut out = String::with_capacity(4 << 20);
    out.push_str(&format!("# swr-trace qpc_hz={}\n", qpc_freq()));
    out.push_str("# kinds: 1=wm_paint 2=frame 3=paint_root 4=paced_handler 5=commit 6=host_tick 7=host_drain 8=present 9=ime_callback\n");
    for (a, b) in EDGES.lock().unwrap_or_else(|e| e.into_inner()).iter() {
        out.push_str(&format!("E,{a},{b}\n"));
    }
    for (k, a, b) in SPANS.lock().unwrap_or_else(|e| e.into_inner()).iter() {
        out.push_str(&format!("S,{k},{a},{b}\n"));
    }
    for (t, live, allocs, private, ws) in MEM.lock().unwrap_or_else(|e| e.into_inner()).iter() {
        out.push_str(&format!("M,{t},{live},{allocs},{private},{ws}\n"));
    }
    if DEEP.load(Relaxed) {
        for (b, sz, pr) in DEEP_FIRST.lock().unwrap_or_else(|e| e.into_inner()).iter() {
            out.push_str(&format!("R,first,{b},{sz},{pr}\n"));
        }
        for l in DEEP_LINES.lock().unwrap_or_else(|e| e.into_inner()).iter() {
            out.push_str(l);
            out.push('\n');
        }
    }
    // rightkit-logs writes the buffer in one append (its own trailing newline ends the file, as before).
    // A 1-byte rotation threshold rolls the previous run's non-empty file to `<name>.1` first, so the
    // named file holds only this run, as `fs::write` made it. A failed roll refuses the write above
    // 2 bytes; that error is returned and reported below.
    let writer = rightkit_logs::RotatingTextWriter::new(&path, 1);
    match writer.write_line(out.trim_end_matches('\n')) {
        Ok(()) => eprintln!("[swiftright-render] trace written: {path}"),
        Err(e) => eprintln!("[swiftright-render] trace write failed: {path}: {e}"),
    }
}
