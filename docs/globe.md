# Globe view

`globe.html` shows any map in this repo as a globe:

- **Continents** are clusters: on the HARK map, one per category; on maps with orbit hubs, one per hub.
- **Islands** are the nodes. The centre node (Cannamax, NOEMA) sits at the north pole.
- **Gold strands** are the map's real edges. Faint lines are decoration only.

Open it with the **◍ Globe** button in the graph view (`index.html`); **⟵ Graph** goes back with the same map selected.

Links:

- `globe.html` opens the HARK map; `globe.html?map=<slug>` opens a map in `maps/`.
- `&focus=<node-id>` opens already flown to a node. The URL follows the focus, so a focused view can be shared.

Controls:

- drag: spin, with momentum; it settles on the nearest island or continent
- pinch / scroll: depth (globe → lens → dome → detail)
- ← → / + −: step one level
- `/`: search the index; `Esc`: clear the focus

## Village: the third view

`village-link.js` holds the Village door for both pages, including the one constant `window.villagePublicUrl`: the public
village's address, empty until it is published.

- **Public site:** the toolbar gains one button, **Village ↗**. It links to the public village in a new tab, with the focused
  continent. On the globe it stays greyed while `villagePublicUrl` is empty (on the graph it does nothing). The public pages never call `/api/` or this Mac.
- **Local mode:** the page is served from the Mac's loopback by the village feed (anim-kit `lab/agent-feed.mjs`, under
  `/map/`). The toolbar reads **Graph · Globe · Village**.
  - **Village** with a continent or island focused, or zooming on past DETAIL, dives in: one push toward the continent, a
    crossfade through white, then that continent's district of the village in a full-page layer.
  - **Esc**, or pinching out once the village is at its overview, plays it back to the globe exactly as it was.
- The May `personal-projects` map is an archive: no Village.

## History numbers: `globe-metrics.py`

The History block and the Metrics tab read `maps/metrics-hark.json` and `maps/metrics-<slug>.json`. These are built on
the maintainer's Mac from the NOEMA project index and `git log`, and contain **aggregates only**:

- first / last commit dates
- commits in 7 / 30 / 90 days
- contributor count
- a 12-week sparkline
- main/master/other branch
- uncommitted and ahead / behind counts

Never commit messages, paths, hostnames or remotes.

Re-run it whenever the map data is updated, and commit the JSON with the map change:

```
python3 globe-metrics.py
```
