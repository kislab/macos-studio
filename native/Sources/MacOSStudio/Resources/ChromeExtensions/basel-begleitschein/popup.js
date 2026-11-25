const sel = document.getElementById('person');
const qty = document.getElementById('qty');
const info = document.getElementById('qtyinfo');

function setInfo(text, cls) { info.textContent = text; info.className = 'hint ' + (cls || ''); }

// Anzahl „Teile“ aus dem aktiven Tab (GSX) lesen – alle Frames, erster Treffer zählt
async function readFromTab() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab || !/^https?:/.test(tab.url || '')) return setInfo('Kein GSX-Tab aktiv – bitte Anzahl eintragen.', 'warn');
    const results = await chrome.scripting.executeScript({ target: { tabId: tab.id, allFrames: true }, func: readPartsCount });
    const hit = results.map((r) => r.result).find((v) => typeof v === 'number');
    if (hit != null) { qty.value = hit; setInfo('Aus GSX gelesen – bitte kurz prüfen.', 'ok'); }
    else setInfo('„Teile“ auf der Seite nicht gefunden – bitte Anzahl eintragen.', 'warn');
  } catch (e) {
    setInfo('Seite konnte nicht gelesen werden – bitte Anzahl eintragen.', 'warn');
  }
}

(async () => {
  const people = await getPeople();
  if (!people.length) {
    document.getElementById('main').hidden = true;
    document.getElementById('manage').hidden = true;
    document.getElementById('empty').hidden = false;
    return;
  }
  const selectedId = await getSelectedId();
  for (const p of people) sel.add(new Option(p.name, p.id, false, p.id === selectedId));
  readFromTab();
})();

sel.addEventListener('change', () => setSelectedId(sel.value));

document.getElementById('make').addEventListener('click', async () => {
  await setSelectedId(sel.value);
  const params = new URLSearchParams({ print: '1', person: sel.value, qty: qty.value.trim() });
  chrome.tabs.create({ url: chrome.runtime.getURL('form.html') + '?' + params });
});

document.getElementById('manage').addEventListener('click', () => chrome.runtime.openOptionsPage());
document.getElementById('setup').addEventListener('click', () => {
  chrome.tabs.create({ url: chrome.runtime.getURL('options.html?setup=1') });
  window.close();
});
