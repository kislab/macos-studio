// Wird per chrome.scripting in die GSX-Seite injiziert.
// Ermittelt die Anzahl der Teile einer Sammelrückgabe. Gibt eine Zahl zurück oder null.
//
// GSX zeigt die Teile in der Karte „Teile“ als AG-Grid-Tabelle (eine Zeile pro Teil).
// AG-Grid rendert bei langen Listen nicht alle Zeilen, deshalb wird bevorzugt die
// Gesamtzahl aus aria-rowcount genommen (enthält die Kopfzeile(n)).
function readPartsCount() {
  // 1) Karte „Teile“ finden
  const title = Array.from(document.querySelectorAll('h1, h2, h3, h4, .app-card__title'))
    .find((h) => /^(Teile|Parts)$/i.test((h.textContent || '').trim()));
  const card = title && (title.closest('.app-card, .item, section') || title.parentElement.parentElement);
  const grid = card && card.querySelector('[role="grid"], [role="treegrid"]');

  if (grid) {
    const dataRows = Array.from(grid.querySelectorAll('.ag-center-cols-container [role="row"], [role="rowgroup"] [row-index]'));
    const total = Number(grid.getAttribute('aria-rowcount'));
    const firstIdx = Math.min(...dataRows.map((r) => Number(r.getAttribute('aria-rowindex'))).filter((n) => n > 0));
    // aria-rowcount = Kopfzeilen + Datenzeilen; erste Datenzeile hat aria-rowindex = Kopfzeilen + 1
    if (total > 0 && Number.isFinite(firstIdx)) return total - (firstIdx - 1);
    // ohne ARIA: eindeutige Zeilenindizes zählen
    const idx = new Set(dataRows.map((r) => r.getAttribute('row-index')).filter((v) => v !== null));
    if (idx.size) return idx.size;
    if (dataRows.length) return dataRows.length;
  }

  // 2) Rückgabeaufträge („HAN…“) zählen – jedes Teil hat einen Eintrag (Nummer kann sich wiederholen)
  const han = Array.from(document.querySelectorAll('button, a, span, div, td'))
    .filter((el) => !el.querySelector('button, a, span, div, td') && /^HAN\d{5,}$/i.test((el.textContent || '').trim()));
  if (han.length) return han.length;

  // 3) Fallback: „Teile: 6“, „Teile (6)“, „6 Teile“
  const text = document.body ? document.body.innerText : '';
  const m = text.match(/\b(?:Teile|Parts)\s*[:(]\s*(\d{1,4})\b/i) || text.match(/\b(\d{1,4})\s+(?:Teile|Parts)\b/i);
  return m ? Number(m[1]) : null;
}
