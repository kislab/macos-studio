#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x 'macOS Studio.app/Contents/MacOS/MacOSStudio' ]; then
    ./native/build-app.sh
fi
open 'macOS Studio.app'
