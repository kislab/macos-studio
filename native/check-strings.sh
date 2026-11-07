#!/bin/bash
# Lists texts in the Swift sources that have no English translation yet (and stale entries).
# German source texts are the keys; translations live in Localization/en.lproj/Localizable.strings.
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null 2>&1
/usr/bin/python3 -I - "$OUT" Localization/en.lproj/Localizable.strings <<'PY'
import glob, json, subprocess, sys
keys = set()
for f in glob.glob(sys.argv[1] + '/*.stringsdata'):
    if f.endswith('CoreTests.stringsdata'): continue
    for table in json.load(open(f)).get('tables', {}).values():
        keys.update(e['key'] for e in table)
done = json.loads(subprocess.run(['/usr/bin/plutil', '-convert', 'json', '-o', '-', sys.argv[2]], capture_output=True, check=True).stdout)
missing, stale = sorted(keys - done.keys()), sorted(done.keys() - keys)
for k in missing: print('MISSING:', json.dumps(k, ensure_ascii=False))
for k in stale: print('UNUSED: ', json.dumps(k, ensure_ascii=False))
print(f'{len(keys)} texts, {len(missing)} without translation, {len(stale)} unused')
sys.exit(1 if missing else 0)
PY
