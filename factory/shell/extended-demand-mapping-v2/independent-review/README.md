# F12 current-source bindings independent review

V2 stage has 14 exact files totaling 29932 bytes. Two source snapshots pass byte/hash validation. Stage input path for source manifest is packet-relative and resolves correctly from v2 root.

Five catalogue path+USR pairs resolve uniquely with inventory status and no registry selectors. EditorScreen lines 16, 30, 31, 34, and 53 occur once as raw bytes; no whitespace normalization occurs. Historical `slice-model` indentation drift remains explicit & hash-preserving.

List, ForEach, TextField, and FocusState USRs identify nominal declaration families; source lines do not resolve one initializer overload. `onMove` has exact method USR. Candidate preserves 107-row v1 denominator, binds two rows, & emits zero registry IDs.

Fault controls cover source replacement, whitespace, duplicate lines, immutable pins, missing snapshots, path/USR mutation, & overload-USR substitution.
