// failover.jsx — Übersicht widget: failover readiness at a glance.
//
// Pairs with failover-probe.sh in the same folder. Read-only.
// 15-minute refresh is deliberate — see the note in failover-probe.sh before
// lowering it.
//
// Drag it by its title bar; the position persists across refreshes and
// restarts. Which display it appears on is NOT set here — that is a per-widget
// setting in the Übersicht menu bar. See README.

export const refreshFrequency = 900000; // 15 min

export const command = "bash failover/failover-probe.sh";

// Where it sits before it has ever been dragged. Once dragged, the saved
// position wins; reset it from the widget's console with:
//   localStorage.removeItem("failover-widget-pos")
const HOME_TOP = 20;
const HOME_RIGHT = 20;
const POS_KEY = "failover-widget-pos";

export const className = `
  top: ${HOME_TOP}px;
  right: ${HOME_RIGHT}px;
  width: 268px;
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  color: #dee8e4;
  background: rgba(13, 20, 18, 0.88);
  border: 1px solid rgba(95, 191, 165, 0.22);
  border-radius: 10px;
  padding: 13px 15px 11px;
  backdrop-filter: blur(14px);
  box-shadow: 0 8px 28px rgba(0,0,0,0.36);
  -webkit-font-smoothing: antialiased;

  .hd {
    display: flex; justify-content: space-between; align-items: baseline;
    font-size: 9.5px; letter-spacing: 0.14em; text-transform: uppercase;
    color: #94a5a0; padding: 3px 5px 8px; margin: -3px -5px 9px;
    border-bottom: 1px solid rgba(148,165,160,0.16);
    border-radius: 4px 4px 0 0;
    cursor: grab; -webkit-user-select: none; user-select: none;
  }
  /* Hover test: if this strip does NOT light up under the cursor, mouse events
     are not reaching the widget and no drag code can work — enable interaction
     for this widget from the Übersicht menu bar. */
  .hd:hover { background: rgba(95,191,165,0.13); color: #cfdcd8; }
  .hd:active { cursor: grabbing; background: rgba(95,191,165,0.2); }
  .grip { letter-spacing: 0; opacity: 0.45; }
  .hd:hover .grip { opacity: 0.9; }

  .banner {
    font-size: 12.5px; font-weight: 700; letter-spacing: 0.03em;
    padding: 7px 9px; border-radius: 5px; margin-bottom: 10px;
  }
  .banner small {
    display: block; font-size: 9.5px; font-weight: 400; letter-spacing: 0;
    opacity: 0.82; margin-top: 2px;
  }
  .b-stop  { background: rgba(232,116,106,0.14); color: #e8746a; border: 1px solid rgba(232,116,106,0.42); }
  .b-clear { background: rgba(99,190,135,0.13);  color: #63be87; border: 1px solid rgba(99,190,135,0.40); }
  .b-hold  { background: rgba(220,164,63,0.13);  color: #dca43f; border: 1px solid rgba(220,164,63,0.40); }

  .row {
    display: flex; justify-content: space-between; align-items: baseline;
    font-size: 11px; padding: 4px 0;
  }
  .k { color: #94a5a0; }
  .v { font-variant-numeric: tabular-nums; }
  .dot { display: inline-block; width: 6px; height: 6px; border-radius: 50%; margin-right: 6px; vertical-align: middle; }
  .ok   { background: #63be87; }
  .bad  { background: #e8746a; }
  .warn { background: #dca43f; }
  .muted { color: #6d7d78; }
  .ft { margin-top: 9px; padding-top: 7px; border-top: 1px solid rgba(148,165,160,0.16); font-size: 9.5px; color: #6d7d78; display: flex; justify-content: space-between; }
`;

const age = (s) => {
  if (s === null || s === undefined || s < 0) return "--";
  if (s < 90) return `${s}s`;
  if (s < 5400) return `${Math.round(s / 60)}m`;
  return `${Math.round(s / 3600)}h`;
};

// Übersicht wraps whatever render() returns in a positioned element carrying
// the className styles. Find that wrapper without assuming its exact shape:
// prefer the nearest ancestor with an id (Übersicht ids each widget), fall back
// to the nearest positioned ancestor, then to the direct parent. Never climb as
// far as body — a shared container would drag every widget at once.
const dragTarget = (el) => {
  let n = el ? el.parentElement : null;
  let positioned = null;
  for (let i = 0; n && n !== document.body && i < 5; i++) {
    if (n.id) return n;
    if (!positioned) {
      const p = window.getComputedStyle(n).position;
      if (p === "absolute" || p === "fixed") positioned = n;
    }
    n = n.parentElement;
  }
  return positioned || (el ? el.parentElement : null);
};

// Attached once per mounted element; render() runs again on every refresh.
const makeDraggable = (el) => {
  if (!el || el.dataset.dragReady === "1") return;
  const box = dragTarget(el);
  const grip = el.querySelector(".hd");
  if (!box || !grip) return;
  el.dataset.dragReady = "1";
  // Visible in the inspector, so you can confirm what is actually being moved.
  el.dataset.dragTarget = box.id || box.className || box.tagName;

  const place = (left, top) => {
    box.style.left = `${left}px`;
    box.style.top = `${top}px`;
    box.style.right = "auto";
    box.style.bottom = "auto";
  };

  try {
    const saved = JSON.parse(window.localStorage.getItem(POS_KEY) || "null");
    if (saved && typeof saved.left === "number" && typeof saved.top === "number") {
      place(saved.left, saved.top);
    }
  } catch (e) {
    /* no saved position — stay at the CSS home corner */
  }

  let startX = 0, startY = 0, baseLeft = 0, baseTop = 0;

  const onMove = (ev) => {
    // Always leave a sliver on screen so it can be grabbed again.
    const maxLeft = Math.max(0, window.innerWidth - 60);
    const maxTop = Math.max(0, window.innerHeight - 30);
    const left = Math.min(Math.max(0, baseLeft + ev.clientX - startX), maxLeft);
    const top = Math.min(Math.max(0, baseTop + ev.clientY - startY), maxTop);
    place(left, top);
  };

  const onUp = (ev) => {
    grip.removeEventListener("pointermove", onMove);
    grip.removeEventListener("pointerup", onUp);
    grip.removeEventListener("pointercancel", onUp);
    try {
      grip.releasePointerCapture(ev.pointerId);
    } catch (e) {
      /* capture already released */
    }
    try {
      window.localStorage.setItem(
        POS_KEY,
        JSON.stringify({ left: parseFloat(box.style.left), top: parseFloat(box.style.top) })
      );
    } catch (e) {
      /* still moved for this session, just not remembered */
    }
  };

  // Pointer events with capture: the drag keeps tracking even when the cursor
  // outruns the widget, which plain mousemove-on-document does not guarantee
  // inside Übersicht's desktop layer.
  grip.addEventListener("pointerdown", (ev) => {
    const r = box.getBoundingClientRect();
    startX = ev.clientX;
    startY = ev.clientY;
    baseLeft = r.left;
    baseTop = r.top;
    place(r.left, r.top); // convert a right-anchored box to left/top before moving
    try {
      grip.setPointerCapture(ev.pointerId);
    } catch (e) {
      /* older engine — listeners below still fire */
    }
    grip.addEventListener("pointermove", onMove);
    grip.addEventListener("pointerup", onUp);
    grip.addEventListener("pointercancel", onUp);
    ev.preventDefault();
  });
};

// render()'s ref fires on mount, but if Übersicht reuses the node across
// refreshes the ref may not fire again — so also retry by class. Both paths run
// through the same idempotent guard.
const armDrag = () => {
  const el = document.querySelector(".fw-root");
  if (el) makeDraggable(el);
};

// Can the failover actually promote right now? The marker alone cannot answer
// that — a masked or stopped unit cannot fire regardless of what it says, and
// showing green on the marker alone would lie in the case that matters most.
const armState = (d) => {
  const w = d.watcher || {};
  if ((d.backup || {}).up !== "up" || d.promoted === "unknown") {
    return { cls: "b-hold", t: "STATE UNKNOWN", s: "hub-backup unreachable — cannot tell" };
  }
  if (w.enabled === "masked") {
    return { cls: "b-hold", t: "FAILOVER OFF", s: "watcher masked — cannot promote" };
  }
  if (w.active !== "active") {
    return { cls: "b-hold", t: "FAILOVER OFF", s: `watcher ${w.active || "not running"}` };
  }
  if (d.promoted === "present") {
    return { cls: "b-hold", t: "FAILOVER BLOCKED", s: "running, but PROMOTED_AT present" };
  }
  return { cls: "b-clear", t: "FAILOVER ARMED", s: "watcher running, marker clear" };
};

export const render = ({ output, error }) => {
  if (error) return <div className="banner b-hold">probe error<small>{String(error)}</small></div>;
  if (!output) return <div className="muted">checking…</div>;

  let d;
  try {
    d = JSON.parse(output.trim().split("\n").pop());
  } catch (e) {
    return <div className="banner b-hold">bad probe output<small>{output.slice(0, 90)}</small></div>;
  }

  const banner = armState(d);

  // Readings staleness: the guard that did not exist during the 7/29 outage.
  const a = d.anderson || {};
  const stale = a.age >= 0 && a.age > 1800; // 30 min
  const aDot = a.up !== "up" ? "bad" : stale ? "warn" : "ok";
  const bDot = (d.backup || {}).up === "up" ? "ok" : "bad";

  const arch = d.archive || {};
  const archBad = arch.count === 0 || arch.count === -1;
  const archStale = arch.age_h >= 0 && arch.age_h > 36;
  const archDot = archBad ? "bad" : archStale ? "warn" : "ok";
  const archText =
    arch.count === -1 ? "folder missing" : arch.count === 0 ? "EMPTY" : `${arch.count} · ${arch.age_h}h old`;

  window.setTimeout(armDrag, 0);

  return (
    <div className="fw-root" ref={makeDraggable}>
      <div className="hd">
        <span>Failover <span className="grip">⠿</span></span>
        <span>{d.checked}</span>
      </div>

      <div className={`banner ${banner.cls}`}>
        {banner.t}
        <small>{banner.s}</small>
      </div>

      <div className="row">
        <span className="k"><span className={`dot ${aDot}`}></span>anderson-hub</span>
        <span className="v">{a.up === "up" ? `last ${age(a.age)}` : "DOWN"}</span>
      </div>
      <div className="row">
        <span className="k muted" style={{ paddingLeft: "12px" }}>reading</span>
        <span className="v muted">{a.last || "--"}</span>
      </div>
      <div className="row">
        <span className="k"><span className={`dot ${bDot}`}></span>hub-backup</span>
        <span className="v">{(d.backup || {}).up === "up" ? "up" : "DOWN"}</span>
      </div>
      <div className="row">
        <span className="k"><span className={`dot ${archDot}`}></span>off-site archive</span>
        <span className="v">{archText}</span>
      </div>

      <div className="ft">
        <span>15 min poll</span>
        <span>read-only</span>
      </div>
    </div>
  );
};
