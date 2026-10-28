const dashboardHtml = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>shorecat</title>
<style>
:root {
  --bg: #f6f5f1; --panel: #ffffff; --ink: #1d1d1b; --muted: #6b6a64;
  --line: #e2e0d8; --accent: #0f766e; --warn: #b45309; --bad: #b91c1c;
  --chip: #eeece5;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #141413; --panel: #1d1d1b; --ink: #ecebe6; --muted: #9b9a93;
    --line: #2f2e2b; --accent: #2dd4bf; --warn: #f59e0b; --bad: #f87171;
    --chip: #2a2926;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink);
  font: 14px/1.5 ui-sans-serif, system-ui, sans-serif; }
header { display: flex; gap: 12px; align-items: center; padding: 16px 24px;
  border-bottom: 1px solid var(--line); background: var(--panel); flex-wrap: wrap; }
h1 { font-size: 18px; margin: 0 auto 0 0; letter-spacing: -0.01em; }
h1 span { color: var(--accent); }
main { max-width: 1100px; margin: 0 auto; padding: 24px 16px; }
input, select, button { font: inherit; color: inherit; background: var(--panel);
  border: 1px solid var(--line); border-radius: 6px; padding: 6px 10px; }
button { cursor: pointer; }
button.primary { background: var(--accent); color: var(--bg); border-color: var(--accent); }
button.danger { color: var(--bad); }
section { background: var(--panel); border: 1px solid var(--line);
  border-radius: 10px; margin-bottom: 20px; overflow: hidden; }
section > h2 { margin: 0; padding: 12px 16px; font-size: 15px;
  border-bottom: 1px solid var(--line); display: flex; gap: 8px; align-items: baseline; }
section > h2 small { color: var(--muted); font-weight: 400; }
.release { padding: 12px 16px; border-bottom: 1px solid var(--line); }
.release:last-child { border-bottom: 0; }
.release h3 { margin: 0 0 8px; font-size: 14px; }
.wrap { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; min-width: 720px; }
th, td { text-align: left; padding: 6px 8px; border-top: 1px solid var(--line);
  vertical-align: middle; }
th { color: var(--muted); font-weight: 500; font-size: 12px; }
.chip { display: inline-block; padding: 1px 8px; border-radius: 999px;
  background: var(--chip); font-size: 12px; }
.active { color: var(--accent); } .paused { color: var(--warn); }
.rolled_back { color: var(--bad); } .draft { color: var(--muted); }
.muted { color: var(--muted); }
.actions { display: flex; gap: 6px; flex-wrap: wrap; }
.actions input { width: 70px; }
#msg { color: var(--bad); }
</style>
</head>
<body>
<header>
  <h1><span>shore</span>cat</h1>
  <input id="token" type="password" placeholder="Admin token" autocomplete="off">
  <button class="primary" id="connect">Connect</button>
  <span id="msg"></span>
</header>
<main id="apps"><p class="muted">Enter the admin token to load apps.</p></main>
<script>
const $ = (tag, attrs = {}, ...children) => {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v);
  }
  for (const c of children) el.append(c instanceof Node ? c : String(c ?? ''));
  return el;
};
const token = () => document.getElementById('token').value;
const api = async (path, init = {}) => {
  const res = await fetch(path, { ...init, headers: {
    'authorization': 'Bearer ' + token(), 'content-type': 'application/json' } });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || res.statusText);
  return body;
};
const msg = (text) => { document.getElementById('msg').textContent = text; };

async function update(release, patch, change) {
  try { await api(`/api/v1/releases/${release.id}/patches/${patch.number}`,
    { method: 'PATCH', body: JSON.stringify(change) }); msg(''); load(); }
  catch (e) { msg(e.message); }
}

function patchRow(release, patch) {
  const rollout = $('input', { type: 'number', min: 0, max: 100, value: patch.rollout_percentage });
  const archs = Object.entries(patch.artifacts)
    .map(([arch, a]) => `${arch} ${(a.delta_size / 1024).toFixed(1)} KiB`).join(', ');
  const s = patch.stats;
  return $('tr', {},
    $('td', {}, '#' + patch.number, patch.is_critical ? $('span', { class: 'chip' }, 'critical') : ''),
    $('td', {}, $('span', { class: 'chip ' + patch.status }, patch.status.replace('_', ' ')),
      patch.status_reason ? $('div', { class: 'muted' }, patch.status_reason) : ''),
    $('td', {}, patch.channel),
    $('td', {}, patch.rollout_percentage + '%'),
    $('td', {}, `${s.install_success || 0} / ${s.launch_success || 0} / ${s.boot_failure || 0}`,
      $('div', { class: 'muted' }, (patch.failure_rate * 100).toFixed(1) + '% failing')),
    $('td', { class: 'muted' }, archs, patch.notes ? $('div', {}, patch.notes) : ''),
    $('td', {}, $('div', { class: 'actions' },
      rollout,
      $('button', { onclick: () => update(release, patch, { rollout_percentage: Number(rollout.value) }) }, 'Set %'),
      patch.status === 'active'
        ? $('button', { onclick: () => update(release, patch, { status: 'paused' }) }, 'Pause')
        : patch.status !== 'draft'
          ? $('button', { onclick: () => update(release, patch, { status: 'active' }) }, 'Resume') : '',
      patch.status !== 'rolled_back' && patch.status !== 'draft'
        ? $('button', { class: 'danger', onclick: () => update(release, patch, { status: 'rolled_back' }) }, 'Roll back') : '')));
}

async function load() {
  const root = document.getElementById('apps');
  try {
    const { apps } = await api('/api/v1/apps');
    root.replaceChildren();
    if (!apps.length) root.append($('p', { class: 'muted' }, 'No apps yet. Run "shorecat init".'));
    for (const summary of apps) {
      const app = await api('/api/v1/apps/' + encodeURIComponent(summary.id));
      const section = $('section', {}, $('h2', {}, app.name, $('small', {}, app.id)));
      if (!app.releases.length) section.append($('div', { class: 'release muted' }, 'No releases yet.'));
      for (const release of app.releases.slice().reverse()) {
        const table = $('table', {}, $('tr', {},
          ...['Patch', 'Status', 'Channel', 'Rollout', 'Installs / launches / crashes', 'Artifacts', ''].map((h) => $('th', {}, h))));
        for (const patch of release.patches.slice().reverse()) table.append(patchRow(release, patch));
        section.append($('div', { class: 'release' },
          $('h3', {}, `${release.version} `, $('span', { class: 'chip' }, release.platform),
            ' ', $('span', { class: 'muted' }, Object.keys(release.artifacts).join(', '))),
          release.patches.length ? $('div', { class: 'wrap' }, table) : $('div', { class: 'muted' }, 'No patches yet.')));
      }
      root.append(section);
    }
    msg('');
    try { sessionStorage.setItem('shorecat-token', token()); } catch (_) {}
  } catch (e) { msg(e.message); }
}

document.getElementById('connect').addEventListener('click', load);
try {
  const saved = sessionStorage.getItem('shorecat-token');
  if (saved) { document.getElementById('token').value = saved; load(); }
} catch (_) {}
</script>
</body>
</html>
''';
