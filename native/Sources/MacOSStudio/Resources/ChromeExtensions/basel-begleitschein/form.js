// Füllt Datum (Feld 6), Name und Unterschrift der gewählten Person.
const now = new Date();
const dd = String(now.getDate()).padStart(2, '0');
const mm = String(now.getMonth() + 1).padStart(2, '0');
const yy = String(now.getFullYear()).slice(-2);
const params = new URLSearchParams(location.search);

document.getElementById('date-de').textContent = `${dd}.${mm}.${yy}`; // z. B. 25.11.26
document.getElementById('date-us').textContent = `${mm}/${dd}/${yy}`; // Feld 4, z. B. 11/25/26
document.getElementById('qty').textContent = params.get('qty') || ''; // Feld 13: Anzahl Teile aus GSX
document.getElementById('print').addEventListener('click', () => window.print());

(async () => {
  const people = await getPeople();
  const id = params.get('person') || (await getSelectedId());
  const person = people.find((p) => p.id === id) || people[0];

  document.getElementById('name').textContent = person ? person.name : '';
  document.title = `Basel_${now.getFullYear()}-${mm}-${dd}${person ? '_' + person.name : ''}`;

  const sigUrl = await loadSignature(person);
  const img = document.getElementById('sig');
  if (sigUrl) {
    img.src = sigUrl;
    await img.decode().catch(() => {});
  }
  if (params.has('print')) setTimeout(() => window.print(), 300);
})();
