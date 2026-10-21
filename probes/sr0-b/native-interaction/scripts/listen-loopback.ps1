# Records the default speaker output (WASAPI loopback) for -Seconds to -Wav (16-bit PCM), then transcribes it offline with the
# built-in Windows recognizer (System.Speech, en-US dictation) to -Json: [{ "offsetMs": n, "durationMs": n, "text": "..." }].
# Used by the R9 narrator check so Narrator's spoken output is checked from a transcript, not by a person listening (#23).
# Must run in the interactive desktop session (the console's audio endpoint). Built-in Windows APIs only; no installs.
# Optional: -Phrases (a list, or one string with '|' separators) adds a closed phrase grammar (wildcard + any one phrase + wildcard)
# next to the dictation grammar, which stays loaded as the fallback so unmatched speech is not forced onto a phrase. With -Phrases each
# result also carries "grammar" ('phrase' | 'dictation') and the JSON adds signal stats. -StopFile ends the recording when the file appears
# (-Seconds is then only the upper bound). -ReadyFile is written once capture has actually started.
param(
  [Parameter(Mandatory)][string]$Wav,
  [Parameter(Mandatory)][string]$Json,
  [int]$Seconds = 60,
  [string]$ReadyFile = '',
  [string[]]$Phrases = @(),
  [string]$StopFile = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

public static class Loopback {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator { int EnumAudioEndpoints(int a, int b, out IntPtr c); int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice dev); }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice { int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
    [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioClient {
        int Initialize(int shareMode, int flags, long bufferDuration, long periodicity, IntPtr format, IntPtr session);
        int GetBufferSize(out uint frames); int GetStreamLatency(out long l); int GetCurrentPadding(out uint p);
        int IsFormatSupported(int m, IntPtr f, out IntPtr c); int GetMixFormat(out IntPtr format); int GetDevicePeriod(out long d, out long m);
        int Start(); int Stop(); int Reset(); int SetEventHandle(IntPtr h);
        int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }
    [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioCaptureClient {
        int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devPos, out ulong qpcPos);
        int ReleaseBuffer(uint frames); int GetNextPacketSize(out uint frames);
    }
    const int AUDCLNT_STREAMFLAGS_LOOPBACK = 0x00020000;
    const uint AUDCLNT_BUFFERFLAGS_SILENT = 0x2;

    // Returns the number of 16-bit mono samples written; the WAV is 16 kHz-free (device rate), mono, 16-bit.
    public static int LastRate; public static long NonZero; public static int Peak;
    public static long Record(string path, int seconds, string stopFile, string readyFile) {
        var en = (IMMDeviceEnumerator)new MMDeviceEnumerator();
        IMMDevice dev; Check(en.GetDefaultAudioEndpoint(0 /*eRender*/, 1 /*eMultimedia*/, out dev));
        var iidClient = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"); object o;
        Check(dev.Activate(ref iidClient, 23 /*CLSCTX_ALL*/, IntPtr.Zero, out o));
        var client = (IAudioClient)o;
        IntPtr fmt; Check(client.GetMixFormat(out fmt));
        short channels = Marshal.ReadInt16(fmt, 2); int rate = Marshal.ReadInt32(fmt, 4); short bits = Marshal.ReadInt16(fmt, 14);
        short tag = Marshal.ReadInt16(fmt, 0); bool isFloat = tag == 3;
        if (tag == unchecked((short)0xFFFE)) { // WAVE_FORMAT_EXTENSIBLE: SubFormat GUID at offset 24
            var sub = new byte[16]; Marshal.Copy(fmt + 24, sub, 0, 16); isFloat = new Guid(sub) == new Guid("00000003-0000-0010-8000-00aa00389b71");
        }
        Check(client.Initialize(0 /*shared*/, AUDCLNT_STREAMFLAGS_LOOPBACK, 10000000 /*1 s*/, 0, fmt, IntPtr.Zero));
        var iidCap = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"); object co;
        Check(client.GetService(ref iidCap, out co)); var cap = (IAudioCaptureClient)co;
        var ms = new MemoryStream(); var bw = new BinaryWriter(ms);
        int bytesPer = bits / 8; long samples = 0;
        Check(client.Start());
        LastRate = rate; NonZero = 0; Peak = 0;
        if (!string.IsNullOrEmpty(readyFile)) File.WriteAllText(readyFile, DateTime.Now.ToString("o"));
        bool useStop = !string.IsNullOrEmpty(stopFile);
        var end = DateTime.UtcNow.AddSeconds(seconds);
        while (DateTime.UtcNow < end && !(useStop && File.Exists(stopFile))) {
            Thread.Sleep(10);
            uint packet; Check(cap.GetNextPacketSize(out packet));
            while (packet > 0) {
                IntPtr data; uint frames, flags; ulong dp, qp;
                Check(cap.GetBuffer(out data, out frames, out flags, out dp, out qp));
                for (uint f = 0; f < frames; f++) {
                    double sum = 0;
                    if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) == 0) {
                        for (int c = 0; c < channels; c++) {
                            IntPtr p = data + (int)((f * channels + c) * bytesPer);
                            if (isFloat && bits == 32) { float[] v = new float[1]; Marshal.Copy(p, v, 0, 1); sum += v[0]; }
                            else if (bits == 16) sum += Marshal.ReadInt16(p) / 32768.0;
                            else if (bits == 32) sum += Marshal.ReadInt32(p) / 2147483648.0;
                        }
                    }
                    double m = Math.Max(-1, Math.Min(1, sum / channels));
                    short sv = (short)(m * 32767); bw.Write(sv); samples++;
                    if (sv != 0) { NonZero++; int a = Math.Abs((int)sv); if (a > Peak) Peak = a; }
                }
                Check(cap.ReleaseBuffer(frames));
                Check(cap.GetNextPacketSize(out packet));
            }
        }
        client.Stop();
        using (var fs = File.Create(path)) {
            var w = new BinaryWriter(fs); int dataLen = (int)ms.Length;
            w.Write(new[] { 'R', 'I', 'F', 'F' }); w.Write(36 + dataLen); w.Write(new[] { 'W', 'A', 'V', 'E' });
            w.Write(new[] { 'f', 'm', 't', ' ' }); w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(rate); w.Write(rate * 2); w.Write((short)2); w.Write((short)16);
            w.Write(new[] { 'd', 'a', 't', 'a' }); w.Write(dataLen); ms.Position = 0; ms.CopyTo(fs);
        }
        return samples;
    }
    static void Check(int hr) { if (hr < 0) Marshal.ThrowExceptionForHR(hr); }
}
'@
$n = [Loopback]::Record($Wav, $Seconds, $StopFile, $ReadyFile)
$rate = [Loopback]::LastRate; $nonZero = [Loopback]::NonZero; $peak = [Loopback]::Peak
$dur = if ($rate -gt 0) { $n / [double]$rate } else { 0 }
$limit = if ($StopFile) { $dur } else { $Seconds }   # end-of-file test below: the actual duration when the stop file ended the recording
$plist = @(); foreach ($p in $Phrases) { foreach ($q in ([string]$p -split '\|')) { if ($q.Trim()) { $plist += $q.Trim() } } }
$usePhrases = $plist.Count -gt 0
Add-Type -AssemblyName System.Speech
$out = New-Object System.Collections.Generic.List[object]
if ($n -ge ($rate / 2)) {   # a WAV with no (or almost no) samples cannot be recognized; the stats still go to the JSON
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
    $rec = New-Object System.Speech.Recognition.SpeechRecognitionEngine($culture)
    $dict = New-Object System.Speech.Recognition.DictationGrammar; $dict.Name = 'dictation'
    if ($usePhrases) {
        $ch = New-Object System.Speech.Recognition.Choices
        foreach ($q in $plist) { $ch.Add($q) }
        $gb = New-Object System.Speech.Recognition.GrammarBuilder
        $gb.Culture = $culture
        $gb.AppendWildcard(); $gb.Append($ch); $gb.AppendWildcard()   # any one phrase, inside longer speech
        $pg = New-Object System.Speech.Recognition.Grammar($gb); $pg.Name = 'phrase'
        $rec.LoadGrammar($pg)
        $rec.MaxAlternates = 4
    }
    $rec.LoadGrammar($dict)
    $rec.SetInputToWaveFile($Wav)
    $nulls = 0
    while ($true) {
        # Once the WAV is consumed, Recognize throws "No audio input is supplied" instead of returning null (Dell, narrator23-a): end of input.
        try { $r = $rec.Recognize() } catch [System.Management.Automation.MethodInvocationException] { if ($_.Exception.InnerException -is [System.InvalidOperationException]) { break } else { throw } }
        if ($null -eq $r) {
            # Recognize returns null on silence or at the end of the file; stop once the stream position reaches the end.
            $nulls++
            if ($rec.AudioPosition.TotalSeconds -ge ($limit - 0.5) -or $rec.AudioState -eq 'Stopped' -or $nulls -gt 200) { break } else { continue }
        }
        $nulls = 0
        $off = [int]$r.Audio.AudioPosition.TotalMilliseconds; $dm = [int]$r.Audio.Duration.TotalMilliseconds
        $row = [ordered]@{ offsetMs = $off; durationMs = $dm; text = $r.Text; confidence = [math]::Round($r.Confidence, 3) }
        if ($usePhrases) {
            $row['grammar'] = $(if ($r.Grammar -ne $null -and $r.Grammar.Name) { $r.Grammar.Name } else { 'dictation' })
            $row['alt'] = $false
        }
        $out.Add($row)
        if ($usePhrases) {
            # when the top hypothesis came from dictation, keep phrase-grammar alternates (marked alt) so a lower-ranked phrase match is not lost
            foreach ($a in $r.Alternates) {
                try {
                    if ($a.Grammar -ne $null -and $a.Grammar.Name -eq 'phrase' -and $row['grammar'] -ne 'phrase') {
                        $out.Add([ordered]@{ offsetMs = $off; durationMs = $dm; text = $a.Text; confidence = [math]::Round($a.Confidence, 3); grammar = 'phrase'; alt = $true })
                    }
                } catch { }
            }
        }
    }
    $rec.Dispose()
}
$nzf = if ($n -gt 0) { [math]::Round($nonZero / [double]$n, 4) } else { 0 }
@{ samples = $n; seconds = $Seconds; recordedSeconds = [math]::Round($dur, 2); sampleRate = $rate; nonZeroSamples = $nonZero; nonZeroFraction = $nzf; peak = $peak; phraseMode = $usePhrases; phrases = $out } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Json -Encoding utf8
"LISTEN_DONE samples=$n phrases=$($out.Count) peak=$peak nonzero_fraction=$nzf"
