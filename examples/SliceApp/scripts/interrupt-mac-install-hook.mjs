// Deterministic fault injection for interrupt-mac-install.sh. Loaded with NODE_OPTIONS=--import=<this file> into the
// REAL `right-release install-app` process (no RightKit file is modified). Env:
//   SLICEAPP_INTERRUPT=ditto      SIGKILL the real /usr/bin/ditto child while it copies the new bundle into place.
//   SLICEAPP_INTERRUPT=installer  SIGKILL the install-app process itself right after it moved the installed bundle aside.
//   SLICEAPP_INTERRUPT_MARK=<file> written (JSON) when the interruption actually fired; the caller fails without it.
// Why a hook: the swap finishes in tens of milliseconds, so an external pgrep/kill poll (the first version of the
// script) never hit the window (R7 run 1: both modes completed with exit 0 and nothing interrupted).
import cp from "node:child_process";
import fs from "node:fs";

const mode = process.env.SLICEAPP_INTERRUPT;
const mark = process.env.SLICEAPP_INTERRUPT_MARK;
const note = (extra) => { if (mark) fs.writeFileSync(mark, JSON.stringify({ mode, at: new Date().toISOString(), ...extra }) + "\n"); };

if (mode === "ditto") {
  const orig = cp.execFile;
  cp.execFile = function patched(file, ...rest) {
    const args = Array.isArray(rest[0]) ? rest[0] : [];
    if (file === "/usr/bin/ditto" && String(args[0]).endsWith(".app") && !process.env.__SLICEAPP_FIRED) {
      const child = orig.call(this, file, ...rest);
      process.env.__SLICEAPP_FIRED = "1";
      const dest = args[1];
      const started = Date.now();
      // Kill as soon as the destination bundle directory exists (copy under way), or after 250 ms at the latest.
      const tick = () => {
        const copying = fs.existsSync(dest);
        if (child.exitCode !== null || child.signalCode !== null) { note({ fired: false, reason: "ditto finished first" }); return; }
        if (copying || Date.now() - started > 250) {
          const killed = child.kill("SIGKILL");
          note({ fired: killed, destExistedAtKill: copying, msAfterSpawn: Date.now() - started });
          return;
        }
        setImmediate(tick);
      };
      setImmediate(tick);
      return child;
    }
    return orig.call(this, file, ...rest);
  };
}

if (mode === "installer") {
  const orig = fs.renameSync;
  fs.renameSync = function patched(from, to) {
    const result = orig.call(this, from, to);
    if (String(to).includes("/.Trash/") && String(to).endsWith(".app")) {
      note({ fired: true, movedAside: String(to) });
      process.kill(process.pid, "SIGKILL");
    }
    return result;
  };
}
