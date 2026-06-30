#!/usr/bin/env bash
# Build and run the cajeta-unit tour. Override the compiler with CAJETA=/path/to/cajeta.
set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
"$SCRIPT_DIR/build.sh"
exec "$SCRIPT_DIR/build/tour"
