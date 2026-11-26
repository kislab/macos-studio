const list = document.getElementById('list');
const status = document.getElementById('status');
const saveBtn = document.getElementById('save');
let appts = [];
let lastDownloadId = null;
const openBtn = document.getElementById('open');
openBtn.addEventListener('click', async () => {
  try { await openDownload(lastDownloadId); setStatus('Kalender wird geöffnet – Termine dort bestätigen.', 'ok'); }
  catch (e) { setStatus('Öffnen nicht möglich – bitte die Datei in den Downloads anklicken.', 'warn'); }
});

const DURATION_MIN = 20; // GSX-Termine liegen im 20-Minuten-Raster
const fullName = (a) => [a.firstName, a.lastName].filter(Boolean).join(' ');
// Titel im Kalender, z. B. „Apple Termin, Max Mustermann, iPhone“
const eventTitle = (a) => ['Apple Termin', fullName(a), a.product].filter(Boolean).join(', ');
const isToday = (d) => d.toDateString() === new Date().toDateString();
const isCancelled = (a) => /storniert|cancel/i.test(a.status);

function setStatus(text, cls) { status.textContent = text; status.className = cls || ''; }

function render() {
  list.textContent = '';
  for (const a of appts) {
    const row = document.createElement('div');
    row.className = 'appt';
    const when = document.createElement('span');
    when.className = 'when';
    when.textContent = a.start.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
    const who = document.createElement('span');
    who.className = 'who';
    who.textContent = fullName(a) || '(ohne Namen)';
    row.append(when, who);
    list.append(row);
  }
  saveBtn.disabled = !appts.length;
  saveBtn.textContent = appts.length === 1 ? '1 Termin in Kalender speichern' : `${appts.length} Termine in Kalender speichern`;
}

saveBtn.addEventListener('click', async () => {
  const events = appts.map((a) => ({
    id: a.id,
    title: eventTitle(a),
    firstName: a.firstName,
    lastName: a.lastName,
    start: a.start,
    end: new Date(a.start.getTime() + DURATION_MIN * 60000),
    notes: [
      a.product && `Produkt: ${a.product}`,
      a.serial && `Seriennummer: ${a.serial}`,
      a.id && `GSX-Termin: ${a.id}`,
    ].filter(Boolean).join('\n'),
  }));
  try {
    lastDownloadId = await downloadIcs(events, `GSX-Termine ${new Date().toLocaleDateString('de-DE')}.ics`);
    try {
      await openDownload(lastDownloadId);
      setStatus('Kalender wird geöffnet – Termine dort bestätigen.', 'ok');
    } catch {
      // Chrome hat das automatische Öffnen blockiert → ein Klick auf den Button öffnet sie
      saveBtn.hidden = true;
      openBtn.hidden = false;
      setStatus('Datei gespeichert.', 'ok');
    }
  } catch (e) {
    setStatus('Speichern fehlgeschlagen: ' + e.message, 'warn');
  }
});

(async () => {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab || !/^https:\/\/gsx2?\.apple\.com\//.test(tab.url || '')) {
      return setStatus('Bitte zuerst in GSX „Termine › Heute“ öffnen.', 'warn');
    }
    const [{ result }] = await chrome.scripting.executeScript({ target: { tabId: tab.id }, func: readGsxAppointments });
    const all = (result || []).map((a) => ({ ...a, start: new Date(a.start) }));
    const today = all.filter((a) => isToday(a.start));
    appts = today.filter((a) => !isCancelled(a)).sort((a, b) => a.start - b.start);
    const cancelled = today.length - appts.length;

    if (!all.length) return setStatus('Keine Termine gefunden – ist „Termine › Heute“ geöffnet?', 'warn');
    if (!appts.length) return setStatus('Heute keine (nicht stornierten) Termine.', 'warn');
    setStatus(`${appts.length} Termin(e) heute${cancelled ? `, ${cancelled} storniert ausgelassen` : ''}:`, 'ok');
    render();
  } catch (e) {
    setStatus('Seite konnte nicht gelesen werden: ' + e.message, 'warn');
  }
})();
