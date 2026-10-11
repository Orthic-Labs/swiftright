import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { MagnifyingGlass } from "@phosphor-icons/react/dist/icons/MagnifyingGlass";
import { useDismiss, useExitTransition, useListNavigation } from "@rightkit/platform-ui/headless";

export interface PaletteItem {
  id: string;
  label: string;
  hint?: string; // right-aligned tag: a shortcut, "open tab", "recent", etc.
  icon?: ReactNode; // optional leading glyph (Phosphor) — decorative; label stays the match target.
  run: () => void;
}

// Subsequence fuzzy match. Returns a sort score (lower = better) or null for no match.
function score(query: string, label: string): number | null {
  const q = query.toLowerCase();
  const l = label.toLowerCase();
  if (!q) return 0;
  let qi = 0;
  let li = 0;
  let firstHit = -1;
  let gaps = 0;
  while (qi < q.length && li < l.length) {
    if (q[qi] === l[li]) {
      if (firstHit < 0) firstHit = li;
      qi++;
      li++;
    } else {
      li++;
      gaps++;
    }
  }
  return qi === q.length ? firstHit + gaps : null;
}

/** Ctrl+Shift+P quick-open + command runner. Lives in the shell (no startup cost). */
export function CommandPalette({ items, onClose }: { items: PaletteItem[]; onClose: () => void }) {
  const [q, setQ] = useState("");
  // Intercept close: play exit animation (80ms), then call onClose. Escape is handled on the
  // input's keydown (below), not a window listener. Enter runs the item, then the exit starts.
  const exit = useExitTransition({
    onActionWhileClosing: "run",
    onSyncThrow: "propagate",
    onClosed: onClose,
  });
  const closing = exit.closing;
  const close = () => void exit.close();
  const inputRef = useRef<HTMLInputElement>(null);
  const overlayRef = useRef<HTMLDivElement>(null);
  const dialogRef = useRef<HTMLDivElement>(null);
  // A click whose target is the overlay closes the palette; clicks inside the dialog never do.
  useDismiss(() => close(), {
    escape: false,
    outside: "click-target",
    container: dialogRef,
    backdrop: overlayRef,
    imeGuard: false,
  });

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const filtered = useMemo(() => {
    const scored: { it: PaletteItem; s: number }[] = [];
    for (const it of items) {
      const s = score(q, it.label);
      if (s !== null) scored.push({ it, s });
    }
    scored.sort((a, b) => a.s - b.s);
    return scored.map((x) => x.it).slice(0, 50);
  }, [q, items]);

  // Spotlight-style sections: documents (open tabs + recents) first, commands second. Score order
  // is preserved within each group; `ordered` is the flat display order the list index points into.
  const groups = useMemo(() => {
    const isDoc = (it: PaletteItem) => it.id.startsWith("tab:") || it.id.startsWith("recent:");
    return [
      { name: "Documents", items: filtered.filter(isDoc) },
      { name: "Commands", items: filtered.filter((it) => !isDoc(it)) },
    ].filter((g) => g.items.length > 0);
  }, [filtered]);
  const ordered = useMemo(() => groups.flatMap((g) => g.items), [groups]);
  // Movement, the kept index across query changes, and scroll-into-view come from the headless list hook.
  // Enter stays in the input's onKeyDown (synchronous). Home and End stay the input's caret keys.
  const nav = useListNavigation({
    count: ordered.length,
    wrap: false,
    homeEnd: false,
    keepIndexOnItemsChange: true,
    hoverSelects: "always",
    activateKeys: [],
    idPrefix: "vr-palette",
    listId: "vr-palette-results",
    scrollIntoView: true,
    scrollOn: "active-or-length",
    imeGuard: false,
    emptyIndex: "preserve",
  });
  const selIdx = nav.activeIndex;
  const inputKeys = nav.getInputProps().onKeyDown;

  const run = (it?: PaletteItem) => {
    if (!it) return;
    try {
      void exit.close(it.run);
    } catch (error) {
      // A synchronous throw leaves the transition untouched (onSyncThrow "propagate"). Start the exit as the
      // close-then-run order always did, then rethrow the same error to the same handler.
      void exit.close();
      throw error;
    }
  };

  return (
    <div
      ref={overlayRef}
      className={`fixed inset-0 z-[70] flex items-start justify-center pt-[12vh] transition-opacity duration-[80ms] ease-out ${closing ? "opacity-0" : "opacity-100"} bg-black/40`}
      style={{ transitionDelay: "0ms" }}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-label="Command palette"
        className={`vr-pop vr-pop-modal vr-glass-panel w-[680px] max-w-[92vw] overflow-hidden rounded-[28px] ${closing ? "vr-pop-exit" : ""}`}
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          // Focus can sit on a result option after Tab; Escape must close from anywhere inside.
          if (e.key === "Escape") {
            e.preventDefault();
            close();
          }
        }}
      >
        <div className="flex h-[62px] items-center gap-3 border-b border-line px-5">
          <MagnifyingGlass
            size={20}
            weight="regular"
            aria-hidden="true"
            className="shrink-0 text-muted"
          />
          <input
            ref={inputRef}
            role="combobox"
            aria-label="Search files and commands"
            aria-expanded="true"
            aria-controls="vr-palette-results"
            aria-activedescendant={ordered.length > 0 ? `vr-palette-option-${selIdx}` : undefined}
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={(e) => {
              inputKeys(e);
              if (e.key === "Enter") {
                e.preventDefault();
                run(ordered[selIdx]);
              } else if (e.key === "Escape") {
                e.preventDefault();
                close();
              }
            }}
            placeholder="Go to a file or run a command…"
            className="vr-focus min-w-0 flex-1 bg-transparent font-sans text-[22px] text-paper placeholder:text-muted-2"
          />
        </div>
        <div
          id="vr-palette-results"
          role="listbox"
          aria-label="Results"
          className="max-h-[min(56vh,520px)] overflow-auto px-2.5 pb-2.5 pt-1.5"
        >
          {ordered.length === 0 ? (
            <div className="px-4 py-3 font-sans text-xs text-muted-2">No matches.</div>
          ) : (
            (() => {
              let rowIndex = 0;
              return groups.map((g) => (
                <div key={g.name} role="group" aria-label={g.name}>
                  <div
                    aria-hidden="true"
                    className="px-3 pb-1 pt-2.5 font-sans text-[11px] font-semibold text-muted-2"
                  >
                    {g.name}
                  </div>
                  {g.items.map((it) => {
                    const i = rowIndex++;
                    const selected = i === selIdx;
                    return (
                      <button
                        type="button"
                        key={it.id}
                        id={`vr-palette-option-${i}`}
                        role="option"
                        aria-selected={selected}
                        tabIndex={-1}
                        onClick={() => run(it)}
                        onMouseMove={nav.getOptionProps(i).onMouseMove}
                        className={`vr-focus flex h-[42px] w-full items-center gap-3 rounded-xl px-3 text-left font-sans ${
                          selected ? "bg-copper/[0.16] text-paper" : "text-paper/85 hover:bg-ink/30"
                        }`}
                      >
                        {it.icon && (
                          <span
                            aria-hidden="true"
                            className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-lg ${
                              selected ? "bg-copper/20 text-copper-hi" : "bg-ink/40 text-muted"
                            }`}
                          >
                            {it.icon}
                          </span>
                        )}
                        <span className="min-w-0 flex-1 truncate text-[14px]">{it.label}</span>
                        {it.hint && (
                          <span
                            className={`ml-3 shrink-0 font-mono text-[11px] ${selected ? "text-muted" : "text-muted-2"}`}
                          >
                            {it.hint}
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
              ));
            })()
          )}
        </div>
      </div>
    </div>
  );
}
