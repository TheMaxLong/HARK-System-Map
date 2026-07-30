# Proving the stack — design

Written 2026-07-30, the day after an eight-hour outage.

Build it on the Pis, where the pain is real and the failures are already documented.
Once it has earned its keep there, the same tooling becomes the maintenance,
watchdog and debugging layer that ships on a HARK box.

---

## What this fixes

On 2026-07-29 a Pi died for eight hours. The outage was ordinary. What made it
expensive was everything around it, and every one of those failures had the same
shape:

> **A system reported health it had never actually verified.**

Verified examples, all from that day and the one after:

| what it said | what was true |
|---|---|
| "Facility Archive Empty" every morning | a 17MB backup was sitting in the folder; the scheduled job is not allowed to *list* `~/Documents`, and an empty listing was read as "no files" |
| deploy exited 0 | target directory was mode 555; nothing was written |
| "Pi reachable" | it was probing the *standby* while labelling it the primary — for two months |
| "identical checksums on both Pis" | they were not |
| "no code-tree drift" | six files differed; one file had been spot-checked and the result generalised |
| tests 584/584 | a file was committed *after* the run |
| cannamax "safe" | it had never once been backed up |
| two machines crashed | neither could say why — logs were volatile and died at reboot |

None of these was a system going down loudly. Every one was a system claiming a
health it had not checked, or a checker that could not see and said "fine" anyway.

**So the thing to build is not more monitoring. There was monitoring. It lied.**

---

## The core idea, and it is already ours

`alexandria` solved this in `docs/dossiers/*.capabilities.json`, merged 2026-07-30.
A capability is never a boolean, because a boolean once produced a false
`adapterAvailable: true`. It is one of four words, and it carries its evidence:

```json
"capabilities": {
  "listZones":   "proven",
  "readSensors": "blocked",
  "readSetpoints": "unsupported",
  "subscribeEvents": "unproven"
},
"provenance": "probe-confirmed",
"provenNotes": {
  "readSensors": "per-zone attribution is blocked by missing stylesheet
                  (/css/elementsDesktop.css) ... Unblocker: fetch it from the controller."
}
```

**Every health check in this system reports the same four states, with the same
meanings.** No new vocabulary is invented.

| state | means | what you do |
|---|---|---|
| `proven` | checked, and it passed, and here is the evidence | nothing |
| `unproven` | nothing has ever checked this | write the check — this is a coverage hole |
| `blocked` | tried to check and **could not see** | fix the *checker*, not the system |
| `unsupported` | cannot apply here, by design | nothing, ever |

`blocked` is the whole point. The 9 AM alarm should have said `blocked` —
*"cannot list that folder"* — instead of `fail` — *"the backups are gone"*. It fired
every morning for days and was never once right.

Two more fields ride along, both copied from the same file:

- **`provenance`** — *how* we know. `probe-confirmed` (we measured it) or
  `documented` (someone asserted it). A documented claim is not evidence. Most of
  what went wrong yesterday was `documented` wearing a green tick.
- **`provenNotes`** — plain sentences saying why a thing is in the state it is in,
  and **what would unblock it**. A `blocked` with no unblocker is half a finding.

---

## Four parts

### 1. The manifest — what must be true

One readable file listing every promise the stack makes. Not code. Data.

```
archive   hub-backup/fluxuum      off-site copy exists      < 36h
archive   hub-backup/cannamax     off-site copy exists      < 36h
archive   anderson-hub/fluxuum    off-site copy exists      < 36h
archive   anderson-hub/cannamax   off-site copy exists      < 36h
archive   deep-archive            two copies, never pruned
restore   any archive             restores and returns rows   monthly
logs      both Pis                journald persistent
failover  hub-backup              armed, and its guard exercised
data      both Pis                readings agree on any closed day
```

**This file is the product. Everything else is machinery.**

`cannamax` went unprotected for months because nothing anywhere said it should be
protected. A promise nobody wrote down cannot be broken and cannot be checked.
Adding a database means adding a line — and **a line with no checker behind it
reports `unproven`, which is itself the alert.**

### 2. The prover — checks each promise, keeps the receipt

For every line: run the check and store **the exact command, its raw output, the
state, and the timestamp.** Never a bare tick.

The reason is `deep_verify_system`'s trap 1, write ≠ read, and it bit twice this
week: "identical checksums on both Pis" was written down and false; "no drift" was
my own claim from a single spot-check. Had either carried its command and output,
both would have been obvious immediately.

Rules, each traceable to a real failure:

- **Read back from the live surface**, never trust an exit code. `verify-facility-drift`
  already does this across three surfaces and surfaces disagreement rather than
  hiding it.
- **Unreachable is `blocked`, never `pass`.** Trap 5.
- **Check the built artifact, not the source.** Trap 7 — a route that passes in
  source and never reaches `dist/` is this project's recurring failure.
- **Both machines, every time.** Trap 3 — one Pi fixed and the other broken has
  happened often enough to be a rule.

### 3. The drills — prove the alarms still fire

A guard nobody has watched fire is not a guard. The pre-drop safety guard is in
place today and its dump path has **never once executed**. `blank-boot.test.ts`
already encodes the discipline: the gate is exercised on every build, and it is
built to be able to go red.

Two tiers, deliberately:

**Cheap drills, automated, safe copies only.** Copy the archive folder, hide the
copy, confirm the alarm notices. Feed a stale receipt, confirm it shouts. Corrupt a
copied dump, confirm integrity catches it. The alarm cannot tell it is a drill;
the real archives are never involved. **If an alarm stays silent when it should
shout, that silence is the alert.**

⚠️ **The drill must run through the real scheduler, as the real user.** Every check
run by hand this morning passed; the same check under `launchd` failed, because a
scheduled job cannot read `~/Documents`. Testing by hand would have proven nothing.

**The real drill, rare, and you sit through it.** Quarterly. Kill one service at a
known time and watch what notices and what does not. The standby's web server
refusing to start because its config named the primary as an upstream — the fault
that made the standby die exactly when it was needed — is only ever found this way.

**Restore drill, monthly, and it is not optional.** `gzip -t` proves a file is not
truncated. It does **not** prove it restores. Take one archive at random, restore
it somewhere harmless, and read one real row back out. An untested backup is not a
backup.

### 4. The dead man — who watches the watcher

The outermost layer cannot check itself. Today nothing can catch
*"the scheduler stopped running at all."*

Five machines already exist: Mac, two Pis, the Beelink, the phone. **Each confirms
the next is still reporting, in a ring.** The watcher holds the timeout, so absence
of a heartbeat is the alarm. No box is the last word on its own health, and no paid
service is involved.

---

## Two cheap additions that would each have caught a real bug

**Identity assertion.** Every probe asks the machine *who are you* and compares
before believing the answer. The phone watcher spent two months probing
`hub-backup` while calling it "Anderson hub". Six lines would have caught it on the
first run.

**A linter for our own traps.** Grep our scripts for the mistakes this project keeps
repeating. Every one below has drawn blood here, three of them on 2026-07-30:

- `grep -q` inside `set -o pipefail` — exits early, SIGPIPEs upstream, reports
  failure **on success**. It rejected a known-good backup.
- `grep -r` where symlinks matter — made a live nginx dependency look absent.
- unquoted variables in zsh — a copy loop moved nothing and printed `MATCH`.
- reading a **commented-out** line as configuration — the hardware watchdog was
  reported off twice while it had been armed the whole time.
- `2>/dev/null` swallowing a real error.
- `[ -n "$VAR" ] && check` — silently *skips* the check when the variable is empty.

`deep_verify_system` already holds nine such traps, each from real history. The
linter makes that catalogue executable, and it grows by one every time something
new bites.

---

## Alert quality — a rule with teeth

An alert whose firings almost never lead to you doing something is not a nuisance,
it is a defect. The working rule: **if fewer than about one in five firings led to
an action, the alert gets rewritten or switched off.**

The "Facility Archive Empty" alarm was at zero. It fired every morning and was
never once right. Every existing alert gets held to this, not just that one.

---

## Build order

Priority is Max's: losing data, then not knowing the facility is in trouble, then
showing a wrong number.

**Layer 1 — data loss.** Manifest plus prover over the four archives. Cheap drills:
hide a folder, stale a receipt, corrupt a copy. Monthly restore drill. This is small
— a weekend, not a project — and it closes the class of failure that came nearest to
costing something irreplaceable.

**Layer 2 — blindness.** Same machinery over watchers and failover. Identity
assertion everywhere. The dead-man ring. The first real game day.

**Layer 3 — wrong numbers.** Same machinery over the data itself: the two Pis
compared row for row, values that cannot be true, sources cross-checked.

---

## Then it moves to the box

The Pis are the proving ground; the box is where this ships.

A HARK box at someone else's facility has nobody to notice it has gone quiet. It
needs exactly this and it needs it more, because the grower is not an engineer and
will not be reading logs. The same four states, the same manifest, the same drills —
reported in the plain language the box already uses.

⛔ **Nothing goes on the box until it has run on the Pis long enough to have caught
something real.** Shipping an unproven health system is precisely the failure this
document exists to prevent, and it would be a particularly embarrassing one.

Two things carry over cleanly and are worth naming now:

- `blocked` with an unblocker note is exactly what a grower needs — *"I cannot read
  this controller, and here is what would fix it"* beats a red dot.
- The box already refuses to state a room it only guessed at. Same instinct, same
  vocabulary.

---

## Explicitly out of scope

- **No paid services.** It runs on hardware already owned.
- **No automated drill ever touches a live surface.** If a guard cannot be drilled
  against a copy, it does not get an automated drill — it goes in the quarterly one
  instead. Being clever here is how a health system becomes an outage.
- **Not a dashboard.** A screen nobody opens is not a check. Output is the manifest's
  state and an alert when it changes.
- **No new vocabulary.** `proven` / `unproven` / `blocked` / `unsupported`,
  `provenance`, `provenNotes` — already ours, already justified by a real failure.

---

## Open questions

1. **Where does the prover run?** The Mac is the only machine that reaches everything
   and is not itself part of the facility, which argues for it. But it sleeps. The
   Beelink is always on and is not a Pi. Undecided.
2. **How is the manifest edited?** A hand-edited file is honest and will drift. A
   generated one cannot be read the way this design assumes.
3. **How long does evidence live?** Receipts are the thing that makes a claim
   checkable later. They are also the thing that quietly fills a disk.
