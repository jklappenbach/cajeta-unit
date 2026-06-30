#!/usr/bin/env bash
# Build the cajeta-unit tour.
#
# Two steps, because build-tool manifest classpath plumbing is not shipped yet:
#   1. Build the dev.cajeta.unit library (.cja) with the build tool.
#   2. Compile the tour against it via --classpath.
#
# Override the compiler with CAJETA=/path/to/cajeta (defaults to `cajeta` on PATH).
set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/../.." &> /dev/null && pwd )"
CAJETA="${CAJETA:-cajeta}"

# 1. Build the library this tour links against.
( cd "$REPO_ROOT" && "$CAJETA" build )

CJA="$( ls "$REPO_ROOT"/build/archive/dev.cajeta.unit-*.cja | head -1 )"
if [[ ! -f "$CJA" ]]; then
    echo "error: dev.cajeta.unit .cja not found under $REPO_ROOT/build/archive" >&2
    exit 1
fi

# 2. Compile the tour with the library on the classpath.
cd "$SCRIPT_DIR"
mkdir -p build
"$CAJETA" --emit=exe --debug --classpath="$CJA" \
    -o build/tour tour.Tour.main src/main/cajeta build/archive

echo "built: $SCRIPT_DIR/build/tour"
