// failover.jsx — Übersicht widget: failover readiness at a glance.
//
// Pairs with failover-probe.sh in the same folder. Read-only.
// 15-minute refresh is deliberate — see the note in failover-probe.sh before
// lowering it.

export const refreshFrequency = 900000; // 15 min

export const command = "bash failover/failover-probe.sh";

export const className = `
  top: 20px;
  right: 20px;
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
    color: #94a5a0; padding-bottom: 8px; margin-bottom: 9px;
    border-bottom: 1px solid rgba(148,165,160,0.16);
  }
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

export const render = ({ output, error }) => {
  if (error) return <div className="banner b-hold">probe error<small>{String(error)}</small></div>;
  if (!output) return <div className="muted">checking…</div>;

  let d;
  try {
    d = JSON.parse(output.trim().split("\n").pop());
  } catch (e) {
    return <div className="banner b-hold">bad probe output<small>{output.slice(0, 90)}</small></div>;
  }

  // PROMOTED_AT present === failover cannot fire. That is the headline.
  const disarmed = d.promoted === "present";
  const unknown = d.promoted === "unknown";

  const banner = disarmed
    ? { cls: "b-stop", t: "FAILOVER DISARMED", s: "PROMOTED_AT present — no auto-promotion" }
    : unknown
    ? { cls: "b-hold", t: "STATE UNKNOWN", s: "hub-backup unreachable — cannot tell" }
    : { cls: "b-clear", t: "FAILOVER ARMED", s: "marker clear" };

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

  return (
    <div>
      <div className="hd">
        <span>Failover</span>
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
