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
