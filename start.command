#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x 'dist/OS Studio.app/Contents/MacOS/MacOSStudio' ]; then
    ./native/build-app.sh
fi
open 'dist/OS Studio.app'
