# Text F10 production reader input r1

Source-only bounded adapter for measured Windows Text20 export at
`factory/native/windows/pilot-text-paint-root-v2/actual-count20-r10-r1`.
It verifies export rows, all 20 native proof directories, measured plan,
compiler receipt, tuple, case, source, runtime, serializer, executable &
renderer joins. File hashes stream in 1MiB chunks; archive reads stay within
256MiB total & 256MiB per file.

Mac input is existing paired report. Adapter preserves its observed AX/DIP,
paint & terminal holds; it never promotes semantic or timing qualification.
Current Mac report must retain `Mac original-process exit/cleanup evidence
absent`, since `owned-window-process.json` supplies retained handle/PID/path
but no native exit/cleanup receipt.

Root invocation after fresh report-r3:

```sh
python3 factory/pipeline/pilot-next-source-v1/text-f10-reader-root-v1/prepare_text_f10_reader_input.py \
  --windows-archive factory/native/windows/pilot-text-paint-root-v2/actual-count20-r10-r1 \
  --mac-report factory/pipeline/pilot-next-source-v1/paired-text-paint-r12-root-v1/actual-paired-report-r3.json \
  --output <fresh-output>/text-f10-reader-input-r1.json
```

Output remains `qualified=false`, `nativeActions=0`, `nativeParity=held`.
Root may feed explicit `windowsArchives.text` into existing
`factory.pipeline.archive_reader.ArchiveByteReader` & run existing
`factory.gate.windows_exit_admission`; no discovery or fuzzy joins are used.

Pure source controls:

```sh
python3 factory/pipeline/pilot-next-source-v1/text-f10-reader-root-v1/test_text_f10_reader_controls.py \
  --mac-report factory/pipeline/pilot-next-source-v1/paired-text-paint-r12-root-v1/actual-paired-report-r3.json
```
