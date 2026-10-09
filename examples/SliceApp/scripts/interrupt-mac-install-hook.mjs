// Deterministic fault injection for interrupt-mac-install.sh. Loaded with NODE_OPTIONS=--import=<this file> into the
// REAL `right-release install-app` process (>= 0.2.141: stage with ditto, journal, rename-only swap). No RightKit file
// is modified. Env:
//   SLICEAPP_INTERRUPT=copy       SIGKILL install-app (and its ditto child) while ditto copies the new bundle into the
//                                 hidden staging path next to the install (journal phase "staging").
//   SLICEAPP_INTERRUPT=swap       SIGKILL install-app right after the first swap rename (installed -> backup), i.e. when
//                                 the installed path is momentarily absent (journal phase "swapping").
//   SLICEAPP_INTERRUPT=swap-term  SIGTERM install-app at the same point; its signal handler must roll the swap back.
//   SLICEAPP_INTERRUPT_MARK=<file> written (JSON) when the interruption actually fired; the caller fails without it.
// Why a hook: the swap is tens of milliseconds, so an external pgrep/kill poll never lands inside it.
import cp from "node:child_process";
import fs from "node:fs";
import { promisify } from "node:util";

const mode = process.env.SLICEAPP_INTERRUPT;
const mark = process.env.SLICEAPP_INTERRUPT_MARK;
const note = (extra) => { if (mark) fs.writeFileSync(mark, JSON.stringify({ mode, at: new Date().toISOString(), ...extra }) + "\n"); };

if (mode === "copy") {
  // install-app runs ditto through background-process.mjs execFile -> childProcess.execFile(file, args, options, callback).
  const origExecFile = cp.execFile;
  const replacement = function execFile(file, args, ...rest) {
    const child = origExecFile.call(this, file, args, ...rest);
    if (file === "/usr/bin/ditto" && String(args?.[1]).includes(".rightkit-install-") && !process.env.__SLICEAPP_FIRED) {
      process.env.__SLICEAPP_FIRED = "1";
      const dest = args[1];
      const started = Date.now();
      const tick = () => {
        const copying = fs.existsSync(dest);
        if (child.exitCode !== null || child.signalCode !== null) { note({ fired: false, reason: "ditto finished first" }); return; }
        if (copying || Date.now() - started > 250) {
          child.kill("SIGKILL");
          note({ fired: true, stagedExistedAtKill: copying, msAfterSpawn: Date.now() - started });
          process.kill(process.pid, "SIGKILL");
          return;
        }
        setImmediate(tick);
      };
      setImmediate(tick);
    }
    return child;
  };
  Object.defineProperty(replacement, promisify.custom, { value: origExecFile[promisify.custom], configurable: true });
  cp.execFile = replacement;
}

if (mode === "swap" || mode === "swap-term") {
  const orig = fs.renameSync;
  fs.renameSync = function patched(from, to) {
    const result = orig.call(this, from, to);
    if (/\.rightkit-backup-\d+\.app$/.test(String(to)) && !process.env.__SLICEAPP_FIRED) {
      process.env.__SLICEAPP_FIRED = "1";
      note({ fired: true, installedMovedTo: String(to) });
      process.kill(process.pid, mode === "swap" ? "SIGKILL" : "SIGTERM");
    }
    return result;
  };
}
