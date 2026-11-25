const $ = (id) => document.getElementById(id);
const INK = [30, 55, 160]; // Blau wie Kugelschreiber
const pad = $('pad');
const ctx = pad.getContext('2d');
let drawn = false;

function setStatus(text, cls) { $('status').textContent = text; $('status').className = cls || ''; }

async function render() {
  const people = await getPeople();
  const setup = new URLSearchParams(location.search).has('setup') || !people.length;
  $('welcome').hidden = !setup || people.length > 0;
  $('title').hidden = setup && !people.length;
  $('addtitle').textContent = people.length ? 'Person hinzufügen' : 'Deine Daten';
  const list = $('list');
  list.textContent = '';
  for (const p of people) {
    const row = document.createElement('div');
    row.className = 'person';
    const name = document.createElement('span');
    name.className = 'name';
    name.textContent = p.name;
    row.append(name);
    const src = await loadSignature(p);
    if (src) { const img = document.createElement('img'); img.src = src; row.append(img); }
    else { const s = document.createElement('span'); s.className = 'nosig'; s.textContent = 'keine Unterschrift'; row.append(s); }
    const del = document.createElement('button');
    del.className = 'danger';
    del.textContent = 'Entfernen';
    del.onclick = async () => {
      if (!confirm(`„${p.name}“ entfernen?`)) return;
      await deletePerson(p.id);
      render();
    };
    row.append(del);
    list.append(row);
  }
}

// ---- Zeichenfläche ----
function resetPad() { ctx.clearRect(0, 0, pad.width, pad.height); drawn = false; }
function pos(e) { const r = pad.getBoundingClientRect(); return [(e.clientX - r.left) * pad.width / r.width, (e.clientY - r.top) * pad.height / r.height]; }
pad.addEventListener('pointerdown', (e) => {
  pad.setPointerCapture(e.pointerId);
  ctx.strokeStyle = `rgb(${INK})`; ctx.lineWidth = 3; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  ctx.beginPath(); ctx.moveTo(...pos(e)); drawn = true;
});
pad.addEventListener('pointermove', (e) => { if (e.buttons) { ctx.lineTo(...pos(e)); ctx.stroke(); } });
$('clear').onclick = () => { resetPad(); $('file').value = ''; };

// Bild hochladen: heller Hintergrund wird transparent, Tinte wird blau
$('file').addEventListener('change', async () => {
  const f = $('file').files[0];
  if (!f) return;
  const img = await createImageBitmap(f);
  resetPad();
  const s = Math.min(pad.width / img.width, pad.height / img.height);
  const w = img.width * s, h = img.height * s;
  ctx.drawImage(img, (pad.width - w) / 2, (pad.height - h) / 2, w, h);
  const d = ctx.getImageData(0, 0, pad.width, pad.height);
  for (let i = 0; i < d.data.length; i += 4) {
    const lum = (d.data[i] + d.data[i + 1] + d.data[i + 2]) / 3;
    const a = Math.max(0, Math.min(1, (200 - lum) / 90)) * (d.data[i + 3] / 255);
    d.data[i] = INK[0]; d.data[i + 1] = INK[1]; d.data[i + 2] = INK[2]; d.data[i + 3] = a * 255;
  }
  ctx.putImageData(d, 0, 0);
  drawn = true;
});

// Auf den Inhalt zuschneiden und klein genug für Chrome-Sync machen
function exportSignature() {
  const d = ctx.getImageData(0, 0, pad.width, pad.height).data;
  let x0 = pad.width, y0 = pad.height, x1 = 0, y1 = 0;
  for (let y = 0; y < pad.height; y++) for (let x = 0; x < pad.width; x++) {
    if (d[(y * pad.width + x) * 4 + 3] > 20) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
  }
  if (x1 <= x0) return '';
  const w = x1 - x0 + 1, h = y1 - y0 + 1;
  for (let maxW = 260; maxW >= 100; maxW -= 40) {
    const s = Math.min(1, maxW / w);
    const c = document.createElement('canvas');
    c.width = Math.round(w * s); c.height = Math.round(h * s);
    c.getContext('2d').drawImage(pad, x0, y0, w, h, 0, 0, c.width, c.height);
    const url = c.toDataURL('image/png');
    if (url.length < 40000) return url; // ~6 Teilstücke à 7 KB
  }
  return '';
}

$('add').onclick = async () => {
  const name = $('name').value.trim();
  if (!name) return setStatus('Bitte einen Namen eingeben.', 'err');
  try {
    const id = 'p' + Date.now().toString(36);
    let sig = '';
    if (!drawn) return setStatus('Bitte unterschreiben oder ein Bild hochladen.', 'err');
    {
      const url = exportSignature();
      if (!url) return setStatus('Unterschrift ist zu groß oder leer.', 'err');
      sig = await storeSignature(id, url);
    }
    const people = await getPeople();
    const first = !people.length;
    people.push({ id, name, sig });
    await savePeople(people);
    if (first || !(await getSelectedId())) await setSelectedId(id);
    if (first) $('done').hidden = false;
    $('name').value = ''; resetPad(); $('file').value = '';
    setStatus(`„${name}“ gespeichert.`, 'ok');
    render();
  } catch (e) {
    setStatus('Speichern fehlgeschlagen (Sync-Speicher voll?): ' + e.message, 'err');
  }
};

render();
