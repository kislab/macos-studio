// Wird per chrome.scripting in die GSX-Terminliste injiziert (Termine › Heute).
// Liest jede Zeile anhand der Spaltenüberschriften aus und gibt eine Liste zurück:
// [{ id, firstName, lastName, start (ISO), status, product, serial }]
// Telefonnummern und Fallnummern werden bewusst nicht gelesen.
// Funktioniert mit AG-Grid (GSX) und mit normalen HTML-Tabellen.
function readGsxAppointments() {
  const clean = (s) => String(s || '').replace(/\s+/g, ' ').trim();
  const COLS = {
    id: /^(Termin|Reservation|Reservierung)$/i,
    date: /^(Datum|Date|Termin(datum|zeit)?\s*\/?\s*Uhrzeit|Start)$/i,
    status: /^Status$/i,
    first: /^(Vorname|First Name)$/i,
    last: /^(Nachname|Last Name)$/i,
    product: /^(Produkt|Product)$/i,
    serial: /^(Seriennummer|Serial Number)$/i,
  };
  const keyFor = (label) => Object.keys(COLS).find((k) => COLS[k].test(clean(label)));

  // „26.11.26 10:20“ → Date (lokale Zeit)
  const parseDate = (t) => {
    const m = clean(t).match(/(\d{1,2})\.(\d{1,2})\.(\d{2,4})\D+(\d{1,2}):(\d{2})/);
    if (!m) return null;
    const y = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
    return new Date(y, Number(m[2]) - 1, Number(m[1]), Number(m[4]), Number(m[5]));
  };

  const rows = []; // je Zeile: { key: text }

  // --- AG-Grid: Kopfzellen haben col-id, Datenzellen ebenso; Zeilen über row-index zusammenführen
  const headers = Array.from(document.querySelectorAll('.ag-header-cell[col-id]'));
  if (headers.length) {
    const colKey = {};
    for (const h of headers) {
      const k = keyFor(h.querySelector('.ag-header-cell-text')?.textContent || h.textContent);
      if (k) colKey[h.getAttribute('col-id')] = k;
    }
    const byIndex = new Map();
    for (const cell of document.querySelectorAll('.ag-row [col-id]')) {
      const k = colKey[cell.getAttribute('col-id')];
      const row = cell.closest('.ag-row');
      if (!k || !row) continue;
      const idx = row.getAttribute('row-index') ?? row.getAttribute('row-id');
      if (!byIndex.has(idx)) byIndex.set(idx, {});
      byIndex.get(idx)[k] = clean(cell.textContent);
    }
    rows.push(...byIndex.values());
  }

  // --- Normale Tabelle
  if (!rows.length) {
    for (const table of document.querySelectorAll('table')) {
      const ths = Array.from(table.querySelectorAll('thead th, tr:first-child th'));
      const keys = ths.map((th) => keyFor(th.textContent));
      if (!keys.includes('date')) continue;
      for (const tr of table.querySelectorAll('tbody tr')) {
        const r = {};
        Array.from(tr.children).forEach((td, i) => { if (keys[i]) r[keys[i]] = clean(td.textContent); });
        rows.push(r);
      }
    }
  }

  return rows
    .map((r) => {
      const start = parseDate(r.date);
      return start && {
        id: r.id || '',
        firstName: r.first || '',
        lastName: r.last || '',
        start: start.toISOString(),
        status: r.status || '',
        product: r.product || '',
        serial: r.serial || '',
      };
    })
    .filter(Boolean);
}
