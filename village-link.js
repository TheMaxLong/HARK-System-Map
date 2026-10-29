// The Village door, shared by globe.html and index.html (Graph · Globe · Village).
// Local mode = the page is served from this Mac's loopback (the village feed serves this checkout under /map/): Village
// opens the live village on the same origin. Anywhere else (the public site), Village is a link to the public village in a
// new tab, and the public site never calls this Mac.
// The public village's address: ONE constant. The public village is a snapshot the Mac publishes to GitHub Pages every
// 10 min (anim-kit lab/ecosystem/publish.mjs): a github.io page, never an address on this Mac. ?public=1 is part of it.
// Set to '' and the public pages show no Village at all (the approved look).
window.villagePublicUrl = 'https://themaxlong.github.io/village-snapshot/village.html?public=1';
window.villageLocal = /^(127\.0\.0\.1|localhost|\[::1\])$/.test(location.hostname);
// the village a map opens: the HARK map (no slug) and Personal Systems; the May personal-projects map is an archive (none)
window.villageEco = slug => !slug ? 'hark' : slug === 'personal-systems' ? 'personal' : null;
// where Village goes for an ecosystem (and a continent = a district); '' = nowhere yet
window.villageHref = (eco, district) => {
  const base = window.villageLocal ? '/village.html' : window.villagePublicUrl;
  if (!eco || !base) return '';
  const u = new URL(base, location.href); u.searchParams.set('eco', eco);
  if (district) u.searchParams.set('district', district);
  return u.href;
};
