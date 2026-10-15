#!/usr/bin/env python3
"""usage: bypass.py <assembled probe dir> : the temporary source bypasses, each recorded. Pulse's code is otherwise copied unmodified.
B1 PulseHub/PulseFormat.swift: RelativeDateTimeFormatter does not exist in Foundation on Windows (a platform gap, not a SwiftRight one);
   the function body is replaced by a minimal relative-time string so the rest of the module can build."""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "Sources/PulseHub/PulseFormat.swift"
s = p.read_text()
old = """        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)"""
new = """        // BYPASS B1 (probe): RelativeDateTimeFormatter is not in Foundation on Windows.
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\\(s / 60) min ago" }
        if s < 86400 { return "\\(s / 3600) hr ago" }
        return "\\(s / 86400) days ago\""""
new = new.rstrip('"') if False else new
assert old in s, "pattern not found"
p.write_text(s.replace(old, new.replace('days ago\\""', 'days ago"')))
print("B1 applied")
