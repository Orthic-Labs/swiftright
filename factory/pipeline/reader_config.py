"""Strict opt-in loader for explicit F10 archive-reader roots."""
from __future__ import annotations

import json
from pathlib import Path, PurePosixPath
import re

from factory.pipeline.archive_reader import ArchiveByteReader


_CAPTURE_HASH = re.compile(r"[0-9a-f]{64}\Z")


def _unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate reader-config key: {key}")
        value[key] = item
    return value


def _physical_path(base: Path, value, label: str) -> Path:
    if (not isinstance(value, str) or not value or "\x00" in value or "\\" in value
            or Path(value).is_absolute()):
        raise ValueError(f"{label} must be a nonempty config-relative path")
    try:
        target = (base / value).resolve(strict=True)
    except OSError as exc:
        raise ValueError(f"{label} target is missing or unresolved") from exc
    return target


def load_origin_reader_config(path: str | Path) -> ArchiveByteReader:
    """Load exact config bytes & construct explicit archive reader.

    Accepted JSON shape is exactly ``version``, ``macRoots``,
    ``windowsArchives`` & ``macPathMap``. Physical paths are relative to
    config file directory; no roots are inferred or widened.
    """
    config_path = Path(path).expanduser().resolve(strict=True)
    if not config_path.is_file():
        raise ValueError("origin-reader config must be a regular file")
    try:
        value = json.loads(config_path.read_bytes().decode("utf-8"), object_pairs_hook=_unique_object,
                           parse_constant=lambda _: (_ for _ in ()).throw(ValueError("invalid JSON constant")))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("origin-reader config must be UTF-8 JSON") from exc
    if not isinstance(value, dict) or set(value) != {"version", "macRoots", "windowsArchives", "macPathMap"}:
        raise ValueError("origin-reader config requires exact version/macRoots/windowsArchives/macPathMap fields")
    if type(value["version"]) is not int or value["version"] != 1:
        raise ValueError("origin-reader config version must be integer 1")
    mac_roots_value = value["macRoots"]
    windows_value = value["windowsArchives"]
    path_map_value = value["macPathMap"]
    if not isinstance(mac_roots_value, list) or not all(isinstance(item, str) for item in mac_roots_value):
        raise ValueError("macRoots must be array of relative path strings")
    if not isinstance(windows_value, dict) or not isinstance(path_map_value, dict):
        raise ValueError("windowsArchives & macPathMap must be objects")

    base = config_path.parent
    mac_roots = [_physical_path(base, item, "macRoots item") for item in mac_roots_value]
    windows_archives = {}
    for capture_hash, location in windows_value.items():
        if not isinstance(capture_hash, str) or not _CAPTURE_HASH.fullmatch(capture_hash):
            raise ValueError("windowsArchives keys must be lowercase canonical capture hashes without prefix")
        windows_archives[capture_hash] = _physical_path(base, location, "windowsArchives value")
    mac_path_map = {}
    for logical_path, location in path_map_value.items():
        normalized = PurePosixPath(logical_path) if isinstance(logical_path, str) else None
        if (not isinstance(logical_path, str) or not logical_path.startswith("/")
                or "\x00" in logical_path or ".." in normalized.parts
                or str(normalized) != logical_path):
            raise ValueError("macPathMap keys must be normalized absolute reference paths")
        mac_path_map[logical_path] = _physical_path(base, location, "macPathMap value")
    if not mac_roots and not windows_archives:
        raise ValueError("reader config must explicitly admit at least one root/archive")
    return ArchiveByteReader(mac_roots=mac_roots, windows_archives=windows_archives,
                             mac_path_map=mac_path_map)
