// Personen (Name + Unterschrift) – gespeichert in chrome.storage.sync,
// damit sie auf allen Chrome-Geräten mit demselben Google-Konto verfügbar sind.
//
// Schema in sync:
//   people:      [{ id, name, sig }]   sig = "sync:<anzahl chunks>" | ""
//   selectedId:  id der zuletzt gewählten Person
//   sig_<id>_<n>: Teilstücke der Unterschrift als data:-URL (sync erlaubt max. 8 KB pro Eintrag)

const CHUNK = 7000;

async function getPeople() {
  const { people } = await chrome.storage.sync.get('people');
  // Alte Einträge mit eingebauter Unterschrift (frühere Version) haben keine Datei mehr
  return Array.isArray(people) ? people.map((p) => (p.sig && p.sig.startsWith('bundled:') ? { ...p, sig: '' } : p)) : [];
}

async function savePeople(people) {
  await chrome.storage.sync.set({ people });
}

async function getSelectedId() {
  const { selectedId } = await chrome.storage.sync.get('selectedId');
  return selectedId;
}

async function setSelectedId(id) {
  await chrome.storage.sync.set({ selectedId: id });
}

async function removeSigChunks(id) {
  const all = await chrome.storage.sync.get(null);
  const keys = Object.keys(all).filter((k) => k.startsWith(`sig_${id}_`));
  if (keys.length) await chrome.storage.sync.remove(keys);
}

// Speichert eine Unterschrift (data:-URL) aufgeteilt in sync und gibt den sig-Wert zurück.
async function storeSignature(id, dataUrl) {
  await removeSigChunks(id);
  const parts = {};
  let n = 0;
  for (let i = 0; i < dataUrl.length; i += CHUNK) parts[`sig_${id}_${n++}`] = dataUrl.slice(i, i + CHUNK);
  await chrome.storage.sync.set(parts);
  return `sync:${n}`;
}

// Liefert eine URL für <img src> oder '' wenn keine Unterschrift hinterlegt ist.
async function loadSignature(person) {
  if (!person || !person.sig) return '';
  if (person.sig.startsWith('sync:')) {
    const n = Number(person.sig.slice(5));
    const keys = Array.from({ length: n }, (_, i) => `sig_${person.id}_${i}`);
    const got = await chrome.storage.sync.get(keys);
    return keys.map((k) => got[k] || '').join('');
  }
  return '';
}

async function deletePerson(id) {
  const people = (await getPeople()).filter((p) => p.id !== id);
  await removeSigChunks(id);
  await savePeople(people);
  if ((await getSelectedId()) === id && people[0]) await setSelectedId(people[0].id);
}
