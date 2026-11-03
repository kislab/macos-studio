#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x 'dist/macOS Studio.app/Contents/MacOS/MacOSStudio' ]; then
    ./native/build-app.sh
fi
open 'dist/macOS Studio.app'
