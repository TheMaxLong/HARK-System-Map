# Assurance — proving the archives, instead of assuming them

Built 2026-07-30, the day after an eight-hour outage. Design note:
`docs/superpowers/specs/2026-07-30-proving-the-stack-design.md`.

Every failure that day had one shape: **a system reported health it had never
verified.** An alarm said the archives were empty while a 17MB backup sat in the
folder — it simply was not allowed to *list* that folder. A deploy exited 0
having written nothing. A watcher called the standby by the primary's name for
two months.

So this is not more monitoring. There was monitoring, and it lied.

## The five states

Borrowed from `alexandria`'s `docs/dossiers/*.capabilities.json`, where a
capability is a word rather than a boolean **because a boolean once produced a
false `adapterAvailable: true`**.

| state | means | what to do |
|---|---|---|
| `proven` | checked, good, evidence stored | nothing |
| `failed` | checked, genuinely bad | this is the alarm |
| `blocked` | **tried to look and could not** | fix the checker, not the system |
| `unproven` | nothing has ever checked this | a coverage hole |
| `unsupported` | does not apply here | nothing |

`blocked` is the point. An unreadable folder is not an empty one.

## Files

| file | what it does | when |
|---|---|---|
| `manifest.txt` | **the product** — every promise, in plain text | — |
| `prove-archives.sh` | checks each promise, stores command + raw output | 09:30 daily |
| `drill-alarms.sh` | deliberately breaks things, asserts the alarms notice | 09:15 daily |
| `restore-drill-monthly.sh` | restores a real archive, reads rows back | 1st, 10:00 |
| `sync-archives-external.sh` | third copy onto the external drive | on mount + 04:00 |
| `facility-archive-backup*.sh` | the four database backups | 03:00–03:45 |
| `facility-archive-staleness.sh` | freshness alarm | 09:00 daily |

The drills run **before** the prover on purpose. Find out whether the alarms can
still go red, and only then read what they report — a green board from checks
that cannot fail is worth nothing, and that is the state this was built after.

## Two things that are not in this repository

**The alert topic.** On ntfy.sh the topic name *is* the password: anyone holding
it can read every alert and send fake ones. It lives in
`~/.config/facility-assurance/ntfy-topic` (mode 600). These scripts read it from
there and have no default — missing means alerting is off, loudly.

**The archives themselves**, obviously. Three copies, two kinds of media, one
off-site: `~/facility-archives`, Google Drive, and an external drive.

## macOS traps these were built around

- A scheduled job **cannot list `~/Documents`** — it is handed an empty listing,
  not an error. That is the original sin behind the false "archive empty".
  `~/Library/CloudStorage` and removable volumes are protected the same way.
  Full Disk Access for `/bin/bash` is what lifts it.
- `grep -q` inside `set -o pipefail` reports **failure on success** — it exits at
  the first match and SIGPIPEs upstream. Use `grep -c`.
- Editing a widget's `.sh` does nothing; Übersicht reloads on `.jsx` changes only.
- `/bin/bash` on macOS is 3.2. The widget probe is written to that.

## Drills never touch a real archive

Structurally, not by care. Each drill builds a sandbox under `mktemp -d` and
hands the prover a different world via `LOCAL_ARCHIVES` / `DRIVE_ARCHIVES` /
`LOG_DIR` / `MANIFEST`. It never tells the prover where the real folders are, so
it cannot reach them. The sandbox is removed on `EXIT`, `INT` and `TERM`.

They have also been **proven able to fail**: a sabotaged copy of the prover that
called a 72-hour-old backup healthy was caught, while the other seven drills
still passed. A drill suite that has only ever passed is itself an unfired guard.
