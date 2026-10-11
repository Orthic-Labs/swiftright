#!/usr/bin/env python3
"""Bounded Windows PowerShell inventory & explicitly authorized owned cancel.

Default mode only inventories. Cancellation requires root-issued JSON with exact
PID, image, start FILETIME, full command-line hash, encoded-command hash, and
short UTC validity window. PID/name alone can never terminate a process.
"""
from __future__ import annotations

import argparse
import ctypes
import ctypes.wintypes as wt
import hashlib
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

MAX_PROCESSES = 2048
MAX_COMMANDLINE_BYTES = 64 * 1024
MAX_COMMANDLINE_PREVIEW = 512
MAX_OUTPUT_BYTES = 2 * 1024 * 1024
DEADLINE_SECONDS = 20.0
CANCEL_WAIT_SECONDS = 10.0
MEMORY_LIMIT_BYTES = 128 * 1024 * 1024
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
PROCESS_VM_READ = 0x0010
PROCESS_TERMINATE = 0x0001
SYNCHRONIZE = 0x00100000
PROCESS_ALL_READ = PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ
PROCESS_CANCEL_ACCESS = PROCESS_ALL_READ | PROCESS_TERMINATE | SYNCHRONIZE
TH32CS_SNAPPROCESS = 0x00000002
STILL_ACTIVE = 259
WAIT_OBJECT_0 = 0
WAIT_TIMEOUT = 258
JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
JOB_OBJECT_LIMIT_JOB_MEMORY = 0x200

# ctypes.wintypes does not expose these aliases consistently across Python builds.
ULONG_PTR = ctypes.c_size_t
SIZE_T = ctypes.c_size_t

if sys.platform != "win32":
    raise SystemExit("Windows-only helper")

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll", use_last_error=True)


class FILETIME(ctypes.Structure):
    _fields_ = [("dwLowDateTime", wt.DWORD), ("dwHighDateTime", wt.DWORD)]


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ProcessID", wt.DWORD),
        ("th32DefaultHeapID", ULONG_PTR), ("th32ModuleID", wt.DWORD),
        ("cntThreads", wt.DWORD), ("th32ParentProcessID", wt.DWORD),
        ("pcPriClassBase", wt.LONG), ("dwFlags", wt.DWORD), ("szExeFile", wt.WCHAR * 260),
    ]


class UNICODE_STRING(ctypes.Structure):
    _fields_ = [("Length", wt.USHORT), ("MaximumLength", wt.USHORT), ("Buffer", wt.LPVOID)]


class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
    _fields_ = [
        ("cb", wt.DWORD), ("PageFaultCount", wt.DWORD), ("PeakWorkingSetSize", SIZE_T),
        ("WorkingSetSize", SIZE_T), ("QuotaPeakPagedPoolUsage", SIZE_T),
        ("QuotaPagedPoolUsage", SIZE_T), ("QuotaPeakNonPagedPoolUsage", SIZE_T),
        ("QuotaNonPagedPoolUsage", SIZE_T), ("PagefileUsage", SIZE_T),
        ("PeakPagefileUsage", SIZE_T), ("PrivateUsage", SIZE_T),
    ]


class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", ctypes.c_longlong), ("PerJobUserTimeLimit", ctypes.c_longlong),
        ("LimitFlags", wt.DWORD), ("MinimumWorkingSetSize", SIZE_T),
        ("MaximumWorkingSetSize", SIZE_T), ("ActiveProcessLimit", wt.DWORD),
        ("Affinity", ULONG_PTR), ("PriorityClass", wt.DWORD), ("SchedulingClass", wt.DWORD),
    ]


class IO_COUNTERS(ctypes.Structure):
    _fields_ = [(name, ctypes.c_ulonglong) for name in (
        "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
        "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]


class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION), ("IoInfo", IO_COUNTERS),
        ("ProcessMemoryLimit", SIZE_T), ("JobMemoryLimit", SIZE_T),
        ("PeakProcessMemoryUsed", SIZE_T), ("PeakJobMemoryUsed", SIZE_T),
    ]


kernel32.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
kernel32.CreateToolhelp32Snapshot.restype = wt.HANDLE
kernel32.Process32FirstW.argtypes = [wt.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
kernel32.Process32FirstW.restype = wt.BOOL
kernel32.Process32NextW.argtypes = [wt.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
kernel32.Process32NextW.restype = wt.BOOL
kernel32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
kernel32.OpenProcess.restype = wt.HANDLE
kernel32.CloseHandle.argtypes = [wt.HANDLE]
kernel32.CloseHandle.restype = wt.BOOL
kernel32.QueryFullProcessImageNameW.argtypes = [wt.HANDLE, wt.DWORD, wt.LPWSTR, ctypes.POINTER(wt.DWORD)]
kernel32.QueryFullProcessImageNameW.restype = wt.BOOL
kernel32.GetProcessTimes.argtypes = [wt.HANDLE, ctypes.POINTER(FILETIME), ctypes.POINTER(FILETIME), ctypes.POINTER(FILETIME), ctypes.POINTER(FILETIME)]
kernel32.GetProcessTimes.restype = wt.BOOL
kernel32.GetExitCodeProcess.argtypes = [wt.HANDLE, ctypes.POINTER(wt.DWORD)]
kernel32.GetExitCodeProcess.restype = wt.BOOL
kernel32.TerminateProcess.argtypes = [wt.HANDLE, wt.UINT]
kernel32.TerminateProcess.restype = wt.BOOL
kernel32.WaitForSingleObject.argtypes = [wt.HANDLE, wt.DWORD]
kernel32.WaitForSingleObject.restype = wt.DWORD
kernel32.CreateJobObjectW.argtypes = [wt.LPVOID, wt.LPCWSTR]
kernel32.CreateJobObjectW.restype = wt.HANDLE
kernel32.SetInformationJobObject.argtypes = [wt.HANDLE, wt.INT, wt.LPVOID, wt.DWORD]
kernel32.SetInformationJobObject.restype = wt.BOOL
kernel32.AssignProcessToJobObject.argtypes = [wt.HANDLE, wt.HANDLE]
kernel32.AssignProcessToJobObject.restype = wt.BOOL
kernel32.GetCurrentProcess.restype = wt.HANDLE
psapi.GetProcessMemoryInfo.argtypes = [wt.HANDLE, wt.LPVOID, wt.DWORD]
psapi.GetProcessMemoryInfo.restype = wt.BOOL
ntdll.NtQueryInformationProcess.argtypes = [wt.HANDLE, wt.ULONG, wt.LPVOID, wt.ULONG, ctypes.POINTER(wt.ULONG)]
ntdll.NtQueryInformationProcess.restype = wt.LONG


def win_error(prefix: str) -> str:
    return f"{prefix}: win32={ctypes.get_last_error()}"


def ensure_deadline(deadline: float) -> None:
    if time.monotonic() > deadline:
        raise TimeoutError("inventory deadline exceeded")


def filetime_value(value: FILETIME) -> int:
    return (int(value.dwHighDateTime) << 32) | int(value.dwLowDateTime)


def filetime_iso(value: FILETIME) -> str:
    ticks = filetime_value(value)
    stamp = datetime(1601, 1, 1, tzinfo=timezone.utc).timestamp() + ticks / 10_000_000
    return datetime.fromtimestamp(stamp, timezone.utc).isoformat().replace("+00:00", "Z")


def close_handle(handle: wt.HANDLE | None) -> None:
    if handle and handle != wt.HANDLE(-1).value:
        kernel32.CloseHandle(handle)


def open_process(pid: int, access: int = PROCESS_ALL_READ) -> wt.HANDLE:
    handle = kernel32.OpenProcess(access, False, pid)
    if not handle:
        raise OSError(win_error("OpenProcess failed"))
    return handle


def process_path(handle: wt.HANDLE) -> str:
    capacity = wt.DWORD(32768)
    buffer = ctypes.create_unicode_buffer(capacity.value)
    if not kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(capacity)):
        raise OSError(win_error("QueryFullProcessImageNameW failed"))
    return buffer.value[: capacity.value]


def process_start(handle: wt.HANDLE) -> tuple[int, str]:
    created, exited, kernel, user = FILETIME(), FILETIME(), FILETIME(), FILETIME()
    if not kernel32.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited), ctypes.byref(kernel), ctypes.byref(user)):
        raise OSError(win_error("GetProcessTimes failed"))
    return filetime_value(created), filetime_iso(created)


def process_memory(handle: wt.HANDLE) -> tuple[int, int]:
    counters = PROCESS_MEMORY_COUNTERS_EX()
    counters.cb = ctypes.sizeof(counters)
    if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
        raise OSError(win_error("GetProcessMemoryInfo failed"))
    return int(counters.WorkingSetSize), int(counters.PrivateUsage)


def process_command_line(handle: wt.HANDLE) -> tuple[str, str, int, bool]:
    raw = ctypes.create_string_buffer(MAX_COMMANDLINE_BYTES)
    returned = wt.ULONG(0)
    status = ntdll.NtQueryInformationProcess(handle, 60, raw, len(raw), ctypes.byref(returned))
    if status != 0:
        raise OSError(f"NtQueryInformationProcess failed: status=0x{status & 0xffffffff:08x}")
    if int(returned.value) < ctypes.sizeof(UNICODE_STRING):
        raise ValueError("ProcessCommandLineInformation returned truncated descriptor")
    descriptor = UNICODE_STRING.from_buffer(raw)
    byte_length = int(descriptor.Length)
    if not descriptor.Buffer or byte_length <= 0:
        return "", hashlib.sha256(b"").hexdigest(), 0, False
    local_base = ctypes.addressof(raw)
    local_end = local_base + len(raw)
    local_pointer = int(descriptor.Buffer or 0)
    if local_pointer < local_base or local_pointer > local_end or byte_length > local_end - local_pointer:
        raise ValueError("ProcessCommandLineInformation returned out-of-buffer string")
    data = ctypes.string_at(local_pointer, byte_length)
    truncated = bool(int(returned.value) > len(raw) or byte_length > MAX_COMMANDLINE_BYTES - 2)
    text = data.decode("utf-16-le", errors="replace").rstrip("\x00")
    return text, hashlib.sha256(data).hexdigest(), len(data), truncated


def snapshot_processes(deadline: float) -> list[PROCESSENTRY32W]:
    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snapshot == wt.HANDLE(-1).value:
        raise OSError(win_error("CreateToolhelp32Snapshot failed"))
    try:
        entry = PROCESSENTRY32W(); entry.dwSize = ctypes.sizeof(entry)
        rows: list[PROCESSENTRY32W] = []
        visited = 0
        if not kernel32.Process32FirstW(snapshot, ctypes.byref(entry)):
            raise OSError(win_error("Process32FirstW failed"))
        while True:
            ensure_deadline(deadline)
            visited += 1
            if visited > MAX_PROCESSES:
                raise RuntimeError("Toolhelp process cap exceeded")
            if entry.szExeFile.lower() == "powershell.exe":
                rows.append(PROCESSENTRY32W.from_buffer_copy(entry))
            if not kernel32.Process32NextW(snapshot, ctypes.byref(entry)):
                break
        return rows
    finally:
        close_handle(snapshot)


def inspect_entry(entry: PROCESSENTRY32W, deadline: float) -> dict[str, object]:
    ensure_deadline(deadline)
    row: dict[str, object] = {
        "pid": int(entry.th32ProcessID), "parentPid": int(entry.th32ParentProcessID),
        "exeName": str(entry.szExeFile), "imagePath": "", "startTimeFileTime": 0,
        "startTimeUtc": "", "commandLine": "", "commandLineSha256": "",
        "commandLineBytes": 0, "commandLineTruncated": False, "encodedCommandSha256": "",
        "workingSetBytes": 0, "privateBytes": 0, "openError": "", "queryErrors": "",
    }
    handle = None
    errors: list[str] = []
    try:
        handle = open_process(int(entry.th32ProcessID))
        for name, func in (("image", process_path), ("start", process_start), ("command", process_command_line), ("memory", process_memory)):
            ensure_deadline(deadline)
            try:
                result = func(handle)
                if name == "image": row["imagePath"] = result
                elif name == "start": row["startTimeFileTime"], row["startTimeUtc"] = result
                elif name == "command":
                    full_command, command_hash, command_bytes, command_truncated = result
                    row["commandLineSha256"] = command_hash
                    row["commandLineBytes"] = command_bytes
                    row["commandLineTruncated"] = command_truncated
                    encoded = re.search(r"(?i)(?:^|\s)-(?:EncodedCommand|enc)\s+([^\s]+)", full_command)
                    row["encodedCommandSha256"] = hashlib.sha256((encoded.group(1) if encoded else "").encode("utf-8")).hexdigest()
                    row["commandLine"] = full_command[:MAX_COMMANDLINE_PREVIEW]
                else: row["workingSetBytes"], row["privateBytes"] = result
            except Exception as exc: errors.append(f"{name}:{exc}")
    except Exception as exc: row["openError"] = str(exc)
    finally: close_handle(handle)
    row["queryErrors"] = ";".join(errors)
    return row


def install_self_job() -> tuple[wt.HANDLE, str]:
    job = kernel32.CreateJobObjectW(None, None)
    if not job: raise OSError(win_error("CreateJobObjectW failed"))
    info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_JOB_MEMORY
    info.JobMemoryLimit = MEMORY_LIMIT_BYTES
    if not kernel32.SetInformationJobObject(job, JOB_OBJECT_EXTENDED_LIMIT_INFORMATION, ctypes.byref(info), ctypes.sizeof(info)):
        close_handle(job); raise OSError(win_error("SetInformationJobObject failed"))
    if not kernel32.AssignProcessToJobObject(job, kernel32.GetCurrentProcess()):
        close_handle(job); raise OSError(win_error("AssignProcessToJobObject failed"))
    return job, "aggregate-job-memory-128MiB-flag-0x200-no-kill-on-close"


def parse_control(path: str) -> dict[str, object]:
    control_file = Path(path)
    stat = control_file.stat()
    if control_file.is_symlink() or not control_file.is_file() or stat.st_size > MAX_OUTPUT_BYTES:
        raise ValueError("bounded regular cancellation JSON required")
    with control_file.open("rb") as stream:
        raw = stream.read(MAX_OUTPUT_BYTES + 1)
    if len(raw) > MAX_OUTPUT_BYTES: raise ValueError("cancellation JSON exceeds 2MiB")
    value = json.loads(raw.decode("utf-8"))
    required = {"kind", "pid", "exeName", "imagePath", "startTimeFileTime", "commandLineSha256", "allowedEncodedCommandSha256", "issuedAtUtc", "expiresAtUtc", "allowTerminate"}
    if not required.issubset(value): raise ValueError("cancellation control missing identity fields")
    if value["kind"] != "factory-owned-cancellation-v1" or value["exeName"].lower() != "powershell.exe" or value["allowTerminate"] is not True:
        raise ValueError("cancellation control kind or executable rejected")
    if not isinstance(value["allowedEncodedCommandSha256"], list) or not value["allowedEncodedCommandSha256"]:
        raise ValueError("encoded-command allowlist required")
    if len(value["allowedEncodedCommandSha256"]) > 16 or int(value["pid"]) <= 0 or int(value["startTimeFileTime"]) <= 0:
        raise ValueError("cancellation identity bounds rejected")
    if not re.match(r"^[A-Za-z]:\\", str(value["imagePath"])):
        raise ValueError("cancellation image path must be absolute Windows path")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", str(value["commandLineSha256"])) or any(not re.fullmatch(r"[0-9a-fA-F]{64}", str(item)) for item in value["allowedEncodedCommandSha256"]):
        raise ValueError("cancellation SHA256 identity fields malformed")
    return value


def cancel_owned(control_path: str, deadline: float) -> dict[str, object]:
    control = parse_control(control_path)
    now = datetime.now(timezone.utc)
    issued = datetime.fromisoformat(str(control["issuedAtUtc"]).replace("Z", "+00:00"))
    expires = datetime.fromisoformat(str(control["expiresAtUtc"]).replace("Z", "+00:00"))
    if issued.tzinfo is None or expires.tzinfo is None: raise ValueError("cancellation timestamps must be UTC-aware")
    if not issued <= now <= expires: raise ValueError("cancellation control outside UTC validity window")
    if (expires - issued).total_seconds() > 20: raise ValueError("cancellation validity window exceeds 20 seconds")
    pid = int(control["pid"])
    handle = open_process(pid, PROCESS_CANCEL_ACCESS)
    try:
        actual_path = process_path(handle)
        actual_start, actual_start_iso = process_start(handle)
        full_command, command_hash, command_bytes, command_truncated = process_command_line(handle)
        if command_truncated:
            raise ValueError("owned cancellation command line exceeds 64 KiB")
        encoded = re.search(r"(?i)(?:^|\s)-(?:EncodedCommand|enc)\s+([^\s]+)", full_command)
        encoded_hash = hashlib.sha256((encoded.group(1) if encoded else "").encode("utf-8")).hexdigest()
        if (actual_path.lower() != str(control["imagePath"]).lower() or actual_start != int(control["startTimeFileTime"])
                or command_hash.lower() != str(control["commandLineSha256"]).lower()
                or encoded_hash.lower() not in [str(item).lower() for item in control["allowedEncodedCommandSha256"]]):
            raise ValueError("owned cancellation identity recheck failed")
        ensure_deadline(deadline)
        if not kernel32.TerminateProcess(handle, 1): raise OSError(win_error("TerminateProcess failed"))
        wait_started = time.monotonic()
        wait = kernel32.WaitForSingleObject(handle, int(CANCEL_WAIT_SECONDS * 1000))
        wait_ms = int((time.monotonic() - wait_started) * 1000)
        if wait != WAIT_OBJECT_0: raise TimeoutError("owned cancellation did not reach terminal state")
        return {"status": "cancelled", "pid": pid, "imagePath": actual_path, "startTimeUtc": actual_start_iso, "commandLineBytes": command_bytes, "commandLineTruncated": command_truncated, "identityRechecked": True, "waitMs": wait_ms, "nativeActions": 1}
    finally: close_handle(handle)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("inventory", "cancel"), default="inventory")
    parser.add_argument("--control-json")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    started = time.monotonic(); deadline = started + DEADLINE_SECONDS
    job = None
    try:
        job, job_status = install_self_job()
        if args.mode == "cancel":
            if not args.control_json: raise ValueError("--control-json required for cancel")
            result = cancel_owned(args.control_json, deadline)
        else:
            rows = [inspect_entry(entry, deadline) for entry in snapshot_processes(deadline)]
            result = {"kind": "factory-windows-process-inventory-v1", "status": "inventory", "candidateCount": len(rows), "processes": rows, "deadlineSeconds": DEADLINE_SECONDS, "selfJob": job_status, "nativeActions": 0}
        encoded = json.dumps(result, ensure_ascii=False, separators=(",", ":"))
        if len(encoded.encode("utf-8")) > MAX_OUTPUT_BYTES: raise ValueError("inventory JSON exceeds 2MiB")
        with open(args.output, "x", encoding="utf-8", newline="\n") as stream: stream.write(encoded + "\n")
        return 0
    except Exception as exc:
        print(f"windows-process-inventory failed: {exc}", file=sys.stderr)
        return 2
    finally:
        close_handle(job)


if __name__ == "__main__": raise SystemExit(main())
