#!/usr/bin/env python3
"""usage: gaps.py <fetched pulse tree> : use sites (file:line) of every API the Windows probe had to stub or patch, and the hub sections each blocks.
Sites are found by regex over Pulse's sources (exact, not compiler-capped); a site blocks a section when the section's own files contain it, or when it is
in a RightKitHub file whose types the section uses (shell files block all twelve)."""
import re, sys, pathlib, json, collections
root = pathlib.Path(sys.argv[1])
SECTIONS = "overview activity storage cleanup monitor apps chat permissions accounts appearance notifications general".split()
GAPS = [  # id, label, regex
 ("G01", "AnyView", r"\bAnyView\b"),
 ("G02", "accessibilityElement(children:)", r"\.accessibilityElement\("),
 ("G03", "accessibilityValue(_:)", r"\.accessibilityValue\("),
 ("G04", "accessibilityAddTraits(_:)", r"\.accessibilityAddTraits\("),
 ("G05", "accessibilityHint(_:)", r"\.accessibilityHint\("),
 ("G06", "accessibilityHidden(_:)", r"\.accessibilityHidden\("),
 ("G07", "Text(verbatim:)", r"Text\(verbatim:"),
 ("G08", "State(initialValue:)", r"State\(initialValue:"),
 ("G09", "Color.clear", r"\bColor\.clear\b"),
 ("G10", "Color.opacity(_:) returning Color (fill(Color.x.opacity()))", r"\.color\.opacity\(|Color\.black\.opacity\("),
 ("G11", "ViewBuilder single-child identity (Trailing == HubNoTrailing)", r"\{ HubNoTrailing\(\) \}|Trailing == HubNoTrailing|Footer == HubNoTrailing"),
 ("G12", "VerticalAlignment.firstTextBaseline", r"\.firstTextBaseline"),
 ("G13", "Font.Weight.heavy (and light/thin/black)", r"\.heavy\b"),
 ("G14", "Font.width(_:)", r"\.width\(\.(condensed|expanded|standard)\)"),
 ("G15", "layoutPriority(_:)", r"\.layoutPriority\("),
 ("G16", "View.id(_:)", r"\)\.id\(|\.id\(section"),
 ("G17", "TextField(_:text:axis:)", r"axis: \.vertical"),
 ("G18", "ViewModifier + Content", r"\bViewModifier\b"),
 ("G19", "Scene / WindowGroup", r"\bWindowGroup\b|some Scene"),
 ("G20", "RelativeDateTimeFormatter (Foundation)", r"RelativeDateTimeFormatter"),
]
files = [p for p in root.rglob("*.swift") if "pulse-hub-render" not in str(p) and "rightkit-engine-probe" not in str(p) and "RightKitEngine/" not in str(p)]
def section_of_pulse(p):
    s = str(p)
    for sec, key in (("overview","Overview"),("activity","Activity"),("storage","Storage"),("cleanup","Cleanup"),("monitor","Monitor"),("apps","Apps"),("chat","Chat")):
        if f"/Sections/{key}/" in s or s.endswith(f"/Sections/{key}Section.swift"): return [sec]
    m = re.search(r"Settings(Permissions|Accounts|Appearance|Notifications|General)Page", s)
    if m: return [m[1].lower()]
    if "/Sections/Settings/" in s or "SettingsSections" in s: return ["permissions","accounts","appearance","notifications","general"]
    return None
hub_files = [p for p in files if "/RightKitHub/Sources/RightKitHub/" in str(p)]
shell = {"HubShell","HubSidebar","HubHeader","HubSearch","HubStates","HubTheme","HubToast","HubSection","HubNavigate","HubBrand","HubExports"}
pulse_files = [p for p in files if "/mac/Hub/Sources/" in str(p)]
pulse_text = {p: p.read_text() for p in pulse_files}
def rk_types(p):
    return set(re.findall(r"(?:struct|enum|class|protocol|extension|func)\s+(Hub\w+)", p.read_text()))
def sections_of(p):
    s = section_of_pulse(p)
    if s is not None: return s
    if "/RightKitHub/Sources/RightKitHub/" in str(p):
        if p.stem in shell: return list(SECTIONS)
        if p.stem == "HubScene": return []   # the app scene helper, no section draws through it
        names = rk_types(p) | {p.stem}
        out = set()
        for q, t in pulse_text.items():
            sec = section_of_pulse(q)
            if sec and any(re.search(rf"\b{n}\b", t) for n in names): out.update(sec)
        return sorted(out, key=SECTIONS.index) if out else list(SECTIONS)
    if "PulseHub/PulseHub.swift" in str(p) or "PulseFormat" in str(p) or "PulseTheme" in str(p): return list(SECTIONS)
    return []
res = []
for gid, label, rx in GAPS:
    sites, secs = [], set()
    for p in files:
        if p.name in ("PlatformServicesMac.swift",): continue
        for n, line in enumerate(p.read_text().splitlines(), 1):
            if line.strip().startswith("//") or line.strip().startswith("///"): continue
            if re.search(rx, line):
                rel = str(p.relative_to(root)); sites.append(f"{rel}:{n}"); secs.update(sections_of(p))
    res.append(dict(id=gid, api=label, sites=len(sites), files=len({s.rsplit(':',1)[0] for s in sites}), sections=sorted(secs, key=SECTIONS.index), nsections=len(secs), first=sites[:6], all=sites))
res.sort(key=lambda r: (-r["nsections"], -r["sites"]))
json.dump(res, open(sys.argv[2] if len(sys.argv) > 2 else "/dev/stdout", "w"), indent=1)
