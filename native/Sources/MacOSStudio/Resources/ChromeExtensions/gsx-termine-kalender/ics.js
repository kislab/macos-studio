// Erzeugt eine .ics-Datei (iCalendar), die der Apple Kalender per Doppelklick importiert.
// Zeiten werden als lokale Zeit Europe/Berlin geschrieben.

const TZ = 'Europe/Berlin';
const VTIMEZONE = [
  'BEGIN:VTIMEZONE',
  'TZID:Europe/Berlin',
  'BEGIN:DAYLIGHT',
  'TZOFFSETFROM:+0100', 'TZOFFSETTO:+0200', 'TZNAME:CEST',
  'DTSTART:19700329T020000', 'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU',
  'END:DAYLIGHT',
  'BEGIN:STANDARD',
  'TZOFFSETFROM:+0200', 'TZOFFSETTO:+0100', 'TZNAME:CET',
  'DTSTART:19701025T030000', 'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU',
  'END:STANDARD',
  'END:VTIMEZONE',
];

const pad = (n) => String(n).padStart(2, '0');
const localStamp = (d) => `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}T${pad(d.getHours())}${pad(d.getMinutes())}00`;
const utcStamp = (d) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
const esc = (s) => String(s || '').replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/([,;])/g, '\\$1');

// iCalendar verlangt Zeilen ≤ 75 Bytes → umbrechen
function fold(line) {
  const out = [];
  let cur = '';
  for (const ch of line) {
    if (new TextEncoder().encode(cur + ch).length > 74) { out.push(cur); cur = ' ' + ch; }
    else cur += ch;
  }
  out.push(cur);
  return out.join('\r\n');
}

/**
 * appts: [{ id, title?, firstName, lastName, start: Date, end?: Date, location?, notes? }]
 */
function buildIcs(appts) {
  const now = utcStamp(new Date());
  const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//GSX Termine//DE', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH', ...VTIMEZONE];
  for (const a of appts) {
    const end = a.end || new Date(a.start.getTime() + 30 * 60000); // Standard: 30 min
    lines.push(
      'BEGIN:VEVENT',
      `UID:gsx-${esc(a.id || localStamp(a.start) + '-' + a.lastName)}@gsx-termine`,
      `DTSTAMP:${now}`,
      `DTSTART;TZID=${TZ}:${localStamp(a.start)}`,
      `DTEND;TZID=${TZ}:${localStamp(end)}`,
      `SUMMARY:${esc(a.title || [a.firstName, a.lastName].filter(Boolean).join(' '))}`,
    );
    if (a.location) lines.push(`LOCATION:${esc(a.location)}`);
    if (a.notes) lines.push(`DESCRIPTION:${esc(a.notes)}`);
    lines.push('END:VEVENT');
  }
  lines.push('END:VCALENDAR');
  return lines.map(fold).join('\r\n') + '\r\n';
}

// Lädt die .ics-Datei herunter und gibt die Download-ID zurück, sobald die Datei fertig ist.
async function downloadIcs(appts, filename) {
  const data = 'data:text/calendar;charset=utf-8,' + encodeURIComponent(buildIcs(appts));
  const id = await chrome.downloads.download({ url: data, filename, saveAs: false, conflictAction: 'uniquify' });
  await new Promise((resolve) => {
    const check = async () => {
      const [item] = await chrome.downloads.search({ id });
      if (!item || item.state !== 'in_progress') { chrome.downloads.onChanged.removeListener(onChange); resolve(); }
    };
    const onChange = (d) => { if (d.id === id && d.state) check(); };
    chrome.downloads.onChanged.addListener(onChange);
    check();
  });
  return id;
}

// Öffnet die heruntergeladene Datei mit dem Standardprogramm (für .ics: Apple Kalender).
// Chrome erlaubt das nur direkt nach einem Klick – deshalb kann es fehlschlagen.
async function openDownload(id) {
  const r = chrome.downloads.open(id); // neuere Chrome-Versionen: Promise, ältere: Fehler über lastError
  if (r && typeof r.then === 'function') await r;
  if (chrome.runtime.lastError) throw new Error(chrome.runtime.lastError.message);
}
