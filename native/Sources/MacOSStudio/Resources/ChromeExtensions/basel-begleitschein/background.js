// Beim ersten Installieren gleich die Einrichtung öffnen (Name + Unterschrift anlegen).
chrome.runtime.onInstalled.addListener(async ({ reason }) => {
  if (reason !== 'install') return;
  const { people } = await chrome.storage.sync.get('people');
  if (!Array.isArray(people) || !people.length) {
    chrome.tabs.create({ url: chrome.runtime.getURL('options.html?setup=1') });
  }
});
