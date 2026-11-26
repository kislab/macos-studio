// Löscht die exportierte .ics-Datei wieder aus den Downloads, sobald der Apple Kalender sie übernommen hat.
// Das Popup schließt sich, wenn der Kalender nach vorn kommt – deshalb erledigt das der Hintergrund-Dienst
// über einen Wecker, der auch einen Neustart von Chrome übersteht.

const DELAY_MIN = 2; // Zeit, um die Termine im Kalender zu bestätigen

async function cleanup() {
  const { pending = [] } = await chrome.storage.local.get('pending');
  const now = Date.now();
  const keep = [];
  for (const entry of pending) {
    if (entry.due > now) { keep.push(entry); continue; }
    try { await chrome.downloads.removeFile(entry.id); } catch { /* schon gelöscht oder verschoben */ }
    try { await chrome.downloads.erase({ id: entry.id }); } catch { /* nicht mehr in der Liste */ }
  }
  await chrome.storage.local.set({ pending: keep });
  if (keep.length) chrome.alarms.create('cleanup', { when: Math.min(...keep.map((e) => e.due)) });
}

chrome.runtime.onMessage.addListener((message, _sender, reply) => {
  if (message?.type !== 'cleanup' || typeof message.id !== 'number') return;
  (async () => {
    const { pending = [] } = await chrome.storage.local.get('pending');
    pending.push({ id: message.id, due: Date.now() + DELAY_MIN * 60000 });
    await chrome.storage.local.set({ pending });
    chrome.alarms.create('cleanup', { when: Math.min(...pending.map((e) => e.due)) });
    reply({ ok: true });
  })();
  return true;
});

chrome.alarms.onAlarm.addListener((alarm) => { if (alarm.name === 'cleanup') cleanup(); });
chrome.runtime.onStartup.addListener(cleanup);
